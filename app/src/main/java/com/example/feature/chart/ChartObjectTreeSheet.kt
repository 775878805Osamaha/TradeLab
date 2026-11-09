package com.example.feature.chart

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Layers
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.feature.chart.model.ChartDrawing
import java.util.Locale

/** Edits the same persisted drawings rendered on the current symbol/timeframe. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ChartObjectTreeSheet(
    symbol: String,
    drawings: List<ChartDrawing>,
    drawingsHidden: Boolean,
    onDismiss: () -> Unit,
    onEdit: (ChartDrawing) -> Unit,
    onDelete: (ChartDrawing) -> Unit,
    onShowDrawings: () -> Unit
) {
    var pendingDelete by remember { mutableStateOf<ChartDrawing?>(null) }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Color.White,
        contentColor = Color(0xFF171717),
        shape = RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp)
    ) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(0.74f).testTag("object_tree_sheet")) {
            Text(
                "شجرة الكائنات", fontSize = 25.sp, fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Right,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 22.dp, vertical = 10.dp)
                    .testTag("object_tree_title")
            )
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 22.dp, vertical = 3.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("${drawings.size} رسم", color = Color(0xFF777777), fontSize = 13.sp)
                Text(symbol, color = Color(0xFF777777), fontSize = 14.sp)
            }
            if (drawingsHidden) {
                TextButton(onClick = onShowDrawings, modifier = Modifier.fillMaxWidth().testTag("object_tree_show_drawings")) {
                    Text("الرسومات مخفية — اضغط لإظهارها على الشارت")
                }
            }
            HorizontalDivider(color = Color(0xFFEEEEEE))
            if (drawings.isEmpty()) {
                Column(
                    Modifier.fillMaxSize().padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Icon(Icons.Outlined.Layers, contentDescription = null,
                        tint = Color(0xFF8D8D8D), modifier = Modifier.size(44.dp))
                    Spacer(Modifier.height(14.dp))
                    Text("لا توجد رسومات على هذا الشارت", fontSize = 17.sp, fontWeight = FontWeight.Medium)
                    Text("أضف خطًا أو أداة رسم لتظهر هنا", fontSize = 14.sp, color = Color(0xFF777777))
                }
            } else {
                LazyColumn(
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 9.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    items(drawings.asReversed(), key = { it.id }) { drawing ->
                        Row(
                            Modifier.fillMaxWidth()
                                .background(Color(0xFFF4F4F4), RoundedCornerShape(14.dp))
                                .testTag("object_tree_row_${drawing.id}")
                                .clickable { onEdit(drawing) }
                                .padding(start = 8.dp, end = 16.dp, top = 10.dp, bottom = 10.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            IconButton(onClick = { pendingDelete = drawing },
                                modifier = Modifier.size(42.dp).testTag("object_tree_delete_${drawing.id}")) {
                                Icon(Icons.Outlined.DeleteOutline, contentDescription = "حذف الرسم", tint = Color(0xFFBE3942))
                            }
                            IconButton(onClick = { onEdit(drawing) },
                                modifier = Modifier.size(42.dp).testTag("object_tree_edit_${drawing.id}")) {
                                Icon(Icons.Outlined.Edit, contentDescription = "تعديل الرسم")
                            }
                            Column(Modifier.weight(1f), horizontalAlignment = Alignment.End) {
                                Text(drawing.tool.catalogLabel(), fontSize = 15.sp,
                                    fontWeight = FontWeight.Medium, textAlign = TextAlign.Right)
                                Text(String.format(Locale.US, "%.2f", drawing.startPrice),
                                    fontSize = 12.sp, color = Color(0xFF737373))
                            }
                        }
                    }
                }
            }
        }
    }
    pendingDelete?.let { drawing ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text("حذف الرسم؟") },
            text = { Text("سيُحذف ${drawing.tool.catalogLabel()} من الشارت الحالي.") },
            confirmButton = {
                TextButton(onClick = { onDelete(drawing); pendingDelete = null }) {
                    Text("حذف", color = Color(0xFFBE3942))
                }
            },
            dismissButton = { TextButton(onClick = { pendingDelete = null }) { Text("إلغاء") } }
        )
    }
}
