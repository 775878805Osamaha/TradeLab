package com.example.feature.results

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.*
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.*
import androidx.compose.ui.unit.*
import androidx.compose.ui.window.Dialog
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.example.R
import com.example.core.model.*
import java.text.SimpleDateFormat
import java.util.*
import kotlin.math.abs

internal val V3Bg=Color(0xFF020D18)
internal val V3Card=Color(0xFF061725)
internal val V3Border=Color(0xFF193447)
internal val V3Blue=Color(0xFF2962FF)
internal val V3Profit=Color(0xFF00D5B0)
internal val V3Loss=Color(0xFFFF4D60)
internal val V3Text=Color(0xFFF1F5FA)
internal val V3Muted=Color(0xFF8E9DB1)
internal fun v3Money(v:Double,signed:Boolean=false)=if(!v.isFinite())"—" else (if(v<0)"−" else if(signed&&v>0)"+" else "")+String.format(Locale.US,"$%,.2f",abs(v))
private fun pct(v:Double)=if(v.isFinite())String.format(Locale.US,"%.2f%%",v) else "—"
private fun number(v:Double?)=v?.takeIf{it.isFinite()}?.let{String.format(Locale.US,"%.2f",it)}?:"—"
@Composable private fun Num(text:String,size:Int=16,color:Color=V3Text,modifier:Modifier=Modifier) { Text(text,color=color,fontSize=size.sp,fontWeight=FontWeight.Bold,style=TextStyle(textDirection=TextDirection.Ltr),modifier=modifier,maxLines=1) }
@Composable private fun Frame(modifier:Modifier=Modifier,content:@Composable ColumnScope.()->Unit) { Surface(modifier,shape=RoundedCornerShape(7.dp),color=V3Card,border=BorderStroke(.7.dp,V3Border)){Column(content=content)} }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ResultsScreen(viewModel:ResultsViewModel,onNavigateToHistory:()->Unit,onNavigateToBacktest:()->Unit={},modifier:Modifier=Modifier) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val a=state.analytics
    var custom by remember{mutableStateOf(false)}
    var expanded by remember{mutableStateOf(false)}
    var mode by remember{mutableStateOf("Equity")}
    val tabs=ResultsTab.values().filter{it!=ResultsTab.COMPARISON}
    state.selectedTradeForDetail?.let{TradeDetailDialog(it,{viewModel.selectTradeForDetail(null)})}
    if(state.isExportDialogOpen && a!=null) ExportDialog(a.metrics,a.trades,
        state.dailySummaries,a.curve,{viewModel.setExportDialogOpen(false)})
    if(custom) CustomDates(state.customStart,state.customEnd,{start,end->viewModel.setCustomRange(start,end);custom=false},{custom=false})
    if(expanded && a!=null) Dialog(onDismissRequest={expanded=false}) { Frame(Modifier.fillMaxWidth()){TextButton(onClick={expanded=false}){Text("إغلاق")};ResultsV3Chart(a.curve,a.days,mode,true)} }
    CompositionLocalProvider(LocalTextStyle provides LocalTextStyle.current.copy(lineHeight=TextUnit.Unspecified,letterSpacing=0.sp)) {
    Column(modifier.fillMaxSize().background(V3Bg).testTag("results_screen")) {
        Row(Modifier.fillMaxWidth().heightIn(min=51.dp).padding(horizontal=12.dp).testTag("results_header"),verticalAlignment=Alignment.CenterVertically) {
            Text("النتائج",color=V3Text,fontSize=18.sp,fontWeight=FontWeight.Bold,modifier=Modifier.weight(1f))
            Text("حساب التدريب",color=V3Blue,fontSize=13.sp,modifier=Modifier.semantics { contentDescription="حساب التدريب · ${state.openPositionsCount} مفتوحة · ${state.trades.size} مغلقة" }.testTag("results_positions_summary"))
            IconButton(onClick={viewModel.setExportDialogOpen(true)},enabled=a!=null,modifier=Modifier.size(32.dp).testTag("export_results_btn")){Icon(Icons.Default.FileDownload,"تصدير النتائج",tint=V3Blue,modifier=Modifier.size(20.dp))}
            Box(Modifier.size(48.dp),contentAlignment=Alignment.Center){Image(painterResource(R.drawable.tradelab_reference_mark),"هوية التطبيق",Modifier.size(42.dp));Box(Modifier.align(Alignment.BottomStart).size(7.dp).clip(RoundedCornerShape(50)).background(if(a!=null)V3Profit else V3Muted))}
        }
        Row(Modifier.fillMaxWidth().padding(horizontal=8.dp).border(.7.dp,V3Border,RoundedCornerShape(5.dp)).testTag("results_tabs").horizontalScroll(rememberScrollState())) {
            tabs.forEach { tab->val active=state.selectedTab==tab
                Column(Modifier.width(if(tab==ResultsTab.STATISTICS)80.dp else 75.dp).border(if(active).7.dp else 0.dp,if(active)V3Blue else Color.Transparent,RoundedCornerShape(4.dp)).background(if(active)V3Blue.copy(alpha=.16f) else Color.Transparent).clickable{viewModel.setSelectedTab(tab)}.testTag("results_tab_${tab.name}")) {
                    Text(tab.displayNameAr,color=if(active)V3Blue else V3Muted,fontSize=9.sp,lineHeight=14.sp,maxLines=1,textAlign=TextAlign.Center,modifier=Modifier.fillMaxWidth().padding(horizontal=4.dp,vertical=9.dp))
                    Box(Modifier.fillMaxWidth().height(1.dp).background(if(active)V3Blue else Color.Transparent))
                }
            }
        }
        Row(Modifier.fillMaxWidth().heightIn(min=40.dp).padding(horizontal=10.dp,vertical=11.dp).testTag("results_filters"),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)) {
            LazyRow(Modifier.weight(1f).testTag("results_periods"),horizontalArrangement=Arrangement.spacedBy(4.dp)) {items(ResultsPeriod.values().toList()){period->
                val active=state.selectedPeriod==period
                Box(Modifier.clip(RoundedCornerShape(4.dp)).background(if(active)V3Blue else V3Card).border(.7.dp,if(active)V3Blue else V3Border,RoundedCornerShape(4.dp)).clickable{if(period==ResultsPeriod.CUSTOM)custom=true else viewModel.setSelectedPeriod(period)}.padding(horizontal=7.dp,vertical=7.dp).testTag("results_period_${period.name}")){Text(period.titleAr,color=if(active)Color.White else V3Muted,fontSize=8.sp,lineHeight=11.sp,maxLines=1)}
            }}
            val format=remember{SimpleDateFormat("yyyy/MM/dd",Locale.US)}
            Row(Modifier.border(.7.dp,V3Border,RoundedCornerShape(4.dp)).clickable{custom=true}.padding(6.dp).testTag("results_custom_dates"),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(5.dp)) {
                Icon(Icons.Default.CalendarMonth,null,tint=V3Muted,modifier=Modifier.size(13.dp))
                Text(if(a!=null)"${format.format(Date(a.start))} – ${format.format(Date(a.end))}" else "اختيار الفترة",fontSize=8.sp,color=V3Muted,style=TextStyle(textDirection=TextDirection.Ltr))
            }
        }
        if(state.isLoading) LinearProgressIndicator(Modifier.fillMaxWidth(),color=V3Profit)
        if(a==null) {Column(Modifier.fillMaxWidth().padding(20.dp)){Text("لا توجد بيانات تدريب محفوظة بعد",color=V3Muted);Button(onClick=onNavigateToBacktest){Text("ابدأ التدريب على الشارت")}}}
        else when(state.selectedTab) {
            ResultsTab.OVERVIEW->LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(start=8.dp,end=8.dp,bottom=8.dp),verticalArrangement=Arrangement.spacedBy(7.dp)) {
                item{Hero(a,{expanded=true})}
                item{MetricGrid(a)}
                item{RecentTable(a,viewModel,false)}
            }
            ResultsTab.CURVES->LazyColumn(Modifier.fillMaxSize().padding(horizontal=8.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                item{Row(Modifier.horizontalScroll(rememberScrollState())){listOf("Equity","Balance","التراجع","الربح التراكمي").forEach { type->TextButton(onClick={mode=type}){Text(type,color=if(mode==type)V3Profit else V3Muted,fontSize=11.sp)} }}}
                item{Frame{ResultsV3Chart(a.curve,a.days,mode,true)}}
                item{Text("Equity يشمل الربح العائم؛ Balance يشمل النتائج المحققة فقط. الأعمدة: صافي النتيجة اليومية بالدولار. اسحب بإصبعين للتكبير واضغط لتحديد نقطة.",color=V3Muted,fontSize=11.sp)}
            }
            ResultsTab.JOURNAL->LazyColumn(Modifier.fillMaxSize().padding(horizontal=8.dp),verticalArrangement=Arrangement.spacedBy(1.dp)) {
                item{Text("سجل الصفقات · ${a.trades.size}",color=V3Text,fontSize=14.sp,modifier=Modifier.padding(8.dp));TradeHeaders()}
                items(a.trades.indices.reversed().toList(),key={a.trades[it].id}){i->TradeRow(a.trades[i],a.recordedAt[i]){viewModel.selectTradeForDetail(a.trades[i])}}
                if(a.trades.isEmpty()) item{EmptyActivity()}
            }
            ResultsTab.STATISTICS->LazyColumn(Modifier.fillMaxSize().padding(horizontal=8.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                item{MetricGrid(a)}
                item{Frame{val m=a.metrics
                    Detail("متوسط الربح",m.avgWin?.let{v3Money(it)}?:"—");Detail("متوسط الخسارة",m.avgLoss?.let{v3Money(-it)}?:"—")
                    Detail("أكبر ربح",m.bestTrade?.let{v3Money(it)}?:"—");Detail("أكبر خسارة",m.worstTrade?.let{v3Money(it)}?:"—")
                    Detail("متوسط ربح / متوسط خسارة",if(m.avgWin!=null&&m.avgLoss!=null&&m.avgLoss>0)number(m.avgWin/m.avgLoss) else "—")
                    Detail("إجمالي العمولات",v3Money(a.trades.sumOf{it.commission}));Detail("إجمالي رسوم التبييت",v3Money(a.trades.sumOf{it.swap}))
                    Detail("إجمالي حجم العقود",number(m.totalVolume));Detail("متوسط R Multiple",number(m.avgRMultiple))
                }}
                item{Text("شارب: متوسط العوائد اليومية ÷ انحرافها المعياري للعينة، دون تحويل سنوي، ويحتاج يومين على الأقل. التعادل يدخل في عدد الصفقات ويقطع تتابع الربح والخسارة. السبريد مضمن في أسعار Bid/Ask ولا يُخصم مرة ثانية. الفلاتر بحسب وقت تسجيل التدريب، والتفاصيل تحتفظ بوقت السوق.",color=V3Muted,fontSize=11.sp)}
            }
            ResultsTab.DAILY->LazyColumn(Modifier.fillMaxSize().padding(horizontal=8.dp),verticalArrangement=Arrangement.spacedBy(7.dp)) {
                if(a.days.isEmpty())item{EmptyActivity()}
                items(a.days.reversed(),key={it.time}){d->Frame{Detail(SimpleDateFormat("yyyy/MM/dd",Locale.US).format(Date(d.time)),v3Money(d.pnl,true));Detail("الصفقات: ${d.count} · رابحة ${d.wins} · خاسرة ${d.losses}",v3Money(d.closing))}}
            }
            ResultsTab.COMPARISON->Unit
        }
    }
    }
}

@Composable private fun Hero(a:TrainingAnalytics,onExpand:()->Unit) {
    var info by remember { mutableStateOf(false) }
    if(info) AlertDialog(onDismissRequest={info=false},title={Text("الحساب والأداء")},text={Text("الرصيد: ${v3Money(a.closing)}\nEquity: ${v3Money(a.metrics.equity)}\nالربح العائم: ${v3Money(a.floating,true)}\nرأس المال المودع هو رصيد البداية، ولا يُضاف مرتين. الربح المحقق بعد العمولات والتبييت، والسبريد مضمن في أسعار التنفيذ. الأعمدة تمثل صافي نتائج أيام التدريب.")},confirmButton={TextButton(onClick={info=false}){Text("إغلاق")}})
    Frame(Modifier.fillMaxWidth().testTag("results_hero_card")) {Column(Modifier.padding(start=8.dp,top=8.dp,bottom=8.dp)){
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr){Row(Modifier.fillMaxWidth().padding(end=8.dp).heightIn(min=76.dp),horizontalArrangement=Arrangement.spacedBy(8.dp),verticalAlignment=Alignment.Top) {
            Column(Modifier.weight(1.2f)) {Row(verticalAlignment=Alignment.CenterVertically){Text("صافي الربح",color=V3Text,fontSize=12.sp,fontWeight=FontWeight.Bold);Icon(Icons.Default.Info,"تعريفات الحساب",tint=V3Muted,modifier=Modifier.padding(start=5.dp).size(11.dp).clickable{info=true})};Num(v3Money(a.metrics.netProfit,true),24,if(a.metrics.netProfit<0)V3Loss else if(a.metrics.netProfit>0)V3Profit else V3Muted);Num((if(a.metrics.returnPct>0)"+" else "")+pct(a.metrics.returnPct),15,if(a.metrics.netProfit<0)V3Loss else V3Profit)}
            Row(Modifier.weight(2.2f),horizontalArrangement=Arrangement.spacedBy(7.dp)) {listOf("الرصيد النهائي" to a.closing,"الرصيد الابتدائي" to a.opening,"إجمالي الإيداعات" to a.deposits).forEach{(label,value)->Frame(Modifier.weight(1f)){Column(Modifier.padding(horizontal=5.dp,vertical=7.dp),verticalArrangement=Arrangement.spacedBy(4.dp)){Text(label,color=V3Muted,fontSize=8.sp,maxLines=1);Num(v3Money(value),10)}}}}
        }}
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr){ResultsV3Chart(a.curve,a.days,onExpand=onExpand)}
        if(a.trades.isEmpty())Text("لا توجد صفقات مغلقة في هذه الفترة",color=V3Muted,fontSize=8.sp)
    }}
}

@Composable private fun MetricGrid(a:TrainingAnalytics) {
    var showWinDetails by remember { mutableStateOf(false) }
    if(showWinDetails) AlertDialog(onDismissRequest={showWinDetails=false},title={Text("معدل النجاح")},text={Text("${a.metrics.winningTrades} رابحة · ${a.metrics.losingTrades} خاسرة · ${a.metrics.totalTrades-a.metrics.winningTrades-a.metrics.losingTrades} متعادلة. النسبة من جميع الإغلاقات المسجلة.")},confirmButton={TextButton(onClick={showWinDetails=false}){Text("إغلاق")}})

    val m=a.metrics
    val count=m.totalTrades
    data class Metric(val title:String,val value:String,val icon:ImageVector,val color:Color,val note:String)
    val items=listOf(
        Metric("معدل النجاح",if(count>0)String.format(Locale.US,"%.1f%%",m.winRatePct)else "—",Icons.Default.TrackChanges,V3Profit,"${m.winningTrades} رابح / ${m.losingTrades} خاسر"),
        Metric("إجمالي الصفقات",count.toString(),Icons.Default.BarChart,V3Blue,"صفقة مكتملة"),
        Metric("معامل الربح",if(m.grossProfit>0&&m.grossLoss==0.0)"∞" else number(m.profitFactor),Icons.Default.SwapVert,V3Profit,"إجمالي الربح / إجمالي الخسارة"),
        Metric("أقصى تراجع",if(a.curve.size>1)pct(-m.maxDrawdownPct) else "—",Icons.Default.TrendingDown,V3Loss,v3Money(-m.maxDrawdown)),
        Metric("التوقع الرياضي",m.expectancy?.let{v3Money(it)}?:"—",Icons.Default.Functions,V3Profit,"متوسط الربح لكل صفقة"),
        Metric("أقصى ربح متتالٍ",if(count>0)m.maxConsecutiveWins.toString() else "—",Icons.Default.TrendingUp,V3Profit,"صفقات رابحة متتالية"),
        Metric("أقصى خسارة متتالية",if(count>0)m.maxConsecutiveLosses.toString() else "—",Icons.Default.South,V3Loss,"صفقات خاسرة متتالية"),
        Metric("متوسط مدة الصفقة",if(count>0)"${m.avgDurationMillis/3600000} س ${(m.avgDurationMillis/60000)%60} د" else "—",Icons.Default.Schedule,Color(0xFF8B4DFF),"من الفتح إلى الإغلاق"),
        Metric("نسبة شارب",number(m.sharpeRatio),Icons.Default.ShowChart,V3Blue,"العائد / المخاطرة اليومية")
    )
    BoxWithConstraints(Modifier.testTag("results_metrics_grid")) {
        val columns=if(maxWidth>=350.dp && LocalDensity.current.fontScale<1.3f)3 else 2
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr){Column(verticalArrangement=Arrangement.spacedBy(6.dp)){
            items.chunked(columns).forEach{row->Row(Modifier.height(IntrinsicSize.Min),horizontalArrangement=Arrangement.spacedBy(6.dp)) {row.forEachIndexed{index,item->
                Frame(Modifier.weight(if(columns==3)listOf(1.08f,.97f,.99f)[index] else 1f).fillMaxHeight().heightIn(min=64.dp).testTag("results_metric_${item.title}")){
                    Row(Modifier.padding(horizontal=8.dp,vertical=6.dp),horizontalArrangement=Arrangement.spacedBy(6.dp)){
                        if(item.title=="معدل النجاح") Box(Modifier.size(45.dp).clickable{showWinDetails=true}.semantics { contentDescription="${item.value}، ${item.note}" },contentAlignment=Alignment.Center){
                            Canvas(Modifier.fillMaxSize()){drawArc(V3Border,0f,360f,false,style=androidx.compose.ui.graphics.drawscope.Stroke(6.dp.toPx()));if(count>0)drawArc(V3Profit,-90f,(m.winRatePct*3.6).toFloat(),false,style=androidx.compose.ui.graphics.drawscope.Stroke(6.dp.toPx(),cap=androidx.compose.ui.graphics.StrokeCap.Round))};Num(item.value,9)
                        } else Box(Modifier.size(26.dp).clip(RoundedCornerShape(6.dp)).background(item.color.copy(alpha=.12f)),contentAlignment=Alignment.Center){Icon(item.icon,null,tint=item.color,modifier=Modifier.size(18.dp))}
                        Column(Modifier.weight(1f),horizontalAlignment=Alignment.End,verticalArrangement=Arrangement.spacedBy(2.dp)){
                            Text(item.title,color=V3Muted,fontSize=9.sp,lineHeight=11.sp,maxLines=2,textAlign=TextAlign.End,style=TextStyle(textDirection=TextDirection.Rtl))
                            if(item.title!="معدل النجاح")Num(item.value,if(item.title=="متوسط مدة الصفقة")12 else 16,if(item.color==V3Loss)V3Loss else V3Text,Modifier.align(Alignment.Start))
                            Text(item.note,color=V3Muted,fontSize=7.sp,lineHeight=8.sp,maxLines=2,textAlign=TextAlign.End,style=TextStyle(textDirection=TextDirection.Rtl))
                        }
                    }
                }
            };repeat(columns-row.size){Spacer(Modifier.weight(1f))}}}
        }}
    }
}

@Composable private fun RecentTable(a:TrainingAnalytics,vm:ResultsViewModel,all:Boolean) {
    Frame(Modifier.fillMaxWidth().testTag("results_recent_trades")) {
        Row(Modifier.fillMaxWidth().padding(horizontal=8.dp,vertical=7.dp),verticalAlignment=Alignment.CenterVertically){Text("أحدث الصفقات",fontSize=12.sp,lineHeight=16.sp,color=V3Text,fontWeight=FontWeight.Bold,modifier=Modifier.weight(1f));Text("عرض الكل  ‹",color=V3Blue,fontSize=10.sp,modifier=Modifier.clickable{vm.setSelectedTab(ResultsTab.JOURNAL)}.testTag("results_show_all"))}
        TradeHeaders()
        a.trades.indices.reversed().take(5).forEach{i->TradeRow(a.trades[i],a.recordedAt[i]){vm.selectTradeForDetail(a.trades[i])}}
        if(a.trades.isEmpty())EmptyActivity()
    }
}
@Composable private fun TradeHeaders(){TradeCells(listOf("الربح","سعر الإغلاق","سعر الدخول","الحجم","النوع","الرمز","وقت التسجيل"),true)}
@Composable private fun TradeCells(values:List<String>,header:Boolean=false,colors:Map<Int,Color> = emptyMap()) {
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr){Row(Modifier.fillMaxWidth().background(if(header)V3Border.copy(alpha=.2f) else Color.Transparent).padding(horizontal=5.dp,vertical=6.dp),verticalAlignment=Alignment.CenterVertically){
        val weights=listOf(.9f,.8f,.8f,.5f,.55f,.8f,1.35f)
        values.forEachIndexed{i,v->Text(v,color=colors[i]?:if(header)V3Muted else V3Text,fontSize=if(header)8.sp else 10.sp,fontWeight=if(i==0&&!header)FontWeight.Bold else FontWeight.Normal,modifier=Modifier.weight(weights[i]),textAlign=TextAlign.Center,maxLines=1,style=TextStyle(textDirection=if(i==4)TextDirection.Rtl else TextDirection.Ltr,lineHeight=if(header)12.sp else 15.sp))}
        Icon(Icons.Default.MoreVert,null,tint=if(header)Color.Transparent else V3Muted,modifier=Modifier.size(10.dp))
    }}
}
@Composable private fun TradeRow(t:TradeJournalEntry,at:Long,onClick:()->Unit){
    val precision=com.example.core.market.DefaultSymbols.getSymbol(t.symbol).digits
    val fmt="%.${precision}f"
    Column(Modifier.clickable(onClick=onClick).testTag("results_trade_${t.id}")) {
        TradeCells(listOf(v3Money(t.netProfitLoss,true),String.format(Locale.US,fmt,t.exitPrice),String.format(Locale.US,fmt,t.entryPrice),number(t.volume),if(t.side==PositionSide.BUY)"شراء" else "بيع",t.symbol,SimpleDateFormat("MM/dd HH:mm",Locale.US).format(Date(at))),colors=mapOf(0 to if(t.netProfitLoss<0)V3Loss else V3Profit,4 to if(t.side==PositionSide.BUY)V3Profit else V3Loss))
        HorizontalDivider(color=V3Border.copy(alpha=.55f),thickness=.5.dp)
    }
}
@Composable private fun EmptyActivity(){Text("لا يوجد نشاط مغلق في هذه الفترة",color=V3Muted,fontSize=11.sp,modifier=Modifier.padding(14.dp))}
@Composable private fun Detail(label:String,value:String){Row(Modifier.fillMaxWidth().padding(10.dp),horizontalArrangement=Arrangement.SpaceBetween){Text(label,color=V3Muted,fontSize=11.sp,modifier=Modifier.weight(1f));Num(value,12)}}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun CustomDates(initialStart:Long?,initialEnd:Long?,onApply:(Long,Long)->Unit,onDismiss:()->Unit) {
    var start by remember{mutableStateOf(initialStart?:System.currentTimeMillis())}
    var stage by remember{mutableIntStateOf(0)}
    key(stage){val picker=rememberDatePickerState(initialSelectedDateMillis=if(stage==0)start else initialEnd?:System.currentTimeMillis(),selectableDates=object:SelectableDates{override fun isSelectableDate(utcTimeMillis:Long)=utcTimeMillis<=System.currentTimeMillis()})
        DatePickerDialog(onDismissRequest=onDismiss,confirmButton={TextButton(onClick={val chosen=picker.selectedDateMillis?:return@TextButton;if(stage==0){start=chosen;stage=1}else onApply(start,chosen)},enabled=picker.selectedDateMillis!=null&&(stage==0||picker.selectedDateMillis!!>=start)){Text(if(stage==0)"اختيار تاريخ النهاية" else "تطبيق")}},dismissButton={TextButton(onClick=onDismiss){Text("إلغاء")}}){Text(if(stage==0)"تاريخ بداية التسجيل" else "تاريخ نهاية التسجيل",modifier=Modifier.padding(16.dp));DatePicker(picker)}
    }
}
