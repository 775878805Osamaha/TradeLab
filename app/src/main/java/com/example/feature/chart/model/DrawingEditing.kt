package com.example.feature.chart.model

import androidx.compose.ui.geometry.Offset

/** Geometry for direct manipulation; all saved coordinates stay in market space. */
object DrawingEditing {
    fun handles(d:ChartDrawing,t:ChartTransform):List<Offset> {
        val a=if(d.tool==DrawingTool.ANCHORED_TEXT && d.screenX!=null && d.screenY!=null)
            Offset(d.screenX*t.chartWidth,d.screenY*t.chartHeight)
        else Offset(t.timeToX(d.startTime)?:return emptyList(),t.priceToY(d.startPrice))
        val b=Offset(d.endTime?.let(t::timeToX)?:a.x,d.endPrice?.let(t::priceToY)?:a.y)
        if(d.tool==DrawingTool.RECTANGLE) return listOf(a,Offset((a.x+b.x)/2,a.y),Offset(b.x,a.y),Offset(b.x,(a.y+b.y)/2),b,Offset((a.x+b.x)/2,b.y),Offset(a.x,b.y),Offset(a.x,(a.y+b.y)/2))
        val anchors=if(d.tool.isFreehand && d.anchors.size>2)listOf(d.anchors.first(),d.anchors.last()) else d.anchors
        return if(anchors.isNotEmpty())anchors.mapNotNull { p->t.timeToX(p.time)?.let { Offset(it,t.priceToY(p.price)) } }
        else if(d.endTime!=null && d.endPrice!=null)listOf(a,b) else listOf(a)
    }
    fun handleAt(d:ChartDrawing,t:ChartTransform,p:Offset,radius:Float):Int? =
        handles(d,t).withIndex().minByOrNull { (it.value-p).getDistance() }?.takeIf { (it.value-p).getDistance()<=radius }?.index?.let { if(d.tool.isFreehand && d.anchors.size>2 && it==1)d.anchors.lastIndex else it }

    fun drag(d:ChartDrawing,t:ChartTransform,origin:Offset,current:Offset,handle:Int?):ChartDrawing {
        if(d.isLocked)return d
        if(d.tool==DrawingTool.ANCHORED_TEXT) return d.copy(screenX=(current.x/t.chartWidth).coerceIn(0f,1f),screenY=(current.y/t.chartHeight).coerceIn(0f,1f))
        val delta=current-origin
        val points=d.anchors.ifEmpty { listOfNotNull(DrawingAnchor(d.startTime,d.startPrice),d.endTime?.let { time->d.endPrice?.let { DrawingAnchor(time,it) } }) }
        fun moved(a:DrawingAnchor,dx:Float,dy:Float):DrawingAnchor {
            val x=t.timeToX(a.time)?:return a
            return DrawingAnchor(t.drawingTimeAtX(x+dx),t.yToPrice(t.priceToY(a.price)+dy))
        }
        val next=if(d.tool==DrawingTool.RECTANGLE && handle!=null && points.size>=2) {
            val a=points.first();val b=points.last()
            val aa=moved(a,if(handle in listOf(0,6,7))delta.x else 0f,if(handle in listOf(0,1,2))delta.y else 0f)
            val bb=moved(b,if(handle in listOf(2,3,4))delta.x else 0f,if(handle in listOf(4,5,6))delta.y else 0f)
            listOf(aa,bb)
        } else points.mapIndexed { i,a->if(handle==null || handle==i)moved(a,delta.x,delta.y) else a }
        if(next.any { !it.price.isFinite() || it.price<=0 || it.time<0 })return d
        return d.copy(startTime=next.first().time,startPrice=next.first().price,
            endTime=if(d.endTime!=null)next.last().time else null,endPrice=if(d.endPrice!=null)next.last().price else null,
            anchors=if(d.anchors.isEmpty())emptyList() else next)
    }
}
