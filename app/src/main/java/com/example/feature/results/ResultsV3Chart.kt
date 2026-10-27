package com.example.feature.results

import android.graphics.Paint
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.*
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.core.model.EquityPoint
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.abs

@Composable
internal fun ResultsV3Chart(points:List<EquityPoint>,days:List<TrainingDay>,mode:String="Equity",expanded:Boolean=false,onExpand:()->Unit={}) {
    var zoom by remember { mutableFloatStateOf(1f) }
    var selected by remember(points,mode){mutableStateOf<Int?>(null)}
    val visible=remember(points,zoom){points.takeLast((points.size/zoom).toInt().coerceAtLeast(2))}
    val plottedDays=remember(days,visible) {
        val from=visible.firstOrNull()?.timestamp?.let(TrainingAnalyticsCalculator::dayStart)
        val until=visible.lastOrNull()?.timestamp?.let(TrainingAnalyticsCalculator::dayStart)
        days.filter { from!=null && until!=null && it.time in from..until }
    }
    val timeline=remember(visible){ResultsChartTimeline(visible.map { it.timestamp })}
    val span=timeline.duration
    val date=remember(span){SimpleDateFormat(if(span<3_600_000L)"HH:mm:ss" else if(span<172_800_000L)"HH:mm" else "MMM dd",Locale.US)}
    fun value(p:EquityPoint)=when(mode){"Balance"->p.balance;"التراجع"->-p.drawdown;"الربح التراكمي"->p.balance-(points.firstOrNull()?.balance?:p.balance);else->p.equity}
    val selectedPoint=selected?.let{visible.getOrNull(it)}
    Box(Modifier.fillMaxWidth().height(if(expanded)340.dp else 151.dp)) {
        Canvas(Modifier.fillMaxSize().testTag("results_equity_chart")
            .pointerInput(visible){detectTapGestures { at ->
                val width=(size.width-40.dp.toPx()).coerceAtLeast(1f)
                selected=timeline.nearest((at.x/width).toDouble())
            }}
            .pointerInput(points){detectTransformGestures { _,_,change,_->zoom=(zoom*change).coerceIn(1f,8f) }}) {
            val right=40.dp.toPx();val plotW=(size.width-right).coerceAtLeast(1f)
            val labelH=14.dp.toPx();val barsH=24.dp.toPx();val plotH=(size.height-labelH-barsH).coerceAtLeast(1f)
            val vals=visible.map(::value)
            val lo=vals.minOrNull()?:0.0;val hi=vals.maxOrNull()?:1.0
            val pad=maxOf((hi-lo)*.13,abs(hi)*.002,0.01)
            val min=lo-pad;val max=hi+pad
            fun y(v:Double)=(plotH-(v-min)/(max-min)*plotH).toFloat()
            fun x(i:Int)=timeline.fraction(visible[i].timestamp).toFloat()*plotW
            val paint=Paint(Paint.ANTI_ALIAS_FLAG).apply{color=V3Muted.toArgb();textSize=8.sp.toPx();typeface=android.graphics.Typeface.create("sans-serif",0)}
            for(i in 0..4){
                val py=plotH*i/4
                drawLine(V3Border.copy(alpha=.45f),Offset(0f,py),Offset(plotW,py),.6.dp.toPx())
                drawContext.canvas.nativeCanvas.drawText(String.format(Locale.US,"%,.2f",max-(max-min)*i/4),plotW+4.dp.toPx(),py+3.dp.toPx(),paint)
            }
            for(i in 0..6){val px=plotW*i/6;drawLine(V3Border.copy(alpha=.4f),Offset(px,0f),Offset(px,plotH+barsH),.6.dp.toPx())}
            if(visible.isNotEmpty()) {
                val path=Path();val fill=Path()
                val firstX=if(visible.size==1)0f else x(0)
                path.moveTo(firstX,y(vals.first()));fill.moveTo(firstX,plotH);fill.lineTo(firstX,y(vals.first()))
                val stride=(visible.size/800).coerceAtLeast(1)
                visible.indices.filter{it%stride==0 || it==visible.lastIndex}.forEach{i->path.lineTo(x(i),y(vals[i]));fill.lineTo(x(i),y(vals[i]))}
                if(visible.size==1){path.lineTo(plotW,y(vals.first()));fill.lineTo(plotW,y(vals.first()))}
                fill.lineTo(if(visible.size==1)plotW else x(visible.lastIndex),plotH);fill.close()
                drawPath(fill,Brush.verticalGradient(listOf(V3Profit.copy(alpha=.24f),Color.Transparent),0f,plotH))
                drawPath(path,V3Profit,style=androidx.compose.ui.graphics.drawscope.Stroke(1.2.dp.toPx()))
                val lastY=y(vals.last()).coerceIn(5.dp.toPx(),plotH-4.dp.toPx())
                drawRect(V3Profit,Offset(plotW,lastY-6.dp.toPx()),androidx.compose.ui.geometry.Size(right,12.dp.toPx()))
                paint.color=Color.White.toArgb();paint.textSize=7.sp.toPx()
                drawContext.canvas.nativeCanvas.drawText(String.format(Locale.US,"%.2f",vals.last()),plotW+2.dp.toPx(),lastY+2.dp.toPx(),paint)
                paint.color=V3Muted.toArgb();paint.textSize=7.sp.toPx()
                for(i in 0..4){val text=date.format(Date(timeline.timeAt(i/4.0)));val textW=paint.measureText(text)
                    drawContext.canvas.nativeCanvas.drawText(text,(plotW*i/4-textW/2).coerceIn(0f,(plotW-textW).coerceAtLeast(0f)),size.height-1.dp.toPx(),paint)}
                selected?.takeIf { it in visible.indices }?.let{i->drawLine(V3Muted,Offset(x(i),0f),Offset(x(i),plotH),.7.dp.toPx());drawCircle(V3Profit,3.dp.toPx(),Offset(x(i),y(vals[i])))}
            }
            val maxBar=plottedDays.maxOfOrNull{abs(it.pnl)}?.coerceAtLeast(.01)?:1.0
            val slot=plotW/(plottedDays.size.coerceAtLeast(1))
            val barWidth=minOf(8.dp.toPx(),slot*.65f)
            plottedDays.forEach { day->
                // Daily totals belong at that day’s last visible observation.
                val at=visible.lastOrNull { TrainingAnalyticsCalculator.dayStart(it.timestamp)==day.time }?.timestamp ?: day.time
                val center=timeline.fraction(at).toFloat()*plotW
                val left=(center-barWidth/2).coerceIn(0f,(plotW-barWidth).coerceAtLeast(0f))
                val h=(abs(day.pnl)/maxBar*barsH*.9).toFloat();drawRect(if(day.pnl>=0)V3Profit else V3Loss,Offset(left,plotH+barsH-h),androidx.compose.ui.geometry.Size(barWidth.coerceAtLeast(1f),h))}
        }
        if(selectedPoint==null) Text(mode,color=V3Muted,fontSize=7.sp,modifier=Modifier.align(Alignment.TopStart))
        Text("صافي النتائج اليومية ($)",color=V3Muted,fontSize=7.sp,maxLines=1,modifier=Modifier.align(Alignment.BottomEnd).absolutePadding(right=44.dp,bottom=26.dp))
        if(selectedPoint!=null) Text("${date.format(Date(selectedPoint.timestamp))} · ${v3Money(value(selectedPoint))}",color=V3Text,fontSize=9.sp,modifier=Modifier.align(Alignment.TopStart))
        if(!expanded) IconButton(onClick=onExpand,modifier=Modifier.align(Alignment.BottomStart).padding(bottom=26.dp).size(22.dp).testTag("results_chart_expand")) { Icon(Icons.Default.Fullscreen,"تكبير المنحنى",tint=V3Muted,modifier=Modifier.size(16.dp)) }
    }
}
