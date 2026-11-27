import '../data/tradelab_data.dart';
import 'pine_v6_ast.dart';
import 'pine_runtime_core.dart';

/// Bounded closed-bar dispatch; local skipped-call histories intentionally
/// fail closed. Pivot high ties and missing-source behavior remain partial.
abstract final class PineSeriesDispatch {
  static const names=['ta.barssince','ta.pivothigh','ta.pivotlow'];
  static bool supports(String? name)=>names.contains(name);
  static List<String> _params(PineCallExpression call){
    if(call.name=='ta.barssince')return ['condition'];
    final explicit=call.arguments.length==3||call.arguments.any((a)=>a.name=='source');
    return explicit?['source','leftbars','rightbars']:['leftbars','rightbars'];
  }
  static List<int> _slots(PineCallExpression call){
    final params=_params(call),slots=<int>[],seen=<int>{};
    for(var i=0;i<call.arguments.length;i++){
      final arg=call.arguments[i],slot=arg.name==null?i:params.indexOf(arg.name!);
      if(slot<0||slot>=params.length||!seen.add(slot)){
        throw PineRuntimeException('series_arguments','Invalid argument to '+call.name!);
      }
      slots.add(slot);
    }
    if(seen.length!=params.length)throw const PineRuntimeException('series_arguments','Missing required series argument');
    return slots;
  }
  static void validate(PineCallExpression call){_slots(call);}
  static List<Object?> bind(PineCallExpression call,List<Object?> values,TradeCandle bar){
    final params=_params(call),slots=_slots(call);
    final args=List<Object?>.filled(params.length,null);
    for(var i=0;i<slots.length;i++)args[slots[i]]=values[i];
    if(call.name=='ta.barssince'||params.length==3)return args;
    return [call.name=='ta.pivothigh'?bar.high:bar.low,...args];
  }
}
