import 'pine_runtime_core.dart';
import 'pine_v6_ast.dart';

/// Closed-bar context supplied explicitly by the chart adapter. No device
/// clock, fake tick size, invented symbol, or inferred provider metadata.
final class PineExecutionContext {
  PineExecutionContext({this.ticker,this.tickerId,this.symbolType,this.minTick,
    this.timeframePeriod,this.isStandard,this.rightVisibleBarTime,
    this.fixedExchangeUtcOffsetMinutes,Map<int,int> exchangeOffsetsByOpenTime=const {},
    Map<String,Object> overrides=const {}})
    :overrides=Map.unmodifiable(overrides),exchangeOffsetsByOpenTime=Map.unmodifiable(exchangeOffsetsByOpenTime);
  final String? ticker,tickerId,symbolType,timeframePeriod;
  final double? minTick;
  final bool? isStandard;
  final int? rightVisibleBarTime,fixedExchangeUtcOffsetMinutes;
  final Map<int,int> exchangeOffsetsByOpenTime;
  final Map<String,Object> overrides;
  static const members={'syminfo.ticker','syminfo.tickerid','syminfo.type',
    'syminfo.mintick','timeframe.period','timeframe.isminutes',
    'chart.is_standard','chart.right_visible_bar_time','barstate.isconfirmed'};
  static const inputs={'input.int','input.float','input.bool','input.string',
    'input.session','input.timeframe','input.symbol'};
  Object member(String name){
    final Object? value=switch(name){
      'syminfo.ticker'=>ticker,'syminfo.tickerid'=>tickerId,
      'syminfo.type'=>symbolType,
      'syminfo.mintick'=>minTick!=null&&minTick!.isFinite&&minTick!>0?minTick:null,
      'timeframe.period'=>timeframePeriod,
      'timeframe.isminutes'=>timeframePeriod==null?null:
        RegExp(r'^[1-9][0-9]*$').hasMatch(timeframePeriod!),
      'chart.is_standard'=>isStandard,'chart.right_visible_bar_time'=>rightVisibleBarTime?.toDouble(),
      'barstate.isconfirmed'=>true,
      _=>null,
    };
    if(value==null)throw PineRuntimeException('missing_context','Missing verified context: '+name);
    return value;
  }
  static Object? constantValue(PineExpression e,Map<String,Object?> constants){
    if(e is PineIdentifierExpression&&constants.containsKey(e.name))return constants[e.name];
    if(e is PineTupleExpression)return [for(final v in e.values)constantValue(v,constants)];
    if(e is PineUnaryExpression&&(e.operator=='-'||e.operator=='+')){
      final v=constantValue(e.value,constants);
      if(v is num)return e.operator=='-'?-v:v;
    }
    if(e is PineLiteralExpression){
      return switch(e.literalType){
        'int'=>int.parse(e.value),'float'=>double.parse(e.value),
        'bool'=>e.value=='true','string'=>e.value.substring(1,e.value.length-1),
        'na'=>null,_=>throw const PineRuntimeException('unsupported_input','Unsupported input literal'),
      };
    }
    throw const PineRuntimeException('unsupported_input','Input settings must be literal in this tier');
  }
  Object input(PineCallExpression call,{Map<String,Object?> constants=const {}}){
    final args=<String,Object?>{};
    const positional=['defval','title'];
    for(var i=0;i<call.arguments.length;i++){
      final a=call.arguments[i];
      final key=a.name??(i<positional.length?positional[i]:
        (throw const PineRuntimeException('unsupported_input','Use named input settings beyond title')));
      if(args.containsKey(key))throw const PineRuntimeException('input_argument','Duplicate input argument');
      args[key]=constantValue(a.value,constants);
    }
    final key=(args['title'] as String?) ?? '${call.span.line}:${call.span.column}';
    final value=overrides[key]??args['defval'];
    final valid=switch(call.name){
      'input.int'=>value is num&&value.isFinite&&value==value.truncateToDouble(),
      'input.float'=>value is num&&value.isFinite,
      'input.bool'=>value is bool,
      _=>value is String,
    };
    if(!valid||value==null)throw const PineRuntimeException('input_type','Invalid input value');
    final options=args['options'];
    if(options is List&&!options.contains(value))throw const PineRuntimeException('input_options','Input value outside options');
    if(value is num){
      final min=args['minval'],max=args['maxval'],step=args['step'];
      if((min is num&&value<min)||(max is num&&value>max)||(step is num&&step<=0)){
        throw const PineRuntimeException('input_range','Invalid numeric input bounds');
      }
      return value.toDouble();
    }
    return value;
  }

  static List<int> _timeSlots(PineCallExpression call){
    const names=['timeframe','session'];
    final slots=<int>[],seen=<int>{};
    for(var i=0;i<call.arguments.length;i++){
      final a=call.arguments[i],n=a.name==null?i:names.indexOf(a.name!);
      if(n<0||n>=2||!seen.add(n))throw const PineRuntimeException('unsupported_time_arguments','Only chart-timeframe session time is enabled');
      slots.add(n);
    }
    if(slots.length!=2)throw const PineRuntimeException('unsupported_time_arguments','Explicit timeframe and session required');
    return slots;
  }
  void validateTimeCall(PineCallExpression call){
    _timeSlots(call);
    if(timeframePeriod==null||(fixedExchangeUtcOffsetMinutes==null&&exchangeOffsetsByOpenTime.isEmpty)){
      throw const PineRuntimeException('unsupported_time_context','Verified exchange timezone offsets and chart timeframe required');
    }
  }
  // Only one daytime interval with aligned minute-based chart bars. A
  // fixed offset must be from verified fixed-zone metadata, never the device.
  Object? sessionTime(PineCallExpression call,List<Object?> args,int? timestamp){
    final slots=_timeSlots(call),values=List<Object?>.filled(2,null);
    for(var i=0;i<2;i++)values[slots[i]]=args[i];
    final period=values[0],session=values[1];
    final minutes=int.tryParse(timeframePeriod??'');
    if(period!=timeframePeriod||minutes==null||minutes<1||session is! String){
      throw const PineRuntimeException('unsupported_timeframe','Only aligned chart-minute timeframe session supported');
    }
    final match=RegExp(r'^([0-9]{2})([0-9]{2})-([0-9]{2})([0-9]{2})(?::([1-7]+))?$').firstMatch(session);
    if(match==null)throw const PineRuntimeException('unsupported_session','Only single daytime session supported');
    final sh=int.parse(match[1]!),sm=int.parse(match[2]!),eh=int.parse(match[3]!),em=int.parse(match[4]!);
    final start=sh*60+sm,end=eh*60+em;
    if(sh>23||eh>23||sm>59||em>59||start>=end||start%minutes!=0||end%minutes!=0){
      throw const PineRuntimeException('unsupported_session','Session must be daytime and aligned to chart interval');
    }
    if(timestamp==null)throw const PineRuntimeException('missing_time','No verified candle timestamp');
    final offset=exchangeOffsetsByOpenTime[timestamp]??fixedExchangeUtcOffsetMinutes;
    if(offset==null||offset.abs()>840)throw const PineRuntimeException('missing_timezone','No verified timezone offset for candle');
    final local=DateTime.fromMillisecondsSinceEpoch(timestamp+offset*60000,isUtc:true);
    final day=(local.weekday%7+1).toString(),at=local.hour*60+local.minute;
    final days=match[5]??'1234567';
    if(at%minutes!=0||local.second!=0||local.millisecond!=0){
      throw const PineRuntimeException('unsupported_session_alignment','Unaligned candle timestamp');
    }
    return days.contains(day)&&at>=start&&at<end?timestamp.toDouble():null;
  }
}
