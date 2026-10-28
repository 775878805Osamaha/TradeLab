package com.example.feature.chart.model

import androidx.compose.ui.geometry.Offset
import kotlin.math.*

object DrawingHitTest {
    fun distance(d: ChartDrawing, t: ChartTransform, point: Offset, density:Float = 1f): Float {
        val a = if(d.tool==DrawingTool.ANCHORED_TEXT && d.screenX!=null && d.screenY!=null) Offset(d.screenX*t.chartWidth,d.screenY*t.chartHeight)
            else Offset(t.timeToX(d.startTime)?:return Float.MAX_VALUE,t.priceToY(d.startPrice))
        val b = Offset(d.endTime?.let{t.timeToX(it)}?:a.x,d.endPrice?.let{t.priceToY(it)}?:a.y)
        fun segment(start:Offset,end:Offset, mode:Int=0):Float {
            val delta=end-start;val len=delta.getDistanceSquared()
            val raw=if(len>0) ((point-start).x*delta.x+(point-start).y*delta.y)/len else 0f
            val f=when(mode){1->raw;2->raw.coerceAtLeast(0f);else->raw.coerceIn(0f,1f)}
            return (point-(start+delta*f)).getDistance()
        }
        fun insidePolygon(vertices:List<Offset>):Boolean {
            if(vertices.size<3)return false
            var inside=false
            var previous=vertices.last()
            for(next in vertices) {
                if((next.y>point.y)!=(previous.y>point.y) && point.x<(previous.x-next.x)*(point.y-next.y)/(previous.y-next.y)+next.x)inside=!inside
                previous=next
            }
            return inside
        }
        val anchors=d.anchors.mapNotNull { p -> t.timeToX(p.time)?.let{Offset(it,t.priceToY(p.price))} }
        // Flatten the rendered quadratic, not its control-point polygon. The latter
        // makes empty space selectable while missing the actual curve.
        fun quadratic(start:Offset,control:Offset,end:Offset,depth:Int=0):Float {
            val chord=end-start
            val lengthSquared=chord.getDistanceSquared()
            val projection=if(lengthSquared>0f) {
                val relative=control-start
                ((relative.x*chord.x+relative.y*chord.y)/lengthSquared).coerceIn(0f,1f)
            } else 0f
            val flatness=(control-(start+chord*projection)).getDistance()
            if(depth>=12 || flatness<=.5f)return segment(start,end)
            val left=(start+control)/2f;val right=(control+end)/2f;val middle=(left+right)/2f
            return min(quadratic(start,left,middle,depth+1),quadratic(middle,right,end,depth+1))
        }
        return when(d.tool) {
            DrawingTool.CURVE,DrawingTool.ARC -> if(anchors.size>=3)quadratic(anchors[0],anchors[1],anchors[2]) else Float.MAX_VALUE
            DrawingTool.DOUBLE_CURVE -> if(anchors.size>=5)min(quadratic(anchors[0],anchors[1],anchors[2]),quadratic(anchors[2],anchors[3],anchors[4])) else Float.MAX_VALUE
            DrawingTool.PARALLEL_CHANNEL -> if(anchors.size>=3) {
                val shift=anchors[2]-anchors[1]
                minOf(segment(anchors[0],anchors[1]),segment(anchors[0]+shift,anchors[2]),segment(anchors[0]+shift/2f,anchors[1]+shift/2f))
            } else Float.MAX_VALUE
            DrawingTool.FIB_FAN -> FibonacciCalculator.DEFAULT_LEVELS.minOf { level -> segment(a,Offset(b.x,(a.y+(b.y-a.y)*level).toFloat())) }
            DrawingTool.CYCLES -> {
                val interval=abs(b.x-a.x).coerceAtLeast(10*density)
                val first=a.x%interval
                val lastIndex=floor((t.chartWidth-first)/interval).toInt().coerceAtLeast(0)
                val index=round((point.x-first)/interval).toInt().coerceIn(0,lastIndex)
                segment(Offset(first+index*interval,0f),Offset(first+index*interval,t.chartHeight))
            }
            DrawingTool.HORIZONTAL_LINE -> abs(point.y-a.y)
            DrawingTool.HORIZONTAL_RAY -> segment(a,Offset(t.chartWidth,a.y))
            DrawingTool.VERTICAL_LINE -> abs(point.x-a.x)
            DrawingTool.EXTENDED_LINE -> segment(a,b,1)
            DrawingTool.RAY -> segment(a,b,2)
            DrawingTool.FIBONACCI -> FibonacciCalculator.calculateLevels(d.startPrice,d.endPrice?:d.startPrice).minOf { (_,price)->abs(point.y-t.priceToY(price)) }
            DrawingTool.LONG_POSITION,DrawingTool.SHORT_POSITION -> {
                val ps=DrawingEditing.handles(d,t)
                if(ps.size<3)segment(a,b) else {
                    val right=DrawingEditing.positionRight(ps,density)
                    if(point.x in a.x..right && point.y in ps.minOf { it.y }..ps.maxOf { it.y })0f
                    else ps.minOf { segment(Offset(a.x,it.y),Offset(right,it.y)) }
                }
            }
            DrawingTool.RECTANGLE,DrawingTool.PRICE_RANGE,DrawingTool.DATE_RANGE,DrawingTool.DATE_PRICE_RANGE -> if(point.x in min(a.x,b.x)..max(a.x,b.x) && point.y in min(a.y,b.y)..max(a.y,b.y))0f else listOf(a,Offset(b.x,a.y),b,Offset(a.x,b.y),a).zipWithNext().minOf{segment(it.first,it.second)}
            DrawingTool.CIRCLE, DrawingTool.ELLIPSE -> {
                val center=(a+b)/2f;val radiusX=abs(b.x-a.x)/2f;val radiusY=abs(b.y-a.y)/2f
                if(d.tool==DrawingTool.CIRCLE) {
                    val distance=(point-center).getDistance();val radius=min(radiusX,radiusY)
                    if(d.fillOpacity>0f && distance<=radius)0f else abs(distance-radius)
                } else if(radiusX<1f||radiusY<1f)segment(a,b) else {
                    val radius=sqrt(((point.x-center.x)/radiusX).pow(2)+((point.y-center.y)/radiusY).pow(2))
                    if(d.fillOpacity>0f && radius<=1f)0f else abs(radius-1f)*min(radiusX,radiusY)
                }
            }
            else -> {
                val closed=d.tool in setOf(DrawingTool.TRIANGLE,DrawingTool.ROTATED_RECTANGLE)
                val vertices=if(d.tool==DrawingTool.ROTATED_RECTANGLE && anchors.size>=3)listOf(anchors[0],anchors[1],anchors[2],anchors[0]+anchors[2]-anchors[1]) else anchors
                val points=if(closed && vertices.size>2)vertices+vertices.first() else vertices
                if(closed && d.fillOpacity>0f && insidePolygon(vertices))0f
                else if(points.size>1)points.zipWithNext().minOf{segment(it.first,it.second)}
                else if(d.tool.isSinglePoint) (point-a).getDistance() else segment(a,b)
            }
        }
    }
}
