package com.example.feature.chart

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.example.feature.chart.model.*

@Composable
internal fun DrawingPropertiesDialog(drawing: ChartDrawing, onDismiss: () -> Unit, onDelete: () -> Unit, onSave: (ChartDrawing) -> Unit, onCopy: ((ChartDrawing) -> Unit)? = null) {
    var color by remember(drawing.id) { mutableStateOf(drawing.color) }
    var width by remember(drawing.id) { mutableFloatStateOf(drawing.strokeWidth) }
    var text by remember(drawing.id) { mutableStateOf(drawing.text) }
    val original = remember(drawing) { drawing.anchors.ifEmpty { listOfNotNull(DrawingAnchor(drawing.startTime,drawing.startPrice), drawing.endTime?.let { t -> drawing.endPrice?.let { DrawingAnchor(t,it) } }) } }
    var prices by remember(drawing.id) { mutableStateOf(original.map { it.price.toString() }) }
    val valid = prices.all { it.toDoubleOrNull()?.let { p -> p.isFinite() && p > 0 } == true }
    AlertDialog(onDismissRequest = onDismiss, modifier = Modifier.testTag("drawing_properties"), title = { Text(drawing.tool.catalogLabel()) },
        text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            ChartColorChoices(androidx.compose.ui.res.stringResource(com.example.R.string.drawing_color), color.toArgb()) { color = Color(it) }
            Text("سُمك الخط: ${width.toInt()}"); Slider(width,{width=it},valueRange=1f..6f,steps=4)
            if(drawing.tool.isTextTool) OutlinedTextField(text,{text=it},label={Text("النص")})
            prices.forEachIndexed { i,value -> OutlinedTextField(value,{next -> prices=prices.toMutableList().also { it[i]=next }},label={Text("سعر النقطة ${i+1}")},singleLine=true,keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Decimal)) }
            if(onCopy != null) TextButton(onClick={onCopy(drawing)}) { Text("نسخ الرسم") }
            TextButton(onClick = onDelete) { Text("حذف الرسم", color = Color(0xFFFF3D48)) }
        } },
        confirmButton = { TextButton(enabled=valid,onClick={
            val anchors=original.mapIndexed { i,a -> a.copy(price=prices[i].toDouble()) }
            onSave(drawing.copy(color=color,strokeWidth=width,text=text,startPrice=anchors.first().price,
                endPrice=if(drawing.endPrice!=null) anchors.last().price else null,
                anchors=if(drawing.anchors.isNotEmpty())anchors else emptyList()))
        }) { Text("حفظ") } }, dismissButton={TextButton(onClick=onDismiss){Text("إلغاء")}})
}
