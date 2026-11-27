import 'pine_runtime_core.dart';
import 'pine_v6_ast.dart';

/// Bounded value-only maps. TradingView reference:
/// https://www.tradingview.com/pine-script-reference/v6/#fun_map.put
/// https://www.tradingview.com/pine-script-docs/language/maps/
/// No reference-valued keys/values, historical map IDs, or intrabar state.
final class PineRuntimeMap {
  PineRuntimeMap._(this.keyType,this.valueType,this.budget){
    budget.consume(work:0,values:1);
  }
  final String keyType,valueType;
  final PineRuntimeBudget budget;
  final Map<Object,Object?> _items={};
  static const names={'map.new','map.get','map.put'};
  static const _types={'int','float','string'};
  static List<String> _params(String? name)=>name=='map.get'?['id','key']:
    name=='map.put'?['id','key','value']:[];
  static List<int> _slots(PineCallExpression call){
    final p=_params(call.name),slots=<int>[],seen=<int>{};
    for(var i=0;i<call.arguments.length;i++){
      final a=call.arguments[i],n=a.name==null?i:p.indexOf(a.name!);
      if(n<0||n>=p.length||!seen.add(n))throw const PineRuntimeException('map_arguments','Invalid map arguments');
      slots.add(n);
    }
    if(seen.length!=p.length)throw const PineRuntimeException('map_arguments','Missing map arguments');
    return slots;
  }
  static void validate(PineCallExpression call){
    _slots(call);
    if(call.name=='map.new'){
      final c=call.callee;
      if(c is! PineGenericReferenceExpression||c.typeArguments.length!=2||
        c.typeArguments.any((x)=>!_types.contains(x.name))){
        throw const PineRuntimeException('unsupported_map_type','Only int, float, string map types are enabled');
      }
    }
  }
  static Object? execute(PineCallExpression call,List<Object?> values,PineRuntimeBudget budget){
    if(call.name=='map.new'){
      final c=call.callee as PineGenericReferenceExpression;
      return PineRuntimeMap._(c.typeArguments[0].name,c.typeArguments[1].name,budget);
    }
    final slots=_slots(call),args=List<Object?>.filled(slots.length,null);
    for(var i=0;i<slots.length;i++)args[slots[i]]=values[i];
    final map=args[0];
    if(map is! PineRuntimeMap)throw const PineRuntimeException('map_type','Expected map reference');
    final key=map._typed(args[1],map.keyType,nullable:false)!;
    budget.consume();
    if(call.name=='map.get')return map._items[key];
    final value=map._typed(args[2],map.valueType,nullable:true);
    final previous=map._items[key];
    if(!map._items.containsKey(key)){
      if(map._items.length>=50000)throw const PineRuntimeException('map_limit','Map pair limit exceeded');
      budget.consume(work:0,values:2);
    }
    map._items[key]=value;
    return previous;
  }
  Object? _typed(Object? x,String type,{required bool nullable}){
    if(x==null&&nullable)return null;
    if(type=='string'&&x is String)return x;
    if(x is num&&x.isFinite){
      if(type=='int'&&x==x.truncateToDouble())return x.toInt();
      if(type=='float')return x.toDouble();
    }
    throw const PineRuntimeException('map_type','Invalid typed map key or value');
  }
}
