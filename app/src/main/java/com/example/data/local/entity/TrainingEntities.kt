package com.example.data.local.entity

import androidx.room.*

/** One training account, committed together with its closed executions. Decimal money is text. */
@Entity(tableName="training_checkpoints")
data class TrainingCheckpointEntity(
    @PrimaryKey val id:Int=1,
    val payload:ByteArray,
    val initialAmount:String,
    val balanceAmount:String,
    val fundedAt:Long,
    val updatedAt:Long
)
@Entity(tableName="training_executions",primaryKeys=["checkpointId","ordinal"],indices=[Index("checkpointId"),Index("recordedAt")])
data class TrainingExecutionEntity(
    val checkpointId:Int=1,val ordinal:Int,val symbol:String,val marketCloseTime:Long,
    val recordedAt:Long,val netAmount:String,val commissionAmount:String,val volume:String
)
data class TrainingBundle(
    @Embedded val checkpoint:TrainingCheckpointEntity,
    @Relation(parentColumn="id",entityColumn="checkpointId") val executions:List<TrainingExecutionEntity>
)
