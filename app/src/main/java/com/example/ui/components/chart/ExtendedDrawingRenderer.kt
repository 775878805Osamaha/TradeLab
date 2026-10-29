package com.example.ui.components.chart

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.*
import com.example.feature.chart.model.*
import kotlin.math.*
import java.util.Locale

/** Drawings use time/price anchors; every transform follows the current viewport. */
internal object ExtendedDrawingRenderer {
    fun draw(scope: DrawScope, d: ChartDrawing, t: ChartTransform, history: List<com.example.core.model.Candle>, vwaps: Map<Long,List<VwapPoint>>, images: Map<Long,ImageBitmap?>, profiles: Map<Long,List<CandleVolumeProfile.Bin>>) = with(scope) {
        val first = if(d.tool == DrawingTool.ANCHORED_TEXT && d.screenX != null && d.screenY != null)
            Offset(d.screenX*t.chartWidth,d.screenY*t.chartHeight)
            else Offset(t.timeToX(d.startTime) ?: return@with, t.priceToY(d.startPrice))
        val last = Offset(d.endTime?.let { t.timeToX(it) } ?: first.x, d.endPrice?.let { t.priceToY(it) } ?: first.y)
        val points = if(d.anchors.isEmpty()) listOf(first,last) else d.anchors.mapNotNull { a -> t.timeToX(a.time)?.let { Offset(it,t.priceToY(a.price)) } }
        if(points.isEmpty()) return@with
        val c = d.color; val w = d.strokeWidth
        fun line(a:Offset,b:Offset,color:Color=c) = drawLine(color,a,b,w)
        fun text(value:String, at:Offset,color:Color=c) {
            drawContext.canvas.nativeCanvas.drawText(value, at.x, at.y, android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { this.color=color.toArgb();textSize=11f*density })
        }
        fun price(v:Double) = (if(v<0) "−" else "") + QuotePriceFormatter.forSymbol(abs(v),t.visibleCandles.firstOrNull()?.symbol)
        fun arrow(a:Offset,b:Offset) {
            line(a,b);val angle=atan2((b.y-a.y).toDouble(),(b.x-a.x).toDouble()); val h=9*density
            for(sign in listOf(-1,1)) line(b,Offset(b.x-(h*cos(angle+sign*.5)).toFloat(),b.y-(h*sin(angle+sign*.5)).toFloat()))
        }
        fun polygon(p:List<Offset>, fill:Boolean=false, close:Boolean=false) {
            val path=Path().apply {moveTo(p[0].x,p[0].y);p.drop(1).forEach{lineTo(it.x,it.y)};if(close)this.close()}
            if(fill)drawPath(path,c.copy(alpha=.12f))
            drawPath(path,if(d.tool==DrawingTool.HIGHLIGHTER)c.copy(alpha=.35f) else c,
                style=Stroke(if(d.tool==DrawingTool.HIGHLIGHTER) 12*density else w, cap=StrokeCap.Round, join=StrokeJoin.Round))
        }
        when(d.tool) {
            DrawingTool.HORIZONTAL_RAY -> line(first,Offset(t.chartWidth,first.y))
            DrawingTool.RAY,DrawingTool.EXTENDED_LINE -> {
                val dx=last.x-first.x;val dy=last.y-first.y
                if(abs(dx)<.5f)line(Offset(first.x,if(d.tool==DrawingTool.RAY)first.y else 0f),Offset(first.x,t.chartHeight))
                else {val start=if(d.tool==DrawingTool.RAY) first else Offset(0f,first.y-first.x*dy/dx);val x=if(dx>=0 || d.tool==DrawingTool.EXTENDED_LINE)t.chartWidth else 0f;line(start,Offset(x,first.y+(x-first.x)*dy/dx))}
            }
            DrawingTool.ARROW -> arrow(first,last)
            DrawingTool.ARROW_MARKER -> {
                val delta=last-first;val length=delta.getDistance().coerceAtLeast(1f);val unit=delta/length;val perpendicular=Offset(-unit.y,unit.x)
                val shaft=4*density;val head=12*density;val neck=last-unit*min(22*density,length*.5f)
                polygon(listOf(first+perpendicular*shaft,neck+perpendicular*shaft,neck+perpendicular*head,last,neck-perpendicular*head,neck-perpendicular*shaft,first-perpendicular*shaft),true,true)
            }
            DrawingTool.CIRCLE -> drawCircle(c,min(abs(last.x-first.x),abs(last.y-first.y))/2,(first+last)/2f,style=Stroke(w))
            DrawingTool.DOUBLE_CURVE -> if(points.size>=5) {
                val path=Path().apply{moveTo(points[0].x,points[0].y);quadraticBezierTo(points[1].x,points[1].y,points[2].x,points[2].y);quadraticBezierTo(points[3].x,points[3].y,points[4].x,points[4].y)}
                drawPath(path,c,style=Stroke(w))
            }
            DrawingTool.CYCLES -> {
                val interval=abs(last.x-first.x).coerceAtLeast(10*density)
                var x=first.x%interval
                while(x<t.chartWidth) {line(Offset(x,0f),Offset(x,t.chartHeight),c.copy(alpha=.55f));x+=interval}
            }
            DrawingTool.FORECAST -> {arrow(first,last);text("توقع يدوي",last+Offset(0f,-8*density))}
            DrawingTool.PROJECTION -> if(points.size>=3) {polygon(points);arrow(points[1],points[2]);text("إسقاط يدوي",points[2])}
            DrawingTool.BARS_PATTERN,DrawingTool.GHOST_FEED -> {
                val bars=history.filter { it.openTime in minOf(d.startTime,d.endTime?:d.startTime)..maxOf(d.startTime,d.endTime?:d.startTime) }.takeLast(100)
                if(bars.isNotEmpty()) {
                    val high=bars.maxOf{it.high};val low=bars.minOf{it.low};val span=(high-low).coerceAtLeast(.0000001)
                    val left=min(first.x,last.x);val top=min(first.y,last.y);val width=abs(last.x-first.x).coerceAtLeast(30*density);val height=abs(last.y-first.y).coerceAtLeast(40*density)
                    fun y(v:Double)=top+((high-v)/span*height).toFloat()
                    bars.forEachIndexed { index,bar -> val x=left+(index+.5f)*width/bars.size;val alpha=if(d.tool==DrawingTool.GHOST_FEED).4f else .9f
                        drawLine(c.copy(alpha=alpha),Offset(x,y(bar.high)),Offset(x,y(bar.low)),w)
                        drawLine(c.copy(alpha=alpha),Offset(x,y(bar.open)),Offset(x,y(bar.close)),(width/bars.size*.65f).coerceAtLeast(w))
                    }
                    text("نسخة مرئية من نمط تاريخي",Offset(left,top-7*density))
                }
            }
            DrawingTool.VOLUME_PROFILE_FIXED,DrawingTool.VOLUME_PROFILE_SESSION -> {
                val bins=profiles[d.id]
                if(bins==null) { text("جاري حساب بروفايل الحجم…",first);return@with }
                val max=bins.maxOfOrNull{it.volume}?:0.0
                if(max>0) bins.forEach { bin ->
                    val y=t.priceToY(bin.price);drawLine(c.copy(alpha=.6f),Offset(first.x,y),Offset(first.x+(bin.volume/max*65*density).toFloat(),y),4*density)
                }
                text(if(max>0) "حجم الشموع عند الإغلاق · تقديري" + if(d.tool==DrawingTool.VOLUME_PROFILE_SESSION) " UTC" else "" else "لا توجد أحجام متاحة للبروفايل",first-Offset(0f,8*density))
            }
            DrawingTool.TABLE -> {
                val rows=d.text.lines().take(20).map{it.split('|').take(8)};val columns=rows.maxOfOrNull{it.size}?:1
                val cellW=65*density;val cellH=20*density
                rows.forEachIndexed{r,row->row.forEachIndexed{k,value->text(value,first+Offset(k*cellW+3*density,(r+1)*cellH-5*density))}}
                for(r in 0..rows.size)line(first+Offset(0f,r*cellH),first+Offset(columns*cellW,r*cellH))
                for(k in 0..columns)line(first+Offset(k*cellW,0f),first+Offset(k*cellW,rows.size*cellH))
            }
            DrawingTool.IMAGE -> {
                val bitmap=images[d.id]
                if(bitmap!=null)drawImage(bitmap,srcOffset=androidx.compose.ui.unit.IntOffset.Zero,srcSize=androidx.compose.ui.unit.IntSize(bitmap.width,bitmap.height),dstOffset=androidx.compose.ui.unit.IntOffset(first.x.toInt(),first.y.toInt()),dstSize=androidx.compose.ui.unit.IntSize((100*density).toInt(),(100*density*bitmap.height/bitmap.width).toInt()))
                else text(if(images.containsKey(d.id)) "الصورة غير متاحة" else "تحميل الصورة…",first)
            }
            DrawingTool.INFO_LINE -> {line(first,last); val m=MeasurementCalculator.calculate(d.startPrice,d.endPrice?:d.startPrice,d.startTime,d.endTime?:d.startTime);text("${price(m.priceDiff)} (${String.format(Locale.US,"%.2f",m.percentDiff)}%) · ${m.durationFormatted}",last)}
            DrawingTool.BRUSH,DrawingTool.HIGHLIGHTER,DrawingTool.PATH,DrawingTool.POLYLINE -> polygon(points)
            DrawingTool.TRIANGLE -> if(points.size>=3)polygon(points,true,true)
            DrawingTool.ROTATED_RECTANGLE -> if(points.size>=3)polygon(listOf(points[0],points[1],points[2],points[0]+points[2]-points[1]),true,true)
            DrawingTool.CURVE,DrawingTool.ARC -> if(points.size>=3) {
                val p=Path().apply{moveTo(points[0].x,points[0].y);quadraticBezierTo(points[1].x,points[1].y,points[2].x,points[2].y)}
                drawPath(p,c,style=Stroke(w))
            }
            DrawingTool.PARALLEL_CHANNEL -> if(points.size>=3) {
                val shift=points[2]-points[1];line(points[0],points[1]);line(points[0]+shift,points[2]);line(points[0]+shift/2f,points[1]+shift/2f,c.copy(alpha=.4f))
            }
            DrawingTool.FIB_FAN -> FibonacciCalculator.DEFAULT_LEVELS.forEach { level ->
                val at=Offset(last.x,(first.y+(last.y-first.y)*level).toFloat());line(first,at,c.copy(alpha=.65f));text(String.format(Locale.US,"%.3f",level),at)
            }
            DrawingTool.LONG_POSITION,DrawingTool.SHORT_POSITION -> if(points.size>=3) {
                val entry=points[0];val target=points[1];val stop=points[2]
                val right=maxOf(entry.x,target.x,stop.x,entry.x+80*density)
                fun zone(at:Offset,color:Color){drawRect(color.copy(alpha=.18f),Offset(entry.x,min(entry.y,at.y)),Size(right-entry.x,abs(entry.y-at.y)));line(Offset(entry.x,at.y),Offset(right,at.y),color)}
                zone(target,Color(0xFF00B7AA));zone(stop,Color(0xFFFF3D48));line(entry,Offset(right,entry.y))
                val targetPrice=d.anchors.getOrNull(1)?.price?:return@with;val stopPrice=d.anchors.getOrNull(2)?.price?:return@with
                val risk=abs(d.startPrice-stopPrice);val reward=abs(targetPrice-d.startPrice)
                val valid=if(d.tool==DrawingTool.LONG_POSITION) targetPrice>d.startPrice && stopPrice<d.startPrice else targetPrice<d.startPrice && stopPrice>d.startPrice
                text(if(valid && risk>0)"R:R ${String.format(Locale.US,"%.2f",reward/risk)} · SL ${price(stopPrice)} · TP ${price(targetPrice)}" else "SL / TP: اتجاه غير صالح",Offset(entry.x, min(target.y,stop.y)-6*density))
            }
            DrawingTool.PRICE_RANGE,DrawingTool.DATE_RANGE,DrawingTool.DATE_PRICE_RANGE -> {
                drawRect(c.copy(alpha=.12f),Offset(min(first.x,last.x),min(first.y,last.y)),Size(abs(last.x-first.x),abs(last.y-first.y)))
                arrow(first,if(d.tool==DrawingTool.PRICE_RANGE)Offset(first.x,last.y) else if(d.tool==DrawingTool.DATE_RANGE)Offset(last.x,first.y) else last)
                val m=MeasurementCalculator.calculate(d.startPrice,d.endPrice?:d.startPrice,d.startTime,d.endTime?:d.startTime)
                val label=when(d.tool){DrawingTool.DATE_RANGE->m.durationFormatted;DrawingTool.PRICE_RANGE->"${price(m.priceDiff)} (${String.format(Locale.US,"%.2f",m.percentDiff)}%)";else->"${price(m.priceDiff)} · ${m.durationFormatted}"}
                text(label,Offset(min(first.x,last.x),min(first.y,last.y)-5*density))
            }
            DrawingTool.ANCHORED_VWAP -> {
                val series = vwaps[d.id]
                if(series==null) { text("جاري حساب VWAP…",first);return@with }
                val startTime = t.visibleCandles.firstOrNull()?.openTime ?: return@with
                val endTime = t.visibleCandles.lastOrNull()?.openTime ?: return@with
                val from = series.binarySearchBy(startTime) { it.time }.let { if(it<0) -it-1 else it }.coerceAtLeast(0)
                val to = series.binarySearchBy(endTime) { it.time }.let { if(it<0) -it-1 else it+1 }.coerceAtMost(series.size)
                var previous:Offset?=null
                if(from<to) series.subList(from,to).forEach { point ->
                    t.timeToX(point.time)?.let { x -> val next=Offset(x,t.priceToY(point.price));previous?.let{line(it,next)};previous=next }
                }
                text(if(series.isNotEmpty())"VWAP" else "VWAP: لا توجد أحجام متاحة",first)
            }
            DrawingTool.CYPHER,DrawingTool.TRIANGLE_PATTERN,DrawingTool.THREE_DRIVES,DrawingTool.ELLIOTT_TRIANGLE,DrawingTool.ELLIOTT_DOUBLE,DrawingTool.ELLIOTT_TRIPLE,DrawingTool.ABCD,DrawingTool.XABCD,DrawingTool.HEAD_SHOULDERS,DrawingTool.ELLIOTT_IMPULSE,DrawingTool.ELLIOTT_CORRECTION -> {
                polygon(points)
                val labels=when(d.tool){DrawingTool.ABCD->listOf("A","B","C","D");DrawingTool.CYPHER,DrawingTool.XABCD->listOf("X","A","B","C","D");DrawingTool.TRIANGLE_PATTERN->listOf("A","B","C","D","E");DrawingTool.THREE_DRIVES->listOf("0","1","A","2","B","3","C");DrawingTool.ELLIOTT_TRIANGLE->listOf("0","A","B","C","D","E");DrawingTool.ELLIOTT_DOUBLE->listOf("0","W","A","X","B","Y","C");DrawingTool.ELLIOTT_TRIPLE->listOf("0","W","A","X","B","Y","C","X","Z");DrawingTool.ELLIOTT_IMPULSE->listOf("0","1","2","3","4","5");DrawingTool.ELLIOTT_CORRECTION->listOf("0","A","B","C");else->listOf("L","LS","N","H","N","RS","R")}
                points.forEachIndexed{i,p->drawCircle(c,3*density,p);text(labels.getOrElse(i){""},p+Offset(3*density,-7*density))}
            }
            DrawingTool.ARROW_UP,DrawingTool.ARROW_DOWN -> {val sign=if(d.tool==DrawingTool.ARROW_UP) -1 else 1;arrow(first+Offset(0f,-sign*22*density),first)}
            DrawingTool.PRICE_LABEL -> text(price(d.startPrice),first)
            DrawingTool.FLAG -> {line(first,first-Offset(0f,24*density));polygon(listOf(first-Offset(0f,24*density),first+Offset(20*density,-17*density),first-Offset(0f,10*density)),true,true)}
            DrawingTool.PIN -> {drawCircle(c,7*density,first-Offset(0f,9*density),style=Stroke(w));line(first,first-Offset(0f,2*density))}
            DrawingTool.PRICE_NOTE,DrawingTool.SIGNPOST,DrawingTool.TEXT,DrawingTool.ANCHORED_TEXT,DrawingTool.NOTE,DrawingTool.CALLOUT -> {
                if(d.tool==DrawingTool.NOTE || d.tool==DrawingTool.CALLOUT)drawRoundRect(c.copy(alpha=.15f),first-Offset(4*density,16*density),Size(max(60*density,d.text.length*7*density),22*density))
                text(if(d.tool==DrawingTool.PRICE_NOTE) "${price(d.startPrice)} · ${d.text}" else d.text,first)
            }
            else -> Unit
        }
    }
}
