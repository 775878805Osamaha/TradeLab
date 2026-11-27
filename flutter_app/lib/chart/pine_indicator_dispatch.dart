import '../data/tradelab_data.dart';
import 'pine_v6_frontend.dart';
import 'pine_runtime_core.dart';
import 'pine_indicator_seed_candidates.dart';

/// One state per written call path; no reference output is used as input.
/// Fixed length/factor, confirmed closed bars only. Interior EMA na, DMI
/// zero TR and dynamic ST factor remain explicitly outside this tier.
final class PineIndicatorDispatch {
  PineIndicatorDispatch(this.name,this.budget);
  final String name;
  final PineRuntimeBudget budget;
  static const _params=<String,List<String>>{
    'ta.ema':['source','length'],
    'ta.macd':['source','fastlen','slowlen','siglen'],
    'ta.dmi':['diLength','adxSmoothing'],
    'ta.supertrend':['factor','atrPeriod'],
  };
  static Iterable<String> get names=>_params.keys;
  static bool supports(String? name)=>_params.containsKey(name);
  static List<int> _slots(PineCallExpression call){
    final params=_params[call.name]!,slots=<int>[],seen=<int>{};
    for(var i=0;i<call.arguments.length;i++){
      final arg=call.arguments[i],slot=arg.name==null?i:params.indexOf(arg.name!);
      if(slot<0||slot>=params.length||!seen.add(slot)){
        throw PineRuntimeException('ta_arguments','Invalid argument to '+call.name!);
      }
      slots.add(slot);
    }
    if(seen.length!=params.length)throw const PineRuntimeException('ta_arguments','Missing TA argument');
    return slots;
  }
  static bool _lengthSlot(String name,int slot)=>name=='ta.dmi'||slot>0;
  static void validate(PineCallExpression call,Map<PineExpression,PineTypeInfo> types){
    final slots=_slots(call);
    for(var i=0;i<slots.length;i++){
      final length=_lengthSlot(call.name!,slots[i]);
      final value=call.arguments[i].value,type=types[value];
      if(type!=null&&type.type!=PineBaseType.unknown){
        if(length&&(type.type!=PineBaseType.intType||type.qualifier.index>PineQualifier.simple.index)){
          throw const PineRuntimeException('ta_type','Length must be simple int');
        }
        if(!length&&type.type!=PineBaseType.floatType&&type.type!=PineBaseType.intType){
          throw const PineRuntimeException('ta_type','Expected numeric input');
        }
      }
      if(length&&value is PineLiteralExpression){
        final n=int.tryParse(value.value);
        if(n==null||n<1||n>500)throw const PineRuntimeException('length','TA length must be 1..500');
      }
    }
  }
  static List<Object?> bind(PineCallExpression call,List<Object?> values){
    final slots=_slots(call),out=List<Object?>.filled(_params[call.name]!.length,null);
    for(var i=0;i<slots.length;i++)out[slots[i]]=values[i];
    return out;
  }
  Object? _state;
  List<num>? _parameters;
  int _lastBar=-1;
  int _length(Object? n){
    if(n is! num||!n.isFinite||n.truncateToDouble()!=n||n<1||n>500){
      throw const PineRuntimeException('length','TA length must be bounded positive integer');
    }
    return n.toInt();
  }
  double? _source(Object? n){
    if(n==null)return null;
    if(n is! num||!n.isFinite)throw const PineRuntimeException('ta_type','Invalid numeric source');
    return n.toDouble();
  }
  Object? step(int barIndex,List<Object?> a,TradeCandle bar){
    if(barIndex!=_lastBar+1)throw const PineRuntimeException('history_order','Indicator call must execute once per confirmed bar in this tier');
    _lastBar=barIndex;
    final p=<num>[
      if(name=='ta.supertrend')_source(a[0])??(throw const PineRuntimeException('ta_type','Factor is na')),
      for(var i=0;i<a.length;i++)if(_lengthSlot(name,i))_length(a[i])
    ];
    final prev=_parameters;
    if(prev!=null&&(prev.length!=p.length||List.generate(p.length,(i)=>p[i]!=prev[i]).any((x)=>x))){
      throw const PineRuntimeException('ta_dynamic_length','Changing length/factor is not supported');
    }
    _parameters??=p;
    switch(name){
      case 'ta.ema':
        final state=(_state??=PineSmaSeededEma(budget,p[0].toInt())) as PineSmaSeededEma;
        return state.step(_source(a[0]));
      case 'ta.macd':
        final state=(_state??=PineSeededMacd(budget,fast:p[0].toInt(),slow:p[1].toInt(),signal:p[2].toInt())) as PineSeededMacd;
        final r=state.step(_source(a[0]));
        return <Object?>[r.line,r.signal,r.histogram];
      case 'ta.dmi':
        final state=(_state??=PineDmiCandidate(budget,length:p[0].toInt(),smoothing:p[1].toInt())) as PineDmiCandidate;
        final r=state.step(bar);
        return <Object?>[r.plus,r.minus,r.adx];
      case 'ta.supertrend':
        final state=(_state??=PineSupertrendCandidate(budget,factor:p[0].toDouble(),length:p[1].toInt())) as PineSupertrendCandidate;
        final r=state.step(bar);
        return <Object?>[r.value,r.direction];
      default:throw const PineRuntimeException('unsupported_indicator','Unsupported indicator');
    }
  }
}
