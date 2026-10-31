package com.example.feature.replay

import android.content.Context
import android.util.AtomicFile
import com.example.core.model.Candle
import com.example.core.market.DataIntegrityValidator
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.map
import java.io.*

/** Private, atomic training checkpoint; never feeds the paper execution repository. */
data class TrainingSessionSnapshot(val state: ReplayUiState,val candles: List<Candle>,val nextId: Long): Serializable

class TrainingSessionStore(context: Context, private val database:com.example.data.local.AppDatabase?=null) {
    private val file=AtomicFile(File(context.filesDir,"training-session-v1.bin"))
    private val owner=java.util.concurrent.atomic.AtomicLong(0)
    private val lock=Any()
    fun newOwner():Long=owner.incrementAndGet()
    fun clear() { owner.incrementAndGet();synchronized(lock){file.delete();database?.let { runBlocking(Dispatchers.IO) { it.trainingDao().clear() } }} }
    fun observeReports():kotlinx.coroutines.flow.Flow<com.example.core.model.ReplayReport?> =
        database?.trainingDao()?.observe()?.map { bundle ->
            if (bundle == null) null else runCatching {
                val snapshot = decode(bundle.checkpoint.payload)
                val executions = bundle.executions.sortedBy { it.ordinal }
                // A checkpoint and its executions are written in one Room transaction.
                // Reject inconsistent/corrupted snapshots rather than displaying a
                // partial journal with incorrect timestamps or account totals.
                require(executions.size == snapshot.state.closedTrades.size) {
                    "Training journal count does not match checkpoint"
                }
                require(executions.indices.all { executions[it].ordinal == it }) {
                    "Training journal ordinals are not contiguous"
                }
                TrainingReportMapper.report(snapshot, executions.map { it.recordedAt },
                    bundle.checkpoint.fundedAt)
            }.getOrElse { error ->
                android.util.Log.e("TrainingSession", "Cannot decode training report", error)
                null
            }
        } ?: kotlinx.coroutines.flow.flowOf(null)

    private val writes=Channel<Pair<Long,TrainingSessionSnapshot>>(Channel.CONFLATED)
    init { CoroutineScope(SupervisorJob()+Dispatchers.IO).launch { for((token,snapshot) in writes) { synchronized(lock) {
        if(token!=owner.get()) return@synchronized
        if(database!=null) {
            try { commitRoom(snapshot) } catch(error:Exception) { android.util.Log.e("TrainingSession","Room checkpoint failed",error) }
            return@synchronized
        }
        val stream=file.startWrite()
        try { val out=ObjectOutputStream(stream);out.writeObject(snapshot);out.flush();file.finishWrite(stream) }
        catch(error:Exception){file.failWrite(stream);android.util.Log.e("TrainingSession","Checkpoint write failed",error)}
    } } } }
    fun save(snapshot:TrainingSessionSnapshot,token:Long){
        val state=snapshot.state.copy(
            visibleCandles=ArrayList(snapshot.state.visibleCandles),
            openPositions=ArrayList(snapshot.state.openPositions),pendingOrders=ArrayList(snapshot.state.pendingOrders),
            closedTrades=ArrayList(snapshot.state.closedTrades),equitySamples=ArrayList(snapshot.state.equitySamples))
        writes.trySend(token to snapshot.copy(state=state,candles=ArrayList(snapshot.candles)))
    }
    fun read():TrainingSessionSnapshot? {
        database?.let { db ->
            val stored=runBlocking(Dispatchers.IO){db.trainingDao().read()}
            if(stored!=null) return decode(stored.checkpoint.payload)
        }
        if(!file.baseFile.exists()) return null
        return try {
            require(file.baseFile.length() <= 20_000_000)
            val value=object:ObjectInputStream(file.openRead()) {
                override fun resolveClass(desc:ObjectStreamClass):Class<*> {
                    val n=desc.name
                    require(n.startsWith("com.example.core.model.") || n in setOf("com.example.feature.replay.TrainingSessionSnapshot","com.example.feature.replay.ReplayUiState","com.example.feature.replay.ReplayEquitySample","com.example.feature.replay.ReplayInteractionMode","java.util.ArrayList","java.util.Arrays\$ArrayList","java.util.Collections\$SingletonList","java.util.Collections\$EmptyList","kotlin.collections.EmptyList","java.lang.Enum","java.lang.Number","java.lang.Integer","java.lang.Long","java.lang.Double","java.lang.Float") || n.startsWith("[Lcom.example.core.model.") || n=="[Ljava.lang.Object;")
                    return super.resolveClass(desc)
                }
            }.use{it.readObject() as TrainingSessionSnapshot}
            require(value.candles.size in 0..5000)
            if(value.candles.isNotEmpty()) require(value.state.currentIndex in value.candles.indices)
            else require(value.state.openPositions.isEmpty() && value.state.pendingOrders.isEmpty())
            require(value.state.initialBalance.isFinite() && value.state.initialBalance>0 && value.state.currentBalance.isFinite() && value.state.currentEquity.isFinite())
            if(value.candles.isNotEmpty()) require(DataIntegrityValidator.validateHistoricalSeries(value.candles).isValid)
            database?.let { runBlocking(Dispatchers.IO){commitRoom(value)} }
            value
        } catch(error:Exception){android.util.Log.e("TrainingSession","Checkpoint unavailable",error);null}
    }
    private fun decode(bytes:ByteArray):TrainingSessionSnapshot {
        val raw=ByteArrayInputStream(bytes)
        val input=if(bytes.size>2 && bytes[0]==0x1f.toByte() && bytes[1]==0x8b.toByte())java.util.zip.GZIPInputStream(raw) else raw
        return ObjectInputStream(input).use { it.readObject() as TrainingSessionSnapshot }
    }

    private fun commitRoom(snapshot:TrainingSessionSnapshot) {
        val dao=database!!.trainingDao()
        val previous=dao.read()
        val old=previous?.executions?.associateBy { it.ordinal }.orEmpty()
        val now=System.currentTimeMillis()
        val rows=snapshot.state.closedTrades.mapIndexed { index,t ->
            // Preserve a trade's original journal timestamp across balance/viewport
            // checkpoint updates, but never reuse it for a different execution.
            val at=old[index]?.takeIf {
                it.symbol==t.symbol &&
                    it.marketCloseTime==t.closeTime &&
                    it.netAmount==java.math.BigDecimal.valueOf(t.netProfitLoss).toPlainString() &&
                    it.commissionAmount==java.math.BigDecimal.valueOf(t.commission).toPlainString() &&
                    it.volume==java.math.BigDecimal.valueOf(t.volume).toPlainString()
            }?.recordedAt ?: now
            com.example.data.local.entity.TrainingExecutionEntity(ordinal=index,symbol=t.symbol,marketCloseTime=t.closeTime,recordedAt=at,
                netAmount=java.math.BigDecimal.valueOf(t.netProfitLoss).toPlainString(),commissionAmount=java.math.BigDecimal.valueOf(t.commission).toPlainString(),volume=java.math.BigDecimal.valueOf(t.volume).toPlainString())
        }
        val bytes=ByteArrayOutputStream().also { buffer ->
            val compressed=object:java.util.zip.GZIPOutputStream(buffer){init{def.setLevel(java.util.zip.Deflater.BEST_SPEED)}}
            ObjectOutputStream(compressed).use { it.writeObject(snapshot) }
        }.toByteArray()
        val initial=java.math.BigDecimal.valueOf(snapshot.state.initialBalance).toPlainString()
        val funding=previous?.checkpoint?.takeIf { it.initialAmount==initial }?.fundedAt ?: now
        dao.replace(com.example.data.local.entity.TrainingCheckpointEntity(payload=bytes,initialAmount=initial,
            balanceAmount=java.math.BigDecimal.valueOf(snapshot.state.currentBalance).toPlainString(),fundedAt=funding,updatedAt=now),rows)
    }
}
