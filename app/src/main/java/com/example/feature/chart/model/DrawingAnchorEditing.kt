package com.example.feature.chart.model

/** One source of truth for visible handles and the coordinates persisted after a drag. */
internal object DrawingAnchorEditing {
    private val basic=setOf(DrawingTool.TRENDLINE,DrawingTool.RECTANGLE,DrawingTool.RAY,
        DrawingTool.EXTENDED_LINE,DrawingTool.ARROW,DrawingTool.HORIZONTAL_LINE,
        DrawingTool.VERTICAL_LINE,DrawingTool.HORIZONTAL_RAY,DrawingTool.FIBONACCI,
        DrawingTool.INFO_LINE,DrawingTool.MEASUREMENT,DrawingTool.ELLIPSE,DrawingTool.CIRCLE)
    fun points(d: ChartDrawing): List<DrawingAnchor> {
        if(d.tool.isFreehand || d.tool==DrawingTool.ANCHORED_TEXT) return emptyList()
        if(d.anchors.isNotEmpty()) return d.anchors
        // Single-point annotations, price labels and imported images also have
        // a draggable placement handle; screen-anchored text remains fixed.
        if(d.tool !in basic && !d.tool.isSinglePoint) return emptyList()
        return listOfNotNull(DrawingAnchor(d.startTime,d.startPrice),
            d.endTime?.let { time -> d.endPrice?.let { DrawingAnchor(time,it) } })
    }
    fun move(d: ChartDrawing,index: Int,target: DrawingAnchor): ChartDrawing {
        val points=points(d)
        if(index !in points.indices || target.time<0 || !target.price.isFinite() || target.price<=0) return d
        val changed=points.toMutableList().apply { this[index]=target }
        return if(d.anchors.isNotEmpty()) d.copy(anchors=changed,
            startTime=changed.first().time,startPrice=changed.first().price,
            endTime=if(d.endTime!=null)changed.last().time else null,
            endPrice=if(d.endPrice!=null)changed.last().price else null)
        else if(index==0) d.copy(startTime=target.time,startPrice=target.price)
        else d.copy(endTime=target.time,endPrice=target.price)
    }

    /** Translate the whole selected shape, preserving relative price/time distances. */
    fun translate(d: ChartDrawing, deltaTime: Long, deltaPrice: Double): ChartDrawing {
        if (d.tool == DrawingTool.ANCHORED_TEXT || !deltaPrice.isFinite()) return d
        fun moveTime(value: Long): Long? = if ((deltaTime > 0 && value > Long.MAX_VALUE - deltaTime) ||
            (deltaTime < 0 && value < -deltaTime)) null else (value + deltaTime).takeIf { it >= 0L }
        fun movePrice(value: Double): Double? = (value + deltaPrice).takeIf { it.isFinite() && it > 0.0 }
        val startTime = moveTime(d.startTime) ?: return d
        val startPrice = movePrice(d.startPrice) ?: return d
        val endTime = d.endTime?.let { moveTime(it) ?: return d }
        val endPrice = d.endPrice?.let { movePrice(it) ?: return d }
        val anchors = d.anchors.map { point ->
            DrawingAnchor(moveTime(point.time) ?: return d, movePrice(point.price) ?: return d)
        }
        return d.copy(startTime=startTime,startPrice=startPrice,endTime=endTime,endPrice=endPrice,anchors=anchors)
    }
}
