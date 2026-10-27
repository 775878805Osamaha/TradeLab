package com.example

import android.content.Context
import android.content.ContextWrapper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.core.model.*
import com.example.feature.replay.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class TrainingSessionStoreTest {
    @Test fun restoresFundedTrainingCheckpointWithoutAnotherProviderRequest() {
        val base=InstrumentationRegistry.getInstrumentation().targetContext
        val folder=File(base.cacheDir,"training-store-test-${System.nanoTime()}").apply{mkdirs()}
        val context=object:ContextWrapper(base){override fun getFilesDir()=folder}
        val store=TrainingSessionStore(context)
        val candles=(0..2).map{Candle("XAUUSD",Timeframe.M15,(it+1)*900000L,open=2000.0,high=2001.0,low=1999.0,close=2000.0,volume=1.0,source="USER_IMPORTED")}
        val saved=TrainingSessionSnapshot(ReplayUiState(symbol="XAUUSD",initialBalance=100.0,currentBalance=99.5,currentEquity=99.2,currentIndex=1,totalCandles=3,isLoading=false,visibleCandles=candles.subList(0,2)),candles,8)
        store.save(saved,store.newOwner())
        val deadline=System.currentTimeMillis()+5000
        var read:TrainingSessionSnapshot?=null
        while(read==null && System.currentTimeMillis()<deadline){android.os.SystemClock.sleep(20);read=store.read()}
        assertNotNull(read)
        assertEquals(100.0,read!!.state.initialBalance,0.0)
        assertEquals(99.5,read.state.currentBalance,0.0)
        assertEquals(1,read.state.currentIndex)
        assertEquals(8L,read.nextId)
        assertEquals(candles,read.candles)
        assertEquals(candles.take(2),read.state.visibleCandles)
        store.clear();folder.deleteRecursively()
    }
}
