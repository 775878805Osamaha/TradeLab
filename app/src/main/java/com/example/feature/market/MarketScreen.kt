package com.example.feature.market

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.util.Locale

private val Navy=Color(0xFF03131D)
private val CardNavy=Color(0xFF0B1B27)
private val Edge=Color(0xFF213545)
private val Muted=Color(0xFF8B9BAE)
private val Teal=Color(0xFF00C7AD)
private val Red=Color(0xFFFF3558)
private val Blue=Color(0xFF126BFF)

@Composable
fun MarketScreen(viewModel:MarketViewModel,onSelectSymbol:(String)->Unit,modifier:Modifier=Modifier) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    var sortOpen by remember{mutableStateOf(false)}
    var details by remember{mutableStateOf<MarketQuoteSnapshot?>(null)}
    Column(modifier.fillMaxSize().background(Navy).padding(horizontal=8.dp).testTag("market_screen")) {
        Row(Modifier.fillMaxWidth().height(55.dp).padding(horizontal=5.dp),verticalAlignment=Alignment.CenterVertically) {
            Text("السوق",color=Color.White,fontSize=22.sp,fontWeight=FontWeight.Bold)
            Spacer(Modifier.width(12.dp))
            val live=state.rows.isNotEmpty() && state.rows.all{it.freshness==MarketQuoteSnapshot.Freshness.LIVE}
            Text(if(live)"LIVE DATA ●" else if(state.loading)"جارٍ الاتصال" else "بيانات جزئية / متأخرة",color=if(live)Teal else Muted,fontSize=10.sp,
                modifier=Modifier.border(1.dp,if(live)Teal else Edge,RoundedCornerShape(5.dp)).padding(8.dp).testTag("market_feed_status"))
            Spacer(Modifier.weight(1f));Icon(Icons.Default.StarBorder,null,tint=Muted,modifier=Modifier.size(28.dp))
        }
        OutlinedTextField(state.searchQuery,viewModel::updateSearchQuery,modifier=Modifier.fillMaxWidth().height(49.dp).testTag("market_search_input"),
            placeholder={Text("ابحث عن رمز أو اسم الأصل...",fontSize=12.sp)},leadingIcon={Icon(Icons.Default.Search,null,tint=Muted)},singleLine=true,
            shape=RoundedCornerShape(9.dp),textStyle=TextStyle(fontSize=13.sp,color=Color.White),
            colors=OutlinedTextFieldDefaults.colors(unfocusedContainerColor=CardNavy,focusedContainerColor=CardNavy,unfocusedBorderColor=Edge,focusedBorderColor=Blue))
        Row(Modifier.padding(vertical=9.dp).horizontalScroll(rememberScrollState()),horizontalArrangement=Arrangement.spacedBy(4.dp)) {
            MarketCategory.entries.forEach{c->Column(Modifier.border(1.dp,if(state.category==c)Blue else Edge,RoundedCornerShape(6.dp)).background(if(state.category==c)Blue.copy(alpha=.12f) else CardNavy).clickable{viewModel.selectCategory(c)}.padding(horizontal=10.dp,vertical=7.dp).testTag("market_category_${c.name}"),horizontalAlignment=Alignment.CenterHorizontally){
                Icon(when(c){MarketCategory.FAVORITES->Icons.Default.StarBorder;MarketCategory.CRYPTO->Icons.Default.CurrencyBitcoin;MarketCategory.FOREX->Icons.Default.CurrencyExchange;MarketCategory.STOCKS->Icons.Default.Business;MarketCategory.INDICES->Icons.Default.BarChart;MarketCategory.METALS->Icons.Default.Diamond;else->Icons.Default.Dashboard},null,tint=if(state.category==c)Blue else Muted,modifier=Modifier.size(19.dp))
                Text(c.label,color=Color.White,fontSize=9.sp)
            }}
        }
        Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){
            IconButton(onClick={viewModel.setCompact(true)},modifier=Modifier.size(32.dp)){Icon(Icons.Default.ViewList,"عرض بالقائمة",tint=if(state.compact)Blue else Muted)}
            IconButton(onClick={viewModel.setCompact(false)},modifier=Modifier.size(32.dp)){Icon(Icons.Default.ViewAgenda,"عرض موسع",tint=if(!state.compact)Blue else Muted)}
            Spacer(Modifier.weight(1f))
            Box { TextButton(onClick={sortOpen=true}){Text("الترتيب: ${state.sortOption.label} ▾",color=Muted,fontSize=11.sp)}
                DropdownMenu(sortOpen,{sortOpen=false}){MarketSort.entries.forEach{s->DropdownMenuItem(text={Text(s.label)},onClick={viewModel.setSortOption(s);sortOpen=false})}}
            }
        }
        Row(Modifier.fillMaxWidth().padding(vertical=5.dp),horizontalArrangement=Arrangement.SpaceAround){listOf("الرمز / المصدر","السعر","التغير","مخطط 24س").forEach{Text(it,color=Muted,fontSize=10.sp)}}
        if(state.rows.isEmpty()) Box(Modifier.fillMaxSize(),contentAlignment=Alignment.Center){Text(if(state.loading)"جارٍ تحميل السوق…" else "لا توجد أصول مدعومة مطابقة",color=Muted)}
        LazyColumn(Modifier.fillMaxSize().testTag("market_list"),verticalArrangement=Arrangement.spacedBy(4.dp),contentPadding=PaddingValues(bottom=8.dp)){
            items(state.rows,key={it.symbol.symbol}) { row->
                MarketAssetRow(row,state.compact,{onSelectSymbol(row.symbol.symbol)},{viewModel.toggleSymbolFavorite(row.symbol.symbol,row.symbol.isFavorite)},{details=row})
            }
        }
    }
    details?.let{row->AlertDialog(onDismissRequest={details=null},title={Text(row.symbol.name)},text={Text("${row.symbol.symbol}\n${row.provider}\n${row.freshness}\nوقت المصدر: ${row.providerTimestamp?.let{java.time.Instant.ofEpochMilli(it).toString()} ?: "غير متاح"}\nالسبريد: ${row.spread ?: "غير متاح"}\nالتغير: نافذة 24 ساعة؛ لا يُحسب عند نقص التاريخ.\nالسعر المعروض: منتصف Bid / Ask")},confirmButton={TextButton(onClick={details=null;onSelectSymbol(row.symbol.symbol)}){Text("فتح الشارت")}},dismissButton={TextButton(onClick={details=null}){Text("إغلاق")}})}
}

@Composable
private fun MarketAssetRow(row:MarketQuoteSnapshot,compact:Boolean,open:()->Unit,favorite:()->Unit,details:()->Unit){
    val up=(row.change ?: 0.0)>=0;val color=if(up)Teal else Red
    fun price(v:Double?)=v?.let{String.format(Locale.US,"%,.${row.symbol.digits}f",it)} ?: "—"
    Row(Modifier.fillMaxWidth().heightIn(min=if(compact)54.dp else 82.dp).border(1.dp,Edge,RoundedCornerShape(8.dp)).background(CardNavy,RoundedCornerShape(8.dp)).clickable(onClick=open).padding(horizontal=4.dp,vertical=6.dp).testTag("symbol_card_${row.symbol.symbol}"),verticalAlignment=Alignment.CenterVertically){
        IconButton(onClick=details,modifier=Modifier.size(20.dp)){Icon(Icons.Default.MoreVert,"تفاصيل ${row.symbol.symbol}",tint=Muted,modifier=Modifier.size(16.dp))}
        Column(Modifier.weight(1.3f)){
            Text(row.symbol.symbol,color=Color.White,fontSize=11.sp,fontWeight=FontWeight.Bold,style=TextStyle(textDirection=TextDirection.Ltr),maxLines=1)
            Text(row.symbol.category,color=Muted,fontSize=9.sp)
            Text(row.provider,color=if(row.freshness==MarketQuoteSnapshot.Freshness.LIVE)Teal else Muted,fontSize=8.sp,maxLines=1)
            if(row.freshness!=MarketQuoteSnapshot.Freshness.LIVE)Text(if(row.freshness==MarketQuoteSnapshot.Freshness.STALE)"سعر متأخر" else "البيانات غير متاحة حاليًا",color=Muted,fontSize=8.sp)
        }
        Column(Modifier.weight(1.15f),horizontalAlignment=Alignment.CenterHorizontally){
            Text(price(row.last),color=Color.White,fontWeight=FontWeight.Bold,fontSize=12.sp,style=TextStyle(textDirection=TextDirection.Ltr),maxLines=1)
            Text("${price(row.bid)} / ${price(row.ask)}",color=Muted,fontSize=7.sp,style=TextStyle(textDirection=TextDirection.Ltr),maxLines=1)
        }
        Column(Modifier.weight(.75f),horizontalAlignment=Alignment.CenterHorizontally){
            Text(row.changePercent?.let{String.format(Locale.US,"%+.2f%%",it)} ?: "—",color=color,fontSize=11.sp,fontWeight=FontWeight.Bold,style=TextStyle(textDirection=TextDirection.Ltr))
            Text(row.change?.let{String.format(Locale.US,"%+.${row.symbol.digits}f",it)} ?: "—",color=color,fontSize=9.sp,style=TextStyle(textDirection=TextDirection.Ltr))
        }
        val bars=row.history
        Canvas(Modifier.weight(.9f).height(32.dp)){
            if(bars.size>1){val low=bars.minOf{it.close};val high=bars.maxOf{it.close};val span=(high-low).coerceAtLeast(.000000001)
                val path=Path();bars.forEachIndexed{i,b->val x=i.toFloat()/(bars.size-1)*size.width;val y=size.height-((b.close-low)/span*size.height).toFloat();if(i==0)path.moveTo(x,y) else path.lineTo(x,y)}
                drawPath(path,if(bars.last().close>=bars.first().close)Teal else Red,style=Stroke(1.2.dp.toPx()))
            }
        }
        IconButton(onClick=favorite,modifier=Modifier.size(28.dp).testTag("fav_btn_${row.symbol.symbol}")){Icon(if(row.symbol.isFavorite)Icons.Default.Star else Icons.Default.StarBorder,"المفضلة",tint=if(row.symbol.isFavorite)Color(0xFFFFB329) else Muted,modifier=Modifier.size(20.dp))}
    }
}
