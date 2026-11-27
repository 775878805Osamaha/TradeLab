import 'dart:collection';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/pine_v6_language_runtime.dart';
import 'package:tradelab_flutter/chart/pine_runtime_core.dart';
import 'package:tradelab_flutter/data/tradelab_data.dart';
class _Poison extends ListBase<TradeCandle>{
  _Poison(this.data,this.cutoff);
  final List<TradeCandle> data;final int cutoff;
  @override int get length=>data.length;
  @override set length(int n)=>throw UnsupportedError('readonly');
  @override TradeCandle operator[](int i){if(i>=cutoff)throw StateError('future read');return data[i];}
  @override void operator[]=(int i,TradeCandle v)=>throw UnsupportedError('readonly');
}
const source='''//@version=6
indicator("Visual records")
top = plot(high, "Top", color=color.orange, linewidth=2, style=plot.style_linebr)
bottom = plot(low, "Bottom", color=color.blue)
fill(top,bottom,color=close > open ? color.new(color.teal,84) : na,title="Band")
plotshape(close > open,title="Up",style=shape.labelup,location=location.belowbar,text="UP",size=size.small,color=color.green)
bgcolor(close < open ? color.new(color.red,92) : na,title="Down")
var table stats = table.new(position.top_right,2,2,bgcolor=color.black,border_color=color.gray,border_width=1)
table.cell(stats,0,0,"Count",text_color=color.white,text_size=size.small)
table.cell(stats,1,0,str.tostring(bar_index,"#"))
if close > open
    alert("up",alert.freq_once_per_bar_close)
    alert("duplicate",alert.freq_once_per_bar_close)''';
void main(){
  final bars=[const TradeCandle(1,3,0,2),const TradeCandle(2,3,0,1),const TradeCandle(1,4,0,3)];
  test('assigned plot handles, gap colors, shapes, table overwrite and historical alerts',(){
    final p=PineV6LanguageProgram.compile(source,enableDisplay:true);
    final r=p.newInstance();
    try{
      r.rebuild(bars,3);
      expect(r.outputs.map((x)=>x.values).toList(),[[3,3,4],[0,0,0]]);
      final d=r.displaySnapshot!;
      expect(d.events.where((e)=>e.kind=='plotshape').map((e)=>e.bar),[0,2]);
      final fill=d.events.where((e)=>e.kind=='fill').toList();
      expect(fill.map((e)=>e.args['plot1']),[0,0,0]);expect(fill.map((e)=>e.args['plot2']),[1,1,1]);
      expect(fill[0].args['color'],isNotNull);expect(fill[1].args['color'],isNull);
      final alerts=d.events.where((e)=>e.kind=='alert').toList();
      expect(alerts.map((e)=>e.bar),[0,2]);expect(alerts.map((e)=>e.args['message']),['up','up']);
      expect(alerts.every((e)=>e.args['historicalOnly']==true),isTrue);
      expect(d.tables.single.cells[(1,0)]!.text,'2');
      expect(d.tables.single.cells[(0,0)]!.size,'size.small');
      r.rebuild(_Poison(bars,1),1);
      expect(r.displaySnapshot!.tables.single.cells[(1,0)]!.text,'0');
      expect(r.displaySnapshot!.events.every((e)=>e.bar==0),isTrue);
      expect(d.tables.single.cells[(1,0)]!.text,'2',reason:'prior snapshot immutable');
      r.rebuild(_Poison(bars,3),3);
      expect(r.displaySnapshot!.events.map((e)=>[e.bar,e.kind,e.args]).toList(),d.events.map((e)=>[e.bar,e.kind,e.args]).toList());
    }finally{r.close();}
  });
  test('unsupported display arguments fail compilation and bad table coordinates fail closed',(){
    expect(()=>PineV6LanguageProgram.compile(source),throwsA(isA<PineRuntimeException>()));
    expect(()=>PineV6LanguageProgram.compile(source.replaceAll('linewidth=2','offset=2'),enableDisplay:true),throwsA(isA<PineRuntimeException>()));
    final p=PineV6LanguageProgram.compile(source.replaceAll('stats,1,0','stats,2,0'),enableDisplay:true);
    expect(()=>p.evaluate(bars),throwsA(isA<PineRuntimeException>()));
  });
}
