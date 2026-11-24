part of 'pine_v6_semantic.dart';

// Semantic-only catalogue. Each exact key links to its own v6 manual entry
// via the reference getter. No runtime dispatch is added here.
// Parameter encoding: name[?]:base[/maximum qualifier]; | is a type union.
class _LibrarySignature {
  const _LibrarySignature(this.parameters,this.result,{this.unimplemented=true});
  final List<String> parameters;
  final String result;
  final bool unimplemented;
}
class _LibraryMember {
  const _LibraryMember(this.type,{this.unimplemented=true});
  final PineTypeInfo type;
  final bool unimplemented;
}
const _libraryTypes=<String,PineBaseType>{
  'int':PineBaseType.intType,'float':PineBaseType.floatType,
  'bool':PineBaseType.boolType,'string':PineBaseType.stringType,
  'color':PineBaseType.colorType,'tuple':PineBaseType.tupleType,
  'void':PineBaseType.voidType,'map':PineBaseType.mapType,
  'table':PineBaseType.tableType,'lookahead':PineBaseType.lookaheadType,
  'gaps':PineBaseType.gapsType,'direction':PineBaseType.directionType,
  'oca':PineBaseType.ocaType,
};
const _simpleString=PineTypeInfo(PineBaseType.stringType,PineQualifier.simple);
const _simpleBool=PineTypeInfo(PineBaseType.boolType,PineQualifier.simple);
const _simpleFloat=PineTypeInfo(PineBaseType.floatType,PineQualifier.simple);
const _seriesBool=PineTypeInfo(PineBaseType.boolType,PineQualifier.series);
const _seriesInt=PineTypeInfo(PineBaseType.intType,PineQualifier.series);
const _seriesFloat=PineTypeInfo(PineBaseType.floatType,PineQualifier.series);
const _constString=PineTypeInfo(PineBaseType.stringType,PineQualifier.constant);
const _constColor=PineTypeInfo(PineBaseType.colorType,PineQualifier.constant);
const _lookahead=PineTypeInfo(PineBaseType.lookaheadType,PineQualifier.constant);
const _gaps=PineTypeInfo(PineBaseType.gapsType,PineQualifier.constant);
const _direction=PineTypeInfo(PineBaseType.directionType,PineQualifier.constant);
const _oca=PineTypeInfo(PineBaseType.ocaType,PineQualifier.constant);

// Exact references: https://www.tradingview.com/pine-script-reference/v6/
// var_ for variables, const_ for constants, fun_ for functions. See handoff
// for individual links and coverage limitations.
final _pineMembers=<String,_LibraryMember>{
  'timeframe.isminutes':const _LibraryMember(_simpleBool,unimplemented:false),
  'timeframe.period':const _LibraryMember(_simpleString),
  'syminfo.ticker':const _LibraryMember(_simpleString),
  'syminfo.tickerid':const _LibraryMember(_simpleString),
  'syminfo.type':const _LibraryMember(_simpleString),
  'syminfo.mintick':const _LibraryMember(_simpleFloat),
  'chart.is_standard':const _LibraryMember(_simpleBool),
  'chart.right_visible_bar_time':const _LibraryMember(_seriesInt),
  'barstate.isconfirmed':const _LibraryMember(_seriesBool),
  'strategy.position_size':const _LibraryMember(_seriesFloat),
  'strategy.position_avg_price':const _LibraryMember(_seriesFloat),
  'strategy.closedtrades':const _LibraryMember(_seriesInt),
  'strategy.wintrades':const _LibraryMember(_seriesInt),
  'strategy.losstrades':const _LibraryMember(_seriesInt),
  'strategy.long':const _LibraryMember(_direction),
  'strategy.short':const _LibraryMember(_direction),
  'strategy.oca.none':const _LibraryMember(_oca),
  'strategy.oca.cancel':const _LibraryMember(_oca),
  'strategy.oca.reduce':const _LibraryMember(_oca),
  'barmerge.lookahead_on':const _LibraryMember(_lookahead),
  'barmerge.lookahead_off':const _LibraryMember(_lookahead),
  'barmerge.gaps_on':const _LibraryMember(_gaps),
  'barmerge.gaps_off':const _LibraryMember(_gaps),
  'alert.freq_all':const _LibraryMember(_constString),
  'alert.freq_once_per_bar':const _LibraryMember(_constString),
  'alert.freq_once_per_bar_close':const _LibraryMember(_constString),
  for(final name in ['top_left','top_center','top_right','middle_left','middle_center',
    'middle_right','bottom_left','bottom_center','bottom_right'])
    'position.$name':const _LibraryMember(_constString),
  for(final name in ['auto','tiny','small','normal','large','huge'])
    'size.$name':const _LibraryMember(_constString,unimplemented:false),
  for(final name in ['black','blue','gray','green','lime','orange','purple','red','teal',
    'white','yellow','aqua','fuchsia','maroon','navy','olive','silver'])
    'color.$name':const _LibraryMember(_constColor,unimplemented:false),
  for(final name in ['line','linebr','histogram','columns','area','areabr','circles','cross','stepline','stepline_diamond','steplinebr'])
    'plot.style_$name':const _LibraryMember(_constString,unimplemented:false),
  for(final name in ['circle','labelup','labeldown','triangleup','triangledown','cross','xcross','square','diamond','arrowup','arrowdown','flag'])
    'shape.$name':const _LibraryMember(_constString,unimplemented:false),
  for(final name in ['abovebar','belowbar','top','bottom','absolute'])
    'location.$name':const _LibraryMember(_constString,unimplemented:false),
  for(final name in ['mintick','price','volume','percent','inherit'])
    'format.$name':const _LibraryMember(_constString,unimplemented:false),
  'math.pi':const _LibraryMember(PineTypeInfo(PineBaseType.floatType,PineQualifier.constant)),
};
const _inputTail='tooltip?:string/const inline?:string/const group?:string/const confirm?:bool/const display?:any active?:bool/input';
const _inputString='defval:string/const title?:string/const options?:tuple $_inputTail';
const _pineCalls=<String,_LibrarySignature>{
  'ticker.standard':_LibrarySignature(['symbol?:string'],'ticker'),
  'ticker.heikinashi':_LibrarySignature(['symbol:string'],'ticker'),
  'time':_LibrarySignature([
    'timeframe:string session?:string bars_back?:int timeframe_bars_back?:int',
    'timeframe:string session:string timezone:string bars_back?:int timeframe_bars_back?:int'
  ],'int'),
  'strategy.closedtrades.exit_price':_LibrarySignature(['trade_num:int'],'float'),
  'strategy.closedtrades.entry_price':_LibrarySignature(['trade_num:int'],'float'),
  'strategy.closedtrades.size':_LibrarySignature(['trade_num:int'],'float'),
  'strategy.entry':_LibrarySignature([
    'id:string direction:direction qty?:float limit?:float stop?:float oca_name?:string oca_type?:oca comment?:string alert_message?:string disable_alert?:bool'
  ],'void'),
  'strategy.exit':_LibrarySignature([
    'id:string from_entry?:string qty?:float qty_percent?:float profit?:float limit?:float loss?:float stop?:float trail_price?:float trail_points?:float trail_offset?:float oca_name?:string comment?:string comment_profit?:string comment_loss?:string comment_trailing?:string alert_message?:string alert_profit?:string alert_loss?:string alert_trailing?:string disable_alert?:bool'
  ],'void'),
  'map.get':_LibrarySignature(['id:map key:key'],'mapValue'),
  'map.put':_LibrarySignature(['id:map key:key value:value'],'mapValue'),
  'table.new':_LibrarySignature([
    'position:string columns:int rows:int bgcolor?:color frame_color?:color frame_width?:int border_color?:color border_width?:int force_overlay?:bool/const'
  ],'table'),
  'table.cell':_LibrarySignature([
    'table_id:table column:int row:int text?:string width?:float height?:float text_color?:color text_halign?:string text_valign?:string text_size?:string|int bgcolor?:color tooltip?:string text_font_family?:string text_formatting?:any'
  ],'void'),
  'alert':_LibrarySignature(['message:string freq?:string/input'],'void'),
  'input.int':_LibrarySignature([
    'defval:int/const title?:string/const options?:tuple $_inputTail',
    'defval:int/const title?:string/const minval?:int/const maxval?:int/const step?:int/const $_inputTail'
  ],'int/input',unimplemented:false),
  'input.float':_LibrarySignature([
    'defval:float/const title?:string/const options?:tuple $_inputTail',
    'defval:float/const title?:string/const minval?:float/const maxval?:float/const step?:float/const $_inputTail'
  ],'float/input',unimplemented:false),
  'input.bool':_LibrarySignature(['defval:bool/const title?:string/const $_inputTail'],'bool/input'),
  'input.string':_LibrarySignature([_inputString],'string/input'),
  'input.session':_LibrarySignature([_inputString],'string/input'),
  'input.timeframe':_LibrarySignature([_inputString],'string/input'),
  'input.symbol':_LibrarySignature(['defval:string/const title?:string/const $_inputTail'],'string/input'),
  'request.security':_LibrarySignature([
    'symbol:string timeframe:string expression:any gaps?:gaps lookahead?:lookahead ignore_invalid_symbol?:bool currency?:string calc_bars_count?:int'
  ],'security'),
  'ta.dmi':_LibrarySignature(['diLength:int/simple adxSmoothing:int/simple'],'tuple'),
  'ta.supertrend':_LibrarySignature(['factor:float atrPeriod:int/simple'],'tuple'),
  'ta.barssince':_LibrarySignature(['condition:bool'],'int'),
  'ta.pivothigh':_LibrarySignature(['source:float leftbars:float rightbars:float','leftbars:float rightbars:float'],'float'),
  'ta.pivotlow':_LibrarySignature(['source:float leftbars:float rightbars:float','leftbars:float rightbars:float'],'float'),
  'math.sum':_LibrarySignature(['source:float length:int'],'float'),
  'math.floor':_LibrarySignature(['number:float'],'int'),
  'math.sign':_LibrarySignature(['number:float'],'float'),
  'str.tostring':_LibrarySignature(['value:int|float|bool|string format?:string'],'string'),
  'str.format_time':_LibrarySignature(['time:int format?:string timezone?:string'],'string'),
  'color.new':_LibrarySignature(['color:color transp:float'],'color'),
};
