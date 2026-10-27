package com.example

import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.data.local.AppDatabase
import com.example.feature.replay.*
import com.example.core.model.*
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TrainingRoomLedgerTest {
    @Test fun duplicateSnapshotsCommitOneExecutionAndRestoreFromRoom()=runBlocking(Dispatchers.IO) {
        val ctx=InstrumentationRegistry.getInstrumentation().targetContext
        val db=Room.inMemoryDatabaseBuilder(ctx,AppDatabase::class.java).build()
        try {
            val store=TrainingSessionStore(ctx,db)
            val owner=store.newOwner()
            val trade=TradeJournalEntry(accountId=9999,symbol="XAUUSD",side=PositionSide.SELL,volume=.01,entryPrice=2001.0,exitPrice=2000.0,profitLoss=1.0,commission=.1,openTime=1000,closeTime=2000,exitReason=ExitReason.TAKE_PROFIT)
            val state=ReplayUiState(initialBalance=100.0,currentBalance=100.9,currentEquity=100.9,closedTrades=listOf(trade))
            val snapshot=TrainingSessionSnapshot(state,emptyList(),2)
            repeat(10){store.save(snapshot,owner)}
            withTimeout(5000){while(db.trainingDao().read()?.executions?.size!=1)delay(20)}
            val at=db.trainingDao().read()!!.executions.single().recordedAt
            store.save(snapshot,owner);delay(200)
            assertEquals(1,db.trainingDao().read()!!.executions.size)
            assertEquals(at,db.trainingDao().read()!!.executions.single().recordedAt)
            assertEquals("0.9",db.trainingDao().read()!!.executions.single().netAmount)
            assertEquals(100.9,store.read()!!.state.currentBalance,0.0)
            val reopened=TrainingSessionStore(ctx,db)
            assertEquals(1,reopened.read()!!.state.closedTrades.size)
            store.clear()
        } finally {db.close()}
    }
    @Test fun migrationKeepsExistingDatabaseContent()=runBlocking(Dispatchers.IO) {
        val ctx=InstrumentationRegistry.getInstrumentation().targetContext
        val name="training-migration-${System.nanoTime()}.db"
        var db=Room.databaseBuilder(ctx,AppDatabase::class.java,name).build()
        db.openHelper.writableDatabase.execSQL("CREATE TABLE preserved_marker (id INTEGER PRIMARY KEY, value TEXT)")
        db.openHelper.writableDatabase.execSQL("INSERT INTO preserved_marker VALUES (1, 'keep')")
        db.close()
        val sqlite=android.database.sqlite.SQLiteDatabase.openDatabase(ctx.getDatabasePath(name).path,null,0)
        sqlite.execSQL("DROP TABLE training_executions");sqlite.execSQL("DROP TABLE training_checkpoints");sqlite.version=2;sqlite.close()
        db=Room.databaseBuilder(ctx,AppDatabase::class.java,name).addMigrations(AppDatabase.MIGRATION_2_3).build()
        try {val cursor=db.openHelper.writableDatabase.query("SELECT value FROM preserved_marker WHERE id=1");cursor.use{assertTrue(it.moveToFirst());assertEquals("keep",it.getString(0))};assertNull(db.trainingDao().read())}
        finally{db.close();ctx.deleteDatabase(name)}
    }
}
