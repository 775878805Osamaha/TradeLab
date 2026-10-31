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
        if(d.tool !in basic) return emptyList()
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
    /** Translate every editable anchor together, preserving the drawing's geometry. */
    fun translate(d: ChartDrawing, timeDelta: Long, priceDelta: Double): ChartDrawing {
        val original = points(d)
        if (original.isEmpty() || !priceDelta.isFinite()) return d
        val shifted = original.map { anchor ->
            val time = anchor.time + timeDelta
            val price = anchor.price + priceDelta
            if ((timeDelta > 0 && time < anchor.time) ||
                (timeDelta < 0 && time > anchor.time) ||
                time < 0 || !price.isFinite() || price <= 0.0) return d
            DrawingAnchor(time, price)
        }
        return if (d.anchors.isNotEmpty()) d.copy(
            anchors = shifted,
            startTime = shifted.first().time,
            startPrice = shifted.first().price,
            endTime = if (d.endTime != null) shifted.last().time else null,
            endPrice = if (d.endPrice != null) shifted.last().price else null
        ) else d.copy(
            startTime = shifted.first().time,
            startPrice = shifted.first().price,
            endTime = if (d.endTime != null) shifted.last().time else null,
            endPrice = if (d.endPrice != null) shifted.last().price else null
        )
    }

}
