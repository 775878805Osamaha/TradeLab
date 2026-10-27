package com.example.data.local.dao

import androidx.room.*
import com.example.data.local.entity.*
import kotlinx.coroutines.flow.Flow

@Dao
abstract class TrainingDao {
    @Transaction @Query("SELECT * FROM training_checkpoints WHERE id=1")
    abstract fun observe():Flow<TrainingBundle?>
    @Transaction @Query("SELECT * FROM training_checkpoints WHERE id=1")
    abstract fun read():TrainingBundle?
    @Insert(onConflict=OnConflictStrategy.REPLACE)
    abstract fun putCheckpoint(value:TrainingCheckpointEntity)
    @Insert(onConflict=OnConflictStrategy.REPLACE)
    abstract fun putExecutions(values:List<TrainingExecutionEntity>)
    @Query("DELETE FROM training_executions") abstract fun deleteExecutions()
    @Query("DELETE FROM training_checkpoints") abstract fun deleteCheckpoints()
    @Transaction open fun replace(value:TrainingCheckpointEntity, executions:List<TrainingExecutionEntity>) {
        putCheckpoint(value);deleteExecutions();putExecutions(executions)
    }
    @Transaction open fun clear(){deleteExecutions();deleteCheckpoints()}
}
