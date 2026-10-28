package com.example.feature.chart.model

import androidx.compose.ui.unit.IntSize

/** The decoded aspect ratio and the same pixel rounding drive rendering and touch. */
object DrawingImageGeometry {
    fun size(width:Int,height:Int,density:Float):IntSize {
        if(width<=0 || height<=0 || !density.isFinite() || density<=0f)return IntSize.Zero
        return IntSize((100f*density).toInt().coerceAtLeast(1),
            (100f*density*height/width).toInt().coerceAtLeast(1))
    }
}
