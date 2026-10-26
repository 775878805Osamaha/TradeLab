package com.example.feature.chart

import androidx.compose.foundation.Canvas
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.runtime.Composable
import com.example.feature.chart.model.DrawingTool
import com.example.feature.chart.model.isTextTool

/** Native vector glyphs share the anchors and proportions of their drawing tools. */
@Composable
internal fun DrawingToolGlyph(tool: DrawingTool, color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val u = size.width / 40f
        val w = 2.1f * u
        fun p(x: Float, y: Float) = Offset(x * u, y * u)
        fun line(x: Float, y: Float, a: Float, b: Float) = drawLine(color, p(x,y), p(a,b), w)
        fun dot(x: Float, y: Float) { drawCircle(Color(0xFFF2F2F2), 2.7f*u, p(x,y)); drawCircle(color, 2.7f*u, p(x,y), style = Stroke(w)) }
        fun path(vararg points: Pair<Float,Float>) { val path = Path(); points.forEachIndexed { i, v -> if(i==0) path.moveTo(v.first*u,v.second*u) else path.lineTo(v.first*u,v.second*u) }; drawPath(path,color,style=Stroke(w)) }
        when {
            tool.isTextTool -> { line(9f,8f,31f,8f); line(20f,8f,20f,32f); line(14f,32f,26f,32f)
                if (tool != DrawingTool.TEXT) drawRect(color,p(5f,3f),Size(30*u,34*u),style=Stroke(w)) }
            tool in setOf(DrawingTool.HORIZONTAL_LINE, DrawingTool.HORIZONTAL_RAY) -> { line(4f,20f,36f,20f); dot(if(tool==DrawingTool.HORIZONTAL_RAY) 7f else 20f,20f) }
            tool == DrawingTool.VERTICAL_LINE -> { line(20f,4f,20f,36f); dot(20f,20f) }
            tool == DrawingTool.FIBONACCI || tool == DrawingTool.PRICE_RANGE || tool == DrawingTool.DATE_RANGE || tool == DrawingTool.DATE_PRICE_RANGE -> {
                for(y in listOf(8f,17f,26f,35f)) line(6f,y,34f,y)
                dot(6f,8f);dot(34f,26f)
            }
            tool == DrawingTool.FIB_FAN -> { for(y in listOf(5f,18f,35f)) line(5f,35f,35f,y); dot(5f,35f) }
            tool == DrawingTool.LONG_POSITION || tool == DrawingTool.SHORT_POSITION -> {
                for(y in listOf(8f,20f,32f)) line(6f,y,34f,y);dot(6f,8f);dot(6f,32f)
                if(tool==DrawingTool.LONG_POSITION) {line(19f,14f,19f,26f);line(19f,26f,26f,26f)} else path(26f to 14f,17f to 14f,17f to 20f,26f to 20f,26f to 26f,17f to 26f)
            }
            tool == DrawingTool.RECTANGLE || tool == DrawingTool.ROTATED_RECTANGLE -> {
                if(tool==DrawingTool.RECTANGLE) {drawRect(color,p(7f,7f),Size(26*u,26*u),style=Stroke(w)); for(v in listOf(7f to 7f,33f to 7f,33f to 33f,7f to 33f))dot(v.first,v.second)}
                else {path(8f to 23f,25f to 5f,35f to 17f,18f to 35f,8f to 23f);dot(8f,23f);dot(25f,5f);dot(35f,17f);dot(18f,35f)}
            }
            tool == DrawingTool.ELLIPSE -> {drawOval(color,p(5f,7f),Size(30*u,27*u),style=Stroke(w));dot(35f,20f)}
            tool == DrawingTool.TRIANGLE -> {path(7f to 5f,7f to 34f,34f to 34f,7f to 5f);dot(7f,5f);dot(7f,34f);dot(34f,34f)}
            tool == DrawingTool.BRUSH || tool == DrawingTool.HIGHLIGHTER -> {path(8f to 29f,11f to 20f,29f to 3f,36f to 10f,18f to 28f,8f to 29f); path(5f to 33f,13f to 36f,23f to 32f,30f to 35f,37f to 29f)}
            tool == DrawingTool.CURVE || tool == DrawingTool.ARC -> {val a=Path().apply{moveTo(6*u,33*u);cubicTo(7*u,7*u,29*u,7*u,34*u,7*u)};drawPath(a,color,style=Stroke(w));dot(6f,33f);dot(34f,7f)}
            tool == DrawingTool.ARROW_UP || tool == DrawingTool.ARROW_DOWN -> {
                val a=if(tool==DrawingTool.ARROW_UP) 1f else -1f
                fun yy(y:Float)=20f+(y-20f)*a
                path(20f to yy(4f),7f to yy(19f),15f to yy(19f),15f to yy(35f),25f to yy(35f),25f to yy(19f),33f to yy(19f),20f to yy(4f))
            }
            tool == DrawingTool.PRICE_LABEL || tool == DrawingTool.PIN || tool == DrawingTool.FLAG -> {drawRect(color,p(8f,5f),Size(25*u,19*u),style=Stroke(w));line(8f,24f,8f,35f);dot(8f,35f);line(15f,11f,26f,11f);line(15f,17f,26f,17f)}
            tool in setOf(DrawingTool.ABCD,DrawingTool.XABCD,DrawingTool.HEAD_SHOULDERS,DrawingTool.ELLIOTT_IMPULSE,DrawingTool.ELLIOTT_CORRECTION,DrawingTool.POLYLINE,DrawingTool.PATH,DrawingTool.ANCHORED_VWAP) -> {
                val pts=listOf(5f to 32f,12f to 9f,21f to 25f,28f to 7f,36f to 18f);path(*pts.toTypedArray());pts.forEach{dot(it.first,it.second)}
            }
            tool == DrawingTool.PARALLEL_CHANNEL -> {line(4f,29f,29f,4f);line(11f,36f,36f,11f);dot(4f,29f);dot(29f,4f);dot(36f,11f)}
            else -> {
                line(7f,33f,33f,7f);dot(7f,33f)
                if(tool==DrawingTool.ARROW) {line(23f,7f,33f,7f);line(33f,7f,33f,17f)} else dot(33f,7f)
                if(tool==DrawingTool.EXTENDED_LINE) {line(2f,38f,38f,2f);dot(15f,25f);dot(25f,15f)}
                if(tool==DrawingTool.INFO_LINE) drawRect(color,p(24f,26f),Size(12*u,9*u),style=Stroke(w))
            }
        }
    }
}
