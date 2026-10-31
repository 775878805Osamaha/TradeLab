package com.example.feature.chart.model

import androidx.compose.ui.geometry.Offset
import kotlin.math.*

object DrawingHitTest {
    fun distance(d: ChartDrawing, t: ChartTransform, point: Offset): Float {
        val a = if(d.tool==DrawingTool.ANCHORED_TEXT && d.screenX!=null && d.screenY!=null) Offset(d.screenX*t.chartWidth,d.screenY*t.chartHeight)
            else Offset(t.timeToX(d.startTime)?:return Float.MAX_VALUE,t.priceToY(d.startPrice))
        val b = Offset(d.endTime?.let{t.timeToX(it)}?:a.x,d.endPrice?.let{t.priceToY(it)}?:a.y)
        if (!point.x.isFinite() || !point.y.isFinite() ||
            !a.x.isFinite() || !a.y.isFinite() ||
            !b.x.isFinite() || !b.y.isFinite()) return Float.MAX_VALUE
        fun segment(start:Offset,end:Offset, mode:Int=0):Float {
            if (!start.x.isFinite() || !start.y.isFinite() ||
                !end.x.isFinite() || !end.y.isFinite()) return Float.MAX_VALUE
            val delta=end-start;val len=delta.getDistanceSquared()
            if (!len.isFinite()) return Float.MAX_VALUE
            val raw=if(len>0) ((point-start).x*delta.x+(point-start).y*delta.y)/len else 0f
            val f=when(mode){1->raw;2->raw.coerceAtLeast(0f);else->raw.coerceIn(0f,1f)}
            return (point-(start+delta*f)).getDistance()
        }
        return when(d.tool) {
            DrawingTool.HORIZONTAL_LINE -> abs(point.y-a.y)
            DrawingTool.HORIZONTAL_RAY -> segment(a,Offset(t.chartWidth,a.y))
            DrawingTool.VERTICAL_LINE -> abs(point.x-a.x)
            DrawingTool.EXTENDED_LINE -> segment(a,b,1)
            DrawingTool.RAY -> segment(a,b,2)
            DrawingTool.RECTANGLE -> listOf(a,Offset(b.x,a.y),b,Offset(a.x,b.y),a).zipWithNext().minOf{segment(it.first,it.second)}
            DrawingTool.CIRCLE, DrawingTool.ELLIPSE -> {
                val center=(a+b)/2f;val radiusX=abs(b.x-a.x)/2f;val radiusY=abs(b.y-a.y)/2f
                if(d.tool==DrawingTool.CIRCLE) abs((point-center).getDistance()-min(radiusX,radiusY))
                else if(radiusX<1f||radiusY<1f)segment(a,b) else abs(sqrt(((point.x-center.x)/radiusX).pow(2)+((point.y-center.y)/radiusY).pow(2))-1f)*min(radiusX,radiusY)
            }
            else -> {
                val anchors=d.anchors.mapNotNull { p -> t.timeToX(p.time)?.let{Offset(it,t.priceToY(p.price))} }
                val closed=d.tool in setOf(DrawingTool.TRIANGLE,DrawingTool.ROTATED_RECTANGLE)
                val points=if(closed && anchors.size>2)anchors+anchors.first() else anchors
                if(points.size>1)points.zipWithNext().minOf{segment(it.first,it.second)}
                else if(points.size==1) (point-points.first()).getDistance()
                else if(d.tool.isSinglePoint) (point-a).getDistance() else segment(a,b)
            }
        }
    }
}
