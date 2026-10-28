package com.example.feature.chart

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.horizontalScroll
import androidx.compose.ui.Alignment
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.example.feature.chart.model.*

@Composable
internal fun DrawingPropertiesDialog(drawing: ChartDrawing, onDismiss: () -> Unit, onDelete: () -> Unit, onSave: (ChartDrawing) -> Unit) {
    var color by remember(drawing.id) { mutableStateOf(drawing.color) }
    var width by remember(drawing.id) { mutableFloatStateOf(drawing.strokeWidth) }
    var lineStyle by remember(drawing.id) { mutableStateOf(drawing.lineStyle) }
    var fillOpacity by remember(drawing.id) { mutableFloatStateOf(drawing.fillOpacity) }
    var locked by remember(drawing.id) { mutableStateOf(drawing.isLocked) }
    var text by remember(drawing.id) { mutableStateOf(drawing.text) }
    val original = remember(drawing) { drawing.anchors.ifEmpty { listOfNotNull(DrawingAnchor(drawing.startTime,drawing.startPrice), drawing.endTime?.let { t -> drawing.endPrice?.let { DrawingAnchor(t,it) } }) } }
    val pricePrecision=remember(drawing.symbol) { com.example.core.market.DefaultSymbols.getSymbol(drawing.symbol).digits }
    var editedPrices by remember(drawing.id) { mutableStateOf(emptySet<Int>()) }
    var prices by remember(drawing.id) { mutableStateOf(original.map { anchor ->
        val formatted=String.format(java.util.Locale.US,"%.${pricePrecision}f",anchor.price)
        if((formatted.toDoubleOrNull()?:0.0)>0.0)formatted else anchor.price.toString()
    }) }
    val valid = prices.all { it.toDoubleOrNull()?.let { p -> p.isFinite() && p > 0 } == true }
    AlertDialog(onDismissRequest = onDismiss, modifier = Modifier.testTag("drawing_properties"), title = { Text(drawing.tool.catalogLabel()) },
        text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if(drawing.tool.supportsColor) {
            Text("لون الرسم")
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) { listOf(Color(0xFF2962FF),Color(0xFF00B7AA),Color(0xFFFF3D48),Color(0xFFF5A623),Color.White).forEach { c ->
                Box(Modifier.size(30.dp).background(c).clickable { color = c })
            } }
            }
            if(drawing.tool.supportsStrokeWidth) { Text("سُمك الخط: ${width.toInt()}"); Slider(width,{width=it},valueRange=1f..6f,steps=4) }
            if(drawing.tool.isTextTool) OutlinedTextField(text,{text=it},label={Text("النص")})
            prices.forEachIndexed { i,value -> OutlinedTextField(value,{next -> prices=prices.toMutableList().also { it[i]=next };editedPrices=editedPrices+i},modifier=Modifier.testTag("drawing_price_$i"),label={Text("سعر النقطة ${i+1}")},singleLine=true,keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Decimal)) }
            if(drawing.tool.supportsLineStyle) {
            Text("نمط الخط")
            Row(Modifier.horizontalScroll(rememberScrollState()).testTag("drawing_style_controls"),horizontalArrangement=Arrangement.spacedBy(4.dp)) { DrawingLineStyle.values().forEach { style ->
                FilterChip(selected=lineStyle==style,onClick={lineStyle=style},label={Text(style.titleAr)},modifier=Modifier.testTag("drawing_style_${style.name}"))
            } }
            }
            if(drawing.tool.supportsFill) {
                Text("كثافة التعبئة: ${(fillOpacity*100).toInt()}%")
                Slider(fillOpacity,{fillOpacity=it},valueRange=0f..1f,modifier=Modifier.testTag("drawing_fill_opacity"))
            }
            Row(verticalAlignment=Alignment.CenterVertically) { Checkbox(locked,{locked=it},modifier=Modifier.testTag("drawing_lock"));Text("قفل الرسم على الشارت") }
            TextButton(onClick = onDelete) { Text("حذف الرسم", color = Color(0xFFFF3D48)) }
        } },
        confirmButton = { TextButton(modifier=Modifier.testTag("drawing_save"),enabled=valid,onClick={
            val anchors=original.mapIndexed { i,a -> if(i in editedPrices)a.copy(price=prices[i].toDouble()) else a }
            onSave(drawing.copy(color=color,strokeWidth=width,text=text,lineStyle=lineStyle,fillOpacity=fillOpacity,isLocked=locked,startPrice=anchors.first().price,
                endPrice=if(drawing.endPrice!=null) anchors.last().price else null,
                anchors=if(drawing.anchors.isNotEmpty())anchors else emptyList()))
        }) { Text("حفظ") } }, dismissButton={TextButton(onClick=onDismiss){Text("إلغاء")}})
}
