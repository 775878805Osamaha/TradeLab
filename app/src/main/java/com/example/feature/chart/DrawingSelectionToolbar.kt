package com.example.feature.chart

import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import com.example.feature.chart.model.*

@Composable internal fun DrawingSelectionToolbar(drawing:ChartDrawing,onProperties:()->Unit,onUpdate:((ChartDrawing)->ChartDrawing)->Unit,onDelete:()->Unit,onDismiss:()->Unit,modifier:Modifier=Modifier) {
    Surface(modifier.testTag("drawing_selection_toolbar"),shape=RoundedCornerShape(8.dp),color=Color(0xFF17191E),shadowElevation=3.dp) {
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(2.dp)) {
            IconButton(onClick=onProperties,modifier=Modifier.size(38.dp).testTag("drawing_edit_properties")){Icon(Icons.Default.Tune,"خصائص الرسم",tint=Color.White)}
            IconButton(onClick={onUpdate { current->current.copy(strokeWidth=if(current.strokeWidth>=6f)1f else current.strokeWidth+1f) }},modifier=Modifier.size(38.dp).testTag("drawing_edit_width")){Text("${drawing.strokeWidth.toInt()}px",color=Color.White)}
            IconButton(onClick={val colors=listOf(Color(0xFF2962FF),Color(0xFF00B7AA),Color(0xFFFF3D48),Color.White);onUpdate { current->current.copy(color=colors[(colors.indexOf(current.color)+1).mod(colors.size)]) }},modifier=Modifier.size(38.dp).testTag("drawing_edit_color")){Icon(Icons.Default.Edit,"تغيير لون الرسم",tint=drawing.color)}
            IconButton(onClick={onUpdate { current->current.copy(lineStyle=DrawingLineStyle.values()[(current.lineStyle.ordinal+1)%DrawingLineStyle.values().size]) }},modifier=Modifier.size(38.dp).testTag("drawing_edit_style")){Icon(if(drawing.lineStyle==DrawingLineStyle.SOLID)Icons.Default.Remove else Icons.Default.MoreHoriz,"نمط الخط: ${drawing.lineStyle.titleAr}",tint=Color.White)}
            if(drawing.tool.supportsFill) IconButton(onClick={val levels=listOf(0f,.1f,.18f,.35f,.6f);onUpdate { current->current.copy(fillOpacity=levels.firstOrNull { it>current.fillOpacity+.001f }?:0f) }},modifier=Modifier.size(38.dp).testTag("drawing_edit_fill")){Icon(Icons.Default.FormatColorFill,"تعبئة الرسم: ${(drawing.fillOpacity*100).toInt()}%",tint=drawing.color)}
            IconButton(onClick={onUpdate { current->current.copy(isLocked=!current.isLocked) }},modifier=Modifier.size(38.dp).testTag("drawing_edit_lock")){Icon(if(drawing.isLocked)Icons.Default.Lock else Icons.Default.LockOpen,if(drawing.isLocked)"إلغاء قفل الرسم" else "قفل الرسم",tint=if(drawing.isLocked)Color(0xFF2962FF) else Color.White)}
            IconButton(onClick=onDelete,modifier=Modifier.size(38.dp).testTag("drawing_edit_delete")){Icon(Icons.Default.DeleteOutline,"حذف الرسم",tint=Color.White)}
            IconButton(onClick=onDismiss,modifier=Modifier.size(38.dp).testTag("drawing_edit_dismiss")){Icon(Icons.Default.Close,"إلغاء تحديد الرسم",tint=Color.White)}
        }
    }
}
