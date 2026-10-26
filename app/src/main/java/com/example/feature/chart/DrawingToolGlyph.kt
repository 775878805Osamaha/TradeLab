package com.example.feature.chart

import androidx.compose.foundation.Canvas
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.runtime.Composable
import com.example.feature.chart.model.DrawingTool
import com.example.feature.chart.model.isTextTool

/** Native vector glyphs share the anchors and proportions of their drawing tools. */
@Composable
internal fun DrawingToolGlyph(tool: DrawingTool, color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val u = size.width / 40f
        val w = 1.8f * u
        fun p(x: Float, y: Float) = Offset(x * u, y * u)
        fun line(x: Float, y: Float, a: Float, b: Float) = drawLine(color, p(x,y), p(a,b), w)
        fun dot(x: Float, y: Float) { drawCircle(Color(0xFFF2F2F2), 2.7f*u, p(x,y)); drawCircle(color, 2.7f*u, p(x,y), style = Stroke(w)) }
        fun path(vararg points: Pair<Float,Float>) { val path = Path(); points.forEachIndexed { i, v -> if(i==0) path.moveTo(v.first*u,v.second*u) else path.lineTo(v.first*u,v.second*u) }; drawPath(path,color,style=Stroke(w)) }
        when {
            tool == DrawingTool.ANCHORED_TEXT -> {
                line(8f,7f,28f,7f);line(18f,7f,18f,31f)
                line(30f,21f,30f,36f);line(25f,25f,35f,25f);path(23f to 31f,26f to 35f,30f to 37f,34f to 35f,37f to 31f);dot(30f,20f)
            }
            tool == DrawingTool.NOTE -> {drawRect(color,p(7f,5f),Size(27*u,22*u),style=Stroke(w));line(12f,10f,28f,10f);line(20f,10f,20f,22f);line(20f,27f,20f,35f);dot(20f,35f)}
            tool == DrawingTool.PRICE_NOTE -> {drawRect(color,p(9f,6f),Size(27*u,23*u),style=Stroke(w));line(9f,29f,5f,35f);dot(5f,35f)}
            tool == DrawingTool.CALLOUT -> {path(7f to 6f,34f to 6f,34f to 26f,18f to 26f,7f to 35f,7f to 6f)}
            tool == DrawingTool.ANNOTATION -> {drawRoundRect(color,p(7f,10f),Size(28*u,19*u),androidx.compose.ui.geometry.CornerRadius(7*u),style=Stroke(w))}
            tool == DrawingTool.SIGNPOST -> {drawCircle(color,11*u,p(20f,15f),style=Stroke(w));line(20f,26f,20f,36f);path(20f to 8f,22f to 12f,27f to 13f,23f to 17f,24f to 22f,20f to 19f,16f to 22f,17f to 17f,13f to 13f,18f to 12f,20f to 8f)}
            tool == DrawingTool.FLAG -> {path(7f to 36f,7f to 5f,34f to 5f,26f to 15f,34f to 25f,7f to 25f)}
            tool == DrawingTool.PRICE_LABEL -> {drawRect(color,p(7f,5f),Size(27*u,22*u),style=Stroke(w));line(20f,27f,20f,35f);dot(20f,35f);drawContext.canvas.nativeCanvas.drawText("\$",16*u,22*u,android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply{this.color=color.toArgb();textSize=19*u})}
            tool == DrawingTool.PIN -> {val a=Path().apply{moveTo(20*u,36*u);cubicTo(5*u,20*u,4*u,5*u,20*u,5*u);cubicTo(36*u,5*u,35*u,20*u,20*u,36*u);close()};drawPath(a,color,style=Stroke(w));drawCircle(color,4*u,p(20f,15f),style=Stroke(w))}
            tool == DrawingTool.PATH -> {path(4f to 29f,14f to 18f,25f to 26f,36f to 10f);for(v in listOf(4f to 29f,14f to 18f,25f to 26f))dot(v.first,v.second);line(27f,10f,36f,10f);line(36f,10f,36f,19f)}
            tool == DrawingTool.POLYLINE -> {val pts=listOf(6f to 33f,6f to 18f,18f to 6f,32f to 6f,32f to 20f,19f to 20f,19f to 33f,6f to 33f);path(*pts.toTypedArray());pts.dropLast(1).forEach{dot(it.first,it.second)}}
            tool == DrawingTool.CIRCLE -> {drawCircle(color,12*u,p(20f,20f),style=Stroke(w));dot(20f,20f);dot(32f,20f)}
            tool == DrawingTool.ARC || tool == DrawingTool.PROJECTION -> {val a=Path().apply{moveTo(8*u,8*u);quadraticBezierTo(32*u,8*u,32*u,32*u);lineTo(8*u,32*u);close()};drawPath(a,color,style=Stroke(w));dot(8f,8f);dot(32f,32f);dot(8f,32f)}
            tool == DrawingTool.HIGHLIGHTER -> {path(8f to 27f,15f to 16f,28f to 29f,20f to 36f,8f to 27f);path(15f to 16f,19f to 7f,28f to 1f);path(28f to 29f,36f to 21f)}
            tool == DrawingTool.TABLE -> {drawRect(color,p(5f,6f),Size(30*u,28*u),style=Stroke(w));for(v in listOf(15f,25f))line(v,6f,v,34f);for(v in listOf(15f,24f))line(5f,v,35f,v)}
            tool == DrawingTool.IMAGE -> {drawRect(color,p(5f,5f),Size(30*u,30*u),style=Stroke(w));path(7f to 30f,16f to 20f,22f to 26f,28f to 17f,34f to 28f);dot(14f,13f)}
            tool == DrawingTool.VOLUME_PROFILE_FIXED || tool == DrawingTool.VOLUME_PROFILE_SESSION -> {
                line(9f,4f,9f,36f);line(34f,6f,34f,36f);dot(9f,36f);dot(34f,6f)
                for((y,x) in listOf(11f to 19f,18f to 27f,25f to 22f)) {line(9f,y,x,y);line(x,y,x,y+4f);line(x,y+4f,9f,y+4f)}
            }
            tool == DrawingTool.CYCLES -> {for(x in listOf(5f,12.5f,20f,27.5f,35f)){line(x,4f,x,36f);if(x<=20f)dot(x,21f)}}
            tool == DrawingTool.BARS_PATTERN || tool == DrawingTool.GHOST_FEED || tool == DrawingTool.FORECAST -> {
                for((x,y) in listOf(9f to 18f,20f to 10f,31f to 15f)){line(x,y-5f,x,y+18f);drawRect(color,p(x-3,y),Size(6*u,11*u),style=Stroke(w))}
                if(tool==DrawingTool.FORECAST){line(35f,2f,35f,10f);line(32f,7f,35f,10f);line(35f,10f,38f,7f)}
            }
            tool.isTextTool -> { line(9f,8f,31f,8f); line(20f,8f,20f,32f); line(14f,32f,26f,32f)
                if (tool != DrawingTool.TEXT) drawRect(color,p(5f,3f),Size(30*u,34*u),style=Stroke(w)) }
            tool in setOf(DrawingTool.HORIZONTAL_LINE, DrawingTool.HORIZONTAL_RAY) -> { line(4f,20f,36f,20f); dot(if(tool==DrawingTool.HORIZONTAL_RAY) 7f else 20f,20f) }
            tool == DrawingTool.VERTICAL_LINE -> { line(20f,4f,20f,36f); dot(20f,20f) }
            tool == DrawingTool.FIBONACCI -> {
                for(y in listOf(8f,17f,26f,35f)) line(6f,y,34f,y)
                dot(6f,8f);dot(34f,26f)
            }
            tool == DrawingTool.PRICE_RANGE -> {line(8f,6f,33f,6f);line(8f,34f,33f,34f);line(20f,6f,20f,34f);path(15f to 12f,20f to 6f,25f to 12f);path(15f to 28f,20f to 34f,25f to 28f);dot(8f,34f);dot(33f,6f)}
            tool == DrawingTool.DATE_RANGE -> {line(6f,7f,6f,33f);line(34f,7f,34f,33f);line(6f,20f,34f,20f);path(28f to 15f,34f to 20f,28f to 25f);dot(6f,33f);dot(34f,7f)}
            tool == DrawingTool.DATE_PRICE_RANGE -> {drawRect(color,p(6f,6f),Size(28*u,28*u),style=Stroke(w));line(20f,7f,20f,33f);line(7f,20f,33f,20f);path(15f to 12f,20f to 7f,25f to 12f);path(28f to 15f,33f to 20f,28f to 25f);dot(6f,34f);dot(34f,6f)}
            tool == DrawingTool.FIB_FAN -> { for(y in listOf(5f,18f,35f)) line(5f,35f,35f,y); dot(5f,35f) }
            tool == DrawingTool.LONG_POSITION || tool == DrawingTool.SHORT_POSITION -> {
                for(y in listOf(8f,20f,32f)) line(6f,y,34f,y);dot(6f,8f);dot(6f,32f)
                if(tool==DrawingTool.LONG_POSITION) {line(19f,14f,19f,26f);line(19f,26f,26f,26f)} else path(26f to 14f,17f to 14f,17f to 20f,26f to 20f,26f to 26f,17f to 26f)
            }
            tool == DrawingTool.RECTANGLE || tool == DrawingTool.ROTATED_RECTANGLE -> {
                if(tool==DrawingTool.RECTANGLE) {drawRect(color,p(7f,7f),Size(26*u,26*u),style=Stroke(w)); for(v in listOf(7f to 7f,33f to 7f,33f to 33f,7f to 33f))dot(v.first,v.second)}
                else {path(8f to 23f,25f to 5f,35f to 17f,18f to 35f,8f to 23f);dot(8f,23f);dot(25f,5f);dot(35f,17f);dot(18f,35f)}
            }
            tool == DrawingTool.ELLIPSE -> {drawOval(color,p(5f,10f),Size(30*u,20*u),style=Stroke(w));dot(5f,20f);dot(35f,20f);dot(20f,10f);dot(20f,30f)}
            tool == DrawingTool.TRIANGLE -> {path(7f to 5f,7f to 34f,34f to 34f,7f to 5f);dot(7f,5f);dot(7f,34f);dot(34f,34f)}
            tool == DrawingTool.BRUSH || tool == DrawingTool.HIGHLIGHTER -> {path(8f to 29f,11f to 20f,29f to 3f,36f to 10f,18f to 28f,8f to 29f); path(5f to 33f,13f to 36f,23f to 32f,30f to 35f,37f to 29f)}
            tool == DrawingTool.DOUBLE_CURVE -> {val a=Path().apply{moveTo(8*u,35*u);quadraticBezierTo(35*u,35*u,20*u,20*u);quadraticBezierTo(3*u,5*u,32*u,5*u)};drawPath(a,color,style=Stroke(w));dot(8f,35f);dot(32f,5f)}
            tool == DrawingTool.CURVE || tool == DrawingTool.ARC -> {val a=Path().apply{moveTo(6*u,33*u);cubicTo(7*u,7*u,29*u,7*u,34*u,7*u)};drawPath(a,color,style=Stroke(w));dot(6f,33f);dot(34f,7f)}
            tool == DrawingTool.ARROW_MARKER -> {path(5f to 35f,16f to 14f,25f to 9f,24f to 5f,35f to 5f,32f to 17f,29f to 13f,21f to 23f,5f to 35f)}
            tool == DrawingTool.ARROW_UP || tool == DrawingTool.ARROW_DOWN -> {
                val a=if(tool==DrawingTool.ARROW_UP) 1f else -1f
                fun yy(y:Float)=20f+(y-20f)*a
                path(20f to yy(4f),7f to yy(19f),15f to yy(19f),15f to yy(35f),25f to yy(35f),25f to yy(19f),33f to yy(19f),20f to yy(4f))
            }
            tool == DrawingTool.PRICE_LABEL || tool == DrawingTool.PIN || tool == DrawingTool.FLAG -> {drawRect(color,p(8f,5f),Size(25*u,19*u),style=Stroke(w));line(8f,24f,8f,35f);dot(8f,35f);line(15f,11f,26f,11f);line(15f,17f,26f,17f)}
            tool in setOf(DrawingTool.CYPHER,DrawingTool.TRIANGLE_PATTERN,DrawingTool.THREE_DRIVES,DrawingTool.ELLIOTT_TRIANGLE,DrawingTool.ELLIOTT_DOUBLE,DrawingTool.ELLIOTT_TRIPLE,DrawingTool.ABCD,DrawingTool.XABCD,DrawingTool.HEAD_SHOULDERS,DrawingTool.ELLIOTT_IMPULSE,DrawingTool.ELLIOTT_CORRECTION,DrawingTool.ANCHORED_VWAP) -> {
                val pts=when(tool) {
                    DrawingTool.XABCD,DrawingTool.CYPHER -> listOf(6f to 33f,12f to 7f,32f to 27f,28f to 9f,10f to 27f)
                    DrawingTool.ABCD -> listOf(7f to 9f,33f to 5f,28f to 32f,4f to 28f,7f to 9f)
                    DrawingTool.TRIANGLE_PATTERN,DrawingTool.ELLIOTT_TRIANGLE -> listOf(6f to 6f,6f to 34f,16f to 11f,16f to 29f,33f to 20f,6f to 6f)
                    DrawingTool.HEAD_SHOULDERS -> listOf(4f to 33f,10f to 16f,15f to 28f,21f to 5f,27f to 28f,32f to 16f,37f to 33f)
                    DrawingTool.THREE_DRIVES -> listOf(4f to 8f,10f to 29f,16f to 11f,22f to 32f,29f to 14f,36f to 35f)
                    DrawingTool.ANCHORED_VWAP -> listOf(4f to 32f,12f to 26f,20f to 21f,28f to 17f,36f to 11f)
                    else -> listOf(5f to 31f,14f to 21f,24f to 29f,35f to 19f)
                }
                path(*pts.toTypedArray());pts.forEach{dot(it.first,it.second)}
                if(tool==DrawingTool.CYPHER) drawContext.canvas.nativeCanvas.drawText("C",17*u,34*u,android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply{this.color=color.toArgb();textSize=10*u})
                val labels=when(tool){DrawingTool.ELLIOTT_IMPULSE->listOf("1","5");DrawingTool.ELLIOTT_CORRECTION->listOf("A","C");DrawingTool.ELLIOTT_DOUBLE->listOf("W","Y");DrawingTool.ELLIOTT_TRIPLE->listOf("W","Z");else->emptyList()}
                labels.forEachIndexed{i,label->drawContext.canvas.nativeCanvas.drawText(label,(9+19*i)*u,12*u,android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply{this.color=color.toArgb();textSize=10*u})}
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
