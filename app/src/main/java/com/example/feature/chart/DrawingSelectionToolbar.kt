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
import com.example.feature.chart.model.ChartDrawing

@Composable internal fun DrawingSelectionToolbar(drawing:ChartDrawing,onProperties:()->Unit,onUpdate:(ChartDrawing)->Unit,onDelete:()->Unit,onDismiss:()->Unit,modifier:Modifier=Modifier) {
    Surface(modifier.testTag("drawing_selection_toolbar"),shape=RoundedCornerShape(8.dp),color=Color(0xFF17191E),shadowElevation=3.dp) {
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(2.dp)) {
            IconButton(onClick=onProperties,modifier=Modifier.size(38.dp).testTag("drawing_edit_properties")){Icon(Icons.Default.Tune,"خصائص الرسم",tint=Color.White)}
            IconButton(onClick={onUpdate(drawing.copy(strokeWidth=if(drawing.strokeWidth>=6f)1f else drawing.strokeWidth+1f))},modifier=Modifier.size(38.dp).testTag("drawing_edit_width")){Text("${drawing.strokeWidth.toInt()}px",color=Color.White)}
            IconButton(onClick={val colors=listOf(Color(0xFF2962FF),Color(0xFF00B7AA),Color(0xFFFF3D48),Color.White);onUpdate(drawing.copy(color=colors[(colors.indexOf(drawing.color)+1).mod(colors.size)]))},modifier=Modifier.size(38.dp).testTag("drawing_edit_color")){Icon(Icons.Default.Edit,"تغيير لون الرسم",tint=drawing.color)}
            IconButton(onClick=onDelete,modifier=Modifier.size(38.dp).testTag("drawing_edit_delete")){Icon(Icons.Default.DeleteOutline,"حذف الرسم",tint=Color.White)}
            IconButton(onClick=onDismiss,modifier=Modifier.size(38.dp).testTag("drawing_edit_dismiss")){Icon(Icons.Default.Close,"إلغاء تحديد الرسم",tint=Color.White)}
        }
    }
}
