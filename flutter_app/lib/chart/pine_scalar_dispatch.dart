import 'pine_v6_ast.dart';
import 'pine_runtime_core.dart';
import 'pine_scalar_primitives.dart';

/// Bounded, typed scalar subset used only by the general AST interpreter.
/// No market timezone, tick-size, array format, or visual-rendering claim.
/// https://www.tradingview.com/pine-script-docs/concepts/strings/
/// https://www.tradingview.com/pine-script-docs/visuals/colors/
abstract final class PineScalarDispatch {
  static const _params=<String,List<String>>{
    'math.floor':['number'],'math.sign':['number'],'math.sum':['source','length'],
    'str.contains':['source','str'],'str.tostring':['value','format'],
    'str.format_time':['time','format','timezone'],'color.new':['color','transp'],
  };
  static Iterable<String> get names=>_params.keys;
  static bool supports(String? name)=>_params.containsKey(name);
  static const _rgb=<String,int>{
    'color.aqua':0x00BCD4,'color.black':0x363A45,'color.blue':0x2196F3,
    'color.fuchsia':0xE040FB,'color.gray':0x787B86,'color.green':0x4CAF50,
    'color.lime':0x00E676,'color.maroon':0x880E4F,'color.navy':0x311B92,
    'color.olive':0x808000,'color.orange':0xFF9800,'color.purple':0x9C27B0,
    'color.red':0xF23645,'color.silver':0xB2B5BE,'color.teal':0x089981,
    'color.white':0xFFFFFF,'color.yellow':0xFDD835,
  };
  static bool isColorMember(String? name)=>_rgb.containsKey(name);
  static PineRgba memberColor(String? name){
    final rgb=_rgb[name];
    if(rgb==null)throw const PineRuntimeException('unsupported_color','Unknown color member');
    return PineRgba(rgb>>16,(rgb>>8)&255,rgb&255,255);
  }
  static PineRgba parseColor(String value){
    if(!RegExp(r'^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(value)){
      throw const PineRuntimeException('unsupported_color','Invalid RGBA literal');
    }
    final hex=value.substring(1);
    final rgba=int.parse(hex.length==6?hex+'ff':hex,radix:16);
    return PineRgba((rgba>>24)&255,(rgba>>16)&255,(rgba>>8)&255,rgba&255);
  }
  static List<int> _slots(PineCallExpression call){
    final params=_params[call.name]!;
    final slots=<int>[],seen=<int>{};
    for(var i=0;i<call.arguments.length;i++){
      final arg=call.arguments[i];
      final slot=arg.name==null?i:params.indexOf(arg.name!);
      if(slot<0||slot>=params.length||!seen.add(slot)){
        throw PineRuntimeException('scalar_arguments','Invalid argument for '+call.name!);
      }
      slots.add(slot);
    }
    final required=call.name=='str.tostring'?1:params.length;
    for(var i=0;i<required;i++){
      if(!seen.contains(i)){
        throw PineRuntimeException('scalar_arguments','Missing explicit '+params[i]+' for '+call.name!);
      }
    }
    return slots;
  }
  static void validate(PineCallExpression call){
    final slots=_slots(call);
    if(call.name=='str.tostring'||call.name=='str.format_time'){
      // Formatting with unknown runtime pattern or instrument metadata is
      // deliberately gated. Explicit constant formats only in this PR.
      for(var i=0;i<slots.length;i++){
        if(slots[i]==0)continue;
        final arg=call.arguments[i].value;
        if(arg is! PineLiteralExpression||arg.literalType!='string'){
          throw const PineRuntimeException('unsupported_format','Formatting requires explicit string literal parameters');
        }
        final value=arg.value.substring(1,arg.value.length-1);
        if(call.name=='str.tostring'){
          PineScalarPrimitives.toText(1,format:value);
        }
      }
      if(call.name=='str.format_time'){
        String literal(int slot){
          final a=call.arguments[slots.indexOf(slot)].value as PineLiteralExpression;
          return a.value.substring(1,a.value.length-1);
        }
        PineScalarPrimitives.formatTime(0,format:literal(1),timezone:literal(2));
      }
    }
  }
  static List<Object?> bind(PineCallExpression call,List<Object?> values){
    final slots=_slots(call),out=List<Object?>.filled(_params[call.name]!.length,null);
    if(call.name=='str.tostring')out[1]='#.########';
    for(var i=0;i<slots.length;i++)out[slots[i]]=values[i];
    return out;
  }
  static num? _numeric(Object? x){
    if(x==null||x is num)return x as num?;
    throw const PineRuntimeException('scalar_type','Expected number or na');
  }
  static String _string(Object? x){
    if(x is String&&x.length<=16384)return x;
    throw const PineRuntimeException('scalar_type','Expected bounded string');
  }
  static Object? evaluate(String name,List<Object?> a,PineRuntimeBudget budget){
    budget.consume();
    switch(name){
      case 'math.floor':return PineScalarPrimitives.floor(_numeric(a[0]));
      case 'math.sign':return PineScalarPrimitives.sign(_numeric(a[0]));
      case 'str.contains':
        final s=_string(a[0]),q=_string(a[1]);
        budget.consume(work:s.length+q.length+1);
        return s.contains(q);
      case 'str.tostring':
        return PineScalarPrimitives.toText(a[0],format:_string(a[1]));
      case 'str.format_time':
        final t=_numeric(a[0]);
        if(t!=null&&(!t.isFinite||t.truncateToDouble()!=t)){
          throw const PineRuntimeException('scalar_type','Timestamp requires integer milliseconds');
        }
        return PineScalarPrimitives.formatTime(t?.toInt(),
          format:_string(a[1]),timezone:_string(a[2]));
      case 'color.new':
        final color=a[0];
        if(color!=null&&color is! PineRgba){
          throw const PineRuntimeException('scalar_type','Expected RGBA color or na');
        }
        return PineScalarPrimitives.withTransparency(color as PineRgba?,_numeric(a[1]));
      default:throw const PineRuntimeException('unsupported_scalar','Scalar dispatch is not implemented');
    }
  }
}
