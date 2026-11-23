import 'pine_runtime_core.dart';

/// Stage 3b batch 1: executable signatures, not the entire Pine API.
/// Lengths are fixed per written call site; tuples are library-only.
class PineTaSignature {
  const PineTaSignature(this.name, this.parameters,
      {this.defaults=const {}, this.lengthSlots=const [],
       this.booleanResult=false, this.tupleResult=false,
       this.legacy=false});
  final String name;
  final List<String> parameters;
  final Map<String,Object> defaults;
  final List<int> lengthSlots;
  final bool booleanResult, tupleResult, legacy;
  bool isBooleanParameter(int slot)=>
      parameters[slot]=='biased'||parameters[slot]=='handle_na';

  List<int> bind(List<String?> names) {
    final slots=<int>[];
    final seen=<int>{};
    for(var i=0;i<names.length;i++){
      final slot=names[i]==null?i:parameters.indexOf(names[i]!);
      if(slot<0||slot>=parameters.length||!seen.add(slot)){
        throw PineRuntimeException('ta_arguments','Invalid arguments for $name');
      }
      slots.add(slot);
    }
    for(var i=0;i<parameters.length;i++){
      if(!seen.contains(i)&&!defaults.containsKey(parameters[i])){
        throw PineRuntimeException('ta_arguments','Missing ${parameters[i]} for $name');
      }
    }
    return slots;
  }

  List<Object?> arguments(List<String?> names,List<Object?> values){
    final slots=bind(names);
    final args=<Object?>[for(final p in parameters)defaults[p]];
    for(var i=0;i<slots.length;i++){args[slots[i]]=values[i];}
    return args;
  }
}

class PineFunctionRegistry {
  static const ta=<String,PineTaSignature>{
    'ta.sma':PineTaSignature('ta.sma',['source','length'],lengthSlots:[1],legacy:true),
    'ta.ema':PineTaSignature('ta.ema',['source','length'],lengthSlots:[1],legacy:true),
    'ta.rma':PineTaSignature('ta.rma',['source','length'],lengthSlots:[1]),
    'ta.wma':PineTaSignature('ta.wma',['source','length'],lengthSlots:[1]),
    'ta.rsi':PineTaSignature('ta.rsi',['source','length'],lengthSlots:[1],legacy:true),
    'ta.atr':PineTaSignature('ta.atr',['length'],lengthSlots:[0]),
    'ta.tr':PineTaSignature('ta.tr',['handle_na']),
    'ta.macd':PineTaSignature('ta.macd',['source','fastlen','slowlen','siglen'],lengthSlots:[1,2,3],tupleResult:true),
    'ta.bb':PineTaSignature('ta.bb',['source','length','mult'],lengthSlots:[1],tupleResult:true),
    'ta.stdev':PineTaSignature('ta.stdev',['source','length','biased'],defaults:{'biased':true},lengthSlots:[1]),
    'ta.highest':PineTaSignature('ta.highest',['source','length'],lengthSlots:[1],legacy:true),
    'ta.lowest':PineTaSignature('ta.lowest',['source','length'],lengthSlots:[1],legacy:true),
    'ta.change':PineTaSignature('ta.change',['source','length'],defaults:{'length':1},lengthSlots:[1],legacy:true),
    'ta.roc':PineTaSignature('ta.roc',['source','length'],lengthSlots:[1],legacy:true),
    'ta.crossover':PineTaSignature('ta.crossover',['source1','source2'],booleanResult:true),
    'ta.crossunder':PineTaSignature('ta.crossunder',['source1','source2'],booleanResult:true),
  };
}
