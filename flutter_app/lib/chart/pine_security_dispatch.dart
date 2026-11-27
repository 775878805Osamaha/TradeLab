import 'dart:math' as math;
import '../data/tradelab_data.dart';
import 'pine_runtime_core.dart';
import 'pine_v6_ast.dart';

/// Provider must return verified closed source candle or explicit verified gap,
/// never a fabricated bar. null response is unknown coverage, not a gap.
final class PineExternalBar {
  const PineExternalBar(this.candle);
  final TradeCandle? candle;
}
typedef PineExternalLookup=PineExternalBar? Function(String symbol,String timeframe,int openTime,int confirmedThrough);
final class PineRequestedTicker {
  const PineRequestedTicker(this.symbol,this.heikin);
  final String symbol;
  final bool heikin;
  static PineRequestedTicker from(Object? raw){
    if(raw is PineRequestedTicker)return raw;
    if(raw is String&&raw.isNotEmpty)return PineRequestedTicker(raw,false);
    throw const PineRuntimeException('security_ticker','Invalid requested ticker');
  }
}

/// Explicit bounded AST subset; lookahead_on cannot use current requested
/// OHLC. No expression is evaluated in the chart context by accident.
final class PineSecuritySpec {
  const PineSecuritySpec(this.symbol,this.timeframe,this.expression,this.lookahead);
  final PineExpression symbol,timeframe,expression;
  final bool lookahead;
  static const fields={'open','high','low','close','volume','time','hl2','hlc3','ohlc4'};
  static PineSecuritySpec parse(PineCallExpression call){
    const keys=['symbol','timeframe','expression','gaps','lookahead'];
    final args=<String,PineExpression>{};
    for(var i=0;i<call.arguments.length;i++){
      final a=call.arguments[i],name=a.name??(i<keys.length?keys[i]:'');
      if(!keys.contains(name)||args.containsKey(name))throw const PineRuntimeException('unsupported_security_arguments','Unsupported security argument');
      args[name]=a.value;
    }
    if(!keys.take(3).every(args.containsKey))throw const PineRuntimeException('security_arguments','Missing required security arguments');
    String? member(String key){
      final e=args[key];
      if(e==null)return null;
      if(e is PineMemberExpression)return e.qualifiedName;
      throw const PineRuntimeException('unsupported_security_option','Security options must be explicit constants');
    }
    final gap=member('gaps'),look=member('lookahead');
    if(gap!=null&&gap!='barmerge.gaps_off')throw const PineRuntimeException('unsupported_security_gaps','Only gaps_off is supported');
    if(look!=null&&look!='barmerge.lookahead_off'&&look!='barmerge.lookahead_on'){
      throw const PineRuntimeException('unsupported_security_lookahead','Unsupported lookahead');
    }
    final on=look=='barmerge.lookahead_on';
    _validate(args['expression']!,on);
    return PineSecuritySpec(args['symbol']!,args['timeframe']!,args['expression']!,on);
  }
  static int _offset(PineHistoryExpression e){
    final x=e.offset;
    if(x is! PineLiteralExpression||x.literalType!='int')throw const PineRuntimeException('unsupported_security_history','Security history offset must be constant int');
    final n=int.tryParse(x.value);
    if(n==null||n<0||n>500)throw const PineRuntimeException('security_history','Security history outside bounds');
    return n;
  }
  static void _validate(PineExpression e,bool on){
    if(e is PineIdentifierExpression&&fields.contains(e.name)){
      if(on)throw const PineRuntimeException('unsupported_security_future','lookahead_on requires prior requested candle references');
      return;
    }
    if(e is PineHistoryExpression&&e.target is PineIdentifierExpression&&fields.contains((e.target as PineIdentifierExpression).name)){
      if(on&&_offset(e)<1)throw const PineRuntimeException('unsupported_security_future','lookahead_on offset must be positive');
      _offset(e);return;
    }
    if(e is PineLiteralExpression&&const {'int','float','bool','na'}.contains(e.literalType))return;
    if(e is PineTupleExpression){for(final v in e.values){_validate(v,on);}return;}
    if(e is PineUnaryExpression&&const {'-','+','not','!'}.contains(e.operator)){_validate(e.value,on);return;}
    if(e is PineBinaryExpression&&const {'+','-','*','/','%','>','<','>=','<=','==','!=','and','or','&&','||'}.contains(e.operator)){
      _validate(e.left,on);_validate(e.right,on);return;
    }
    if(e is PineTernaryExpression){_validate(e.condition,on);_validate(e.thenValue,on);_validate(e.elseValue,on);return;}
    throw const PineRuntimeException('unsupported_security_expression','Unsupported expression in requested context');
  }
  Object? evaluate(List<TradeCandle> bars,int index,PineRuntimeBudget budget){
    Object? field(String name,int i){
      if(i<0||i>=bars.length)return null;
      final c=bars[i];
      return switch(name){
        'open'=>c.open,'high'=>c.high,'low'=>c.low,'close'=>c.close,'volume'=>c.volume,'time'=>c.timestampMs?.toDouble(),
        'hl2'=>(c.high+c.low)/2,'hlc3'=>(c.high+c.low+c.close)/3,
        'ohlc4'=>(c.open+c.high+c.low+c.close)/4,_=>null,
      };
    }
    bool boolean(Object? x){
      if(x is bool)return x;
      throw const PineRuntimeException('security_type','Expected bool in requested expression');
    }
    Object? eval(PineExpression e){
      budget.consume();
      if(e is PineIdentifierExpression)return field(e.name,index);
      if(e is PineHistoryExpression)return field((e.target as PineIdentifierExpression).name,index-_offset(e));
      if(e is PineLiteralExpression)return switch(e.literalType){
        'int'||'float'=>double.parse(e.value),'bool'=>e.value=='true',_=>null};
      if(e is PineTupleExpression)return <Object?>[for(final v in e.values)eval(v)];
      if(e is PineTernaryExpression)return eval(boolean(eval(e.condition))?e.thenValue:e.elseValue);
      if(e is PineUnaryExpression){
        final x=eval(e.value);
        if(e.operator=='not'||e.operator=='!')return !boolean(x);
        return x==null?null:e.operator=='-'?-(x as num):x;
      }
      final b=e as PineBinaryExpression;
      final x=eval(b.left);
      if(b.operator=='and'||b.operator=='&&')return boolean(x)&&boolean(eval(b.right));
      if(b.operator=='or'||b.operator=='||')return boolean(x)||boolean(eval(b.right));
      final y=eval(b.right);
      if(b.operator=='==')return x!=null&&y!=null&&x==y;
      if(b.operator=='!=')return x!=null&&y!=null&&x!=y;
      if(const {'>','<','>=','<='}.contains(b.operator)){
        if(x==null||y==null)return false;
        final a=x as num,c=y as num;
        return switch(b.operator){'>'=>a>c,'<'=>a<c,'>='=>a>=c,_=>a<=c};
      }
      if(x==null||y==null)return null;
      final a=x as num,c=y as num;
      final v=switch(b.operator){'+'=>a+c,'-'=>a-c,'*'=>a*c,'/'=>c==0?null:a/c,'%'=>c==0?null:a%c,_=>null};
      return v!=null&&v.isFinite?v.toDouble():null;
    }
    return eval(expression);
  }
  Object? missing(){
    final e=expression;
    return e is PineTupleExpression?<Object?>[for(final _ in e.values)null]:null;
  }
}

/// One written request, one instance, strictly confirmed chart bars only.
/// Local minute-based aggregation accepts complete aligned buckets; any
/// incomplete bucket fails closed rather than inventing missing source bars.
final class PineSecurityState {
  PineSecurityState(this.budget,this.spec);
  final PineRuntimeBudget budget;
  final PineSecuritySpec spec;
  final List<TradeCandle> _history=[];
  TradeCandle? _pending;
  int? _bucket,_lastTime,_duration;
  int _bucketBase=0,_lastBar=-1,_count=0;
  String? _symbol;
  bool? _heikin;
  static int _minutes(Object? value){
    if(value is! String||!RegExp(r'^[1-9][0-9]*$').hasMatch(value))throw const PineRuntimeException('unsupported_security_timeframe','Only minute timeframes are enabled');
    final n=int.tryParse(value);
    if(n==null||n>1440)throw const PineRuntimeException('unsupported_security_timeframe','Minute timeframe outside bounds');
    return n*60000;
  }
  void _append(TradeCandle raw,bool heikin){
    budget.consume(work:1,values:5);
    if(!heikin){_history.add(raw);return;}
    final previous=_history.isEmpty?null:_history.last;
    final o=previous==null?(raw.open+raw.close)/2:(previous.open+previous.close)/2;
    final c=(raw.open+raw.high+raw.low+raw.close)/4;
    _history.add(TradeCandle(o,math.max(raw.high,math.max(o,c)),math.min(raw.low,math.min(o,c)),c,
      timestampMs:raw.timestampMs,volume:raw.volume));
  }
  Object? step(int index,TradeCandle raw,PineRequestedTicker ticker,Object? timeframe,
      String chartSymbol,String chartTimeframe,PineExternalLookup? external){
    final stamp=raw.timestampMs;
    final chart=_minutes(chartTimeframe),duration=_minutes(timeframe);
    if(index!=_lastBar+1||stamp==null||stamp%chart!=0||(_lastTime!=null&&stamp<=_lastTime!)){
      throw const PineRuntimeException('security_order','Verified ordered, aligned, once-per-bar execution required');
    }
    if(duration<chart||duration%chart!=0)throw const PineRuntimeException('unsupported_security_lower_tf','Only same or integral higher timeframe supported');
    if(_symbol!=null&&(_symbol!=ticker.symbol||_heikin!=ticker.heikin||_duration!=duration)){
      throw const PineRuntimeException('unsupported_security_dynamic','Changing requested context is not enabled');
    }
    _symbol=ticker.symbol;_heikin=ticker.heikin;_duration=duration;
    _lastBar=index;_lastTime=stamp;
    if(ticker.symbol!=chartSymbol){
      if(duration!=chart||spec.lookahead||external==null){
        throw const PineRuntimeException('unsupported_security_external','External request requires verified same-timeframe closed coverage');
      }
      final found=external(ticker.symbol,timeframe as String,stamp,stamp+chart);
      if(found==null)throw const PineRuntimeException('missing_security_coverage','Requested external candle coverage is unknown');
      final candle=found.candle;
      if(candle!=null){
        if(candle.timestampMs!=stamp)throw const PineRuntimeException('security_external_time','External candle timestamp mismatch');
        _append(candle,ticker.heikin);
      }
      return _history.isEmpty?spec.missing():spec.evaluate(_history,_history.length-1,budget);
    }
    final bucket=stamp-stamp%duration;
    if(_bucket!=bucket){
      if(_pending!=null)throw const PineRuntimeException('security_incomplete_bucket','Missing bars in requested timeframe bucket');
      _bucket=bucket;_bucketBase=_history.length;_count=0;
    }
    if(stamp!=bucket+_count*chart)throw const PineRuntimeException('security_incomplete_bucket','Requested timeframe bucket must start aligned and be complete');
    final p=_pending;
    _pending=p==null?raw:TradeCandle(p.open,math.max(p.high,raw.high),math.min(p.low,raw.low),raw.close,
      timestampMs:bucket,volume:p.volume==null||raw.volume==null?null:p.volume!+raw.volume!);
    _count++;
    if(stamp+chart==bucket+duration){
      _append(_pending!,ticker.heikin);_pending=null;
    }
    if(spec.lookahead)return spec.evaluate(_history,_bucketBase,budget);
    if(_history.isEmpty)return spec.missing();
    return spec.evaluate(_history,_history.length-1,budget);
  }
}
