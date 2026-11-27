import '../data/tradelab_data.dart';
import 'pine_runtime_core.dart';
import 'pine_v6_ast.dart';

/// Explicit zero-cost, single-entry, full-exit historical emulator tier.
/// No network, broker API, order submission, margin or currency conversion.
final class PineBrokerConfig {
  const PineBrokerConfig({required this.initialCapital,required this.defaultQty,
    required this.pointValue,required this.minTick,required this.processOnClose});
  final double initialCapital,defaultQty,pointValue,minTick;
  final bool processOnClose;
  void validate(){
    if([initialCapital,defaultQty,pointValue,minTick].any((v)=>!v.isFinite||v<=0)){
      throw const PineRuntimeException('broker_config','Positive finite explicit broker settings required');
    }
  }
}
enum PineBrokerDirection {long,short}
typedef PineBrokerTrade=({String entryId,String exitId,int entryBar,int exitBar,
  double entryPrice,double exitPrice,double size,double profit});
typedef PineBrokerFill=({String id,int bar,double price,double signedQty,String phase});
typedef PineBrokerSnapshot=({double size,double? averagePrice,double realizedProfit,
  double equity,List<PineBrokerTrade> closedTrades,List<PineBrokerFill> fills,
  String? pendingEntry,String? pendingExit});
typedef _Entry=({String id,PineBrokerDirection direction,double qty});
typedef _Bracket=({String id,String from,double? stop,double? limit});

final class PineBrokerEmulator {
  PineBrokerEmulator(this.config,this.budget){config.validate();}
  final PineBrokerConfig config;
  final PineRuntimeBudget budget;
  final _trades=<PineBrokerTrade>[];
  final _fills=<PineBrokerFill>[];
  _Entry? _pending;
  _Bracket? _bracket;
  String? _entryId;
  int? _entryBar;
  double? _entryPrice;
  double _size=0,_profit=0;
  TradeCandle? _bar;
  int _index=-1;
  bool _evaluating=false;
  PineBrokerSnapshot get snapshot=>(size:_size,averagePrice:_entryPrice,
    realizedProfit:_profit,equity:config.initialCapital+_profit+
      (_entryPrice==null||_bar==null?0:(_bar!.close-_entryPrice!)*_size*config.pointValue),
    closedTrades:List.unmodifiable(_trades),fills:List.unmodifiable(_fills),
    pendingEntry:_pending?.id,pendingExit:_bracket?.id);
  void _reject(String code,String message)=>throw PineRuntimeException(code,message);
  bool _aligned(double p){
    final ticks=p/config.minTick;
    return ticks.isFinite&&(ticks-ticks.roundToDouble()).abs()<=1e-6;
  }
  void beginBar(int index,TradeCandle b){
    if(_evaluating||index!=_index+1)_reject('broker_order','Sequential confirmed bars required');
    if([b.open,b.high,b.low,b.close].any((p)=>!p.isFinite||!_aligned(p))||
      b.high<b.open||b.high<b.close||b.low>b.open||b.low>b.close||b.low>b.high){
      _reject('broker_ohlc','Invalid or unaligned standard OHLC');
    }
    if(b.timestampMs==null||(_bar!=null&&b.timestampMs!<=_bar!.timestampMs!)){
      _reject('broker_time','Verified increasing bar timestamps required');
    }
    _index=index;_bar=b;budget.consume();
    // A previously active bracket is eligible at the opening gap before
    // evaluating the new bar. Simultaneous reversal and bracket gap are
    // intentionally rejected rather than claiming unverified priority.
    if(_pending!=null&&_size!=0&&_bracket!=null){
      _reject('unsupported_broker_priority','Pending reversal with active bracket not supported');
    }
    if(_pending!=null){final e=_pending!;_pending=null;_fillEntry(e,b.open,'open');}
    _priceBracket(b.open,'open');
    if(_size!=0&&_bracket!=null){
      final x=_bracket!;
      final hitsStop=x.stop!=null&&(_size>0?b.low<=x.stop!:b.high>=x.stop!);
      final hitsLimit=x.limit!=null&&(_size>0?b.high>=x.limit!:b.low<=x.limit!);
      if(hitsStop&&hitsLimit){
        final up=b.high-b.open,down=b.open-b.low;
        if((up-down).abs()<=config.minTick*1e-6){
          _reject('unsupported_broker_tie','Equal-distance OHLC path requires reference');
        }
        final stopFirst=_size>0?down<up:up<down;
        _close(x.id,stopFirst?x.stop!:x.limit!,'intrabar');
      }else if(hitsStop){_close(x.id,x.stop!,'intrabar');}
      else if(hitsLimit){_close(x.id,x.limit!,'intrabar');}
    }
    _evaluating=true;
  }
  void _priceBracket(double price,String phase){
    final x=_bracket;
    if(x==null||_size==0)return;
    final stop=x.stop!=null&&(_size>0?price<=x.stop!:price>=x.stop!);
    final limit=x.limit!=null&&(_size>0?price>=x.limit!:price<=x.limit!);
    if(stop&&limit)_reject('unsupported_broker_bracket','Overlapping stop/limit');
    if(stop||limit)_close(x.id,price,phase);
  }
  void entry(String id,PineBrokerDirection direction,double qty){
    if(!_evaluating||id.isEmpty||!qty.isFinite||qty<=0)_reject('broker_entry','Invalid entry');
    if(_size!=0&&(_size>0)==(direction==PineBrokerDirection.long))return;
    if(_pending!=null&&_pending!.id!=id)_reject('unsupported_broker_multiple','Only one pending entry supported');
    _pending=(id:id,direction:direction,qty:qty);
  }
  void exit(String id,String from,double? stop,double? limit){
    if(!_evaluating||id.isEmpty||from.isEmpty)_reject('broker_exit','Explicit exit and entry IDs required');
    if(stop==null&&limit==null)_reject('broker_exit','At least one exit price required');
    if([stop,limit].whereType<double>().any((p)=>!p.isFinite||!_aligned(p))){
      _reject('broker_exit_tick','Exit price must align to verified tick');
    }
    if(from!=_entryId&&from!=_pending?.id)return;
    if(_bracket!=null&&_bracket!.id!=id)_reject('unsupported_broker_reservation','Partial exits and multiple reservations unsupported');
    final long=from==_pending?.id?_pending!.direction==PineBrokerDirection.long:_size>0;
    if(stop!=null&&limit!=null&&(long?stop>=limit:stop<=limit)){
      _reject('unsupported_broker_bracket','Invalid bracket order');
    }
    _bracket=(id:id,from:from,stop:stop,limit:limit);
  }
  void endBar(){
    if(!_evaluating)_reject('broker_order','No active evaluation');
    if(config.processOnClose){
      if(_pending!=null){
        final e=_pending!;_pending=null;
        if(_size!=0&&_bracket!=null)_reject('unsupported_broker_priority','Reversal with active bracket unsupported');
        _fillEntry(e,_bar!.close,'close');
      }
      _priceBracket(_bar!.close,'close');
    }
    _evaluating=false;
  }
  void _fillEntry(_Entry e,double price,String phase){
    if(_size!=0){
      // Reversal records the close and new exposure separately in the
      // internal ledger; not a claim about TradingView report grouping.
      _close(e.id,price,phase);
    }
    _size=e.direction==PineBrokerDirection.long?e.qty:-e.qty;
    _entryId=e.id;_entryBar=_index;_entryPrice=price;
    _recordFill(e.id,price,_size,phase);
  }
  void _recordFill(String id,double price,double qty,String phase){
    budget.consume(work:1,values:5);
    _fills.add((id:id,bar:_index,price:price,signedQty:qty,phase:phase));
  }
  void _close(String id,double price,String phase){
    if(_size==0)return;
    final profit=(price-_entryPrice!)*_size*config.pointValue;
    if(!profit.isFinite)_reject('broker_profit','Nonfinite trade result');
    budget.consume(work:1,values:8);
    _trades.add((entryId:_entryId!,exitId:id,entryBar:_entryBar!,exitBar:_index,
      entryPrice:_entryPrice!,exitPrice:price,size:_size,profit:profit));
    _recordFill(id,price,-_size,phase);
    _profit+=profit;_size=0;_entryId=null;_entryBar=null;_entryPrice=null;_bracket=null;
  }
  Object? member(String name)=>switch(name){
    'strategy.long'=>PineBrokerDirection.long,'strategy.short'=>PineBrokerDirection.short,
    'strategy.position_size'=>_size,'strategy.position_avg_price'=>_entryPrice,
    'strategy.closedtrades'=>_trades.length.toDouble(),
    'strategy.wintrades'=>_trades.where((t)=>t.profit>0).length.toDouble(),
    'strategy.losstrades'=>_trades.where((t)=>t.profit<0).length.toDouble(),
    _=>throw const PineRuntimeException('unsupported_broker_member','Unsupported broker member'),
  };
  Object? closed(String name,int index){
    if(index<0||index>=_trades.length)return null;
    final t=_trades[index];
    return switch(name){
      'strategy.closedtrades.entry_price'=>t.entryPrice,
      'strategy.closedtrades.exit_price'=>t.exitPrice,
      'strategy.closedtrades.size'=>t.size,
      _=>throw const PineRuntimeException('unsupported_broker_call','Unsupported trade field'),
    };
  }
}

abstract final class PineBrokerDispatch {
  static const members={'strategy.long','strategy.short','strategy.position_size',
    'strategy.position_avg_price','strategy.closedtrades','strategy.wintrades','strategy.losstrades'};
  static const calls={'strategy','strategy.entry','strategy.exit','strategy.closedtrades.entry_price',
    'strategy.closedtrades.exit_price','strategy.closedtrades.size'};
  static const _header=['title','shorttitle','overlay','pyramiding','process_orders_on_close','initial_capital'];
  static List<String> _params(String? name)=>switch(name){
    'strategy'=>_header,'strategy.entry'=>['id','direction','qty'],
    'strategy.exit'=>['id','from_entry','stop','limit'],
    _=>['trade_num'],
  };
  static Map<String,PineExpression> _bind(PineCallExpression call){
    final p=_params(call.name),args=<String,PineExpression>{};
    for(var i=0;i<call.arguments.length;i++){
      final a=call.arguments[i],name=a.name??(i<p.length?p[i]:'');
      // Positional parameters past the unambiguous prefix differ from
      // the full Pine signature, so require names.
      if(a.name==null&&i>= (call.name=='strategy'?1:call.name=='strategy.exit'?2:call.name=='strategy.entry'?3:1)){
        throw const PineRuntimeException('unsupported_broker_arguments','Use named arguments for optional settings');
      }
      if(!p.contains(name)||args.containsKey(name)){
        throw const PineRuntimeException('unsupported_broker_arguments','Unsupported or duplicate broker argument');
      }
      args[name]=a.value;
    }
    return args;
  }
  static void validateHeader(PineScriptAst ast,PineBrokerConfig config){
    final headers=ast.statements.whereType<PineExpressionStatement>().map((s)=>s.expression)
      .whereType<PineCallExpression>().where((c)=>c.name=='strategy').toList();
    if(headers.length!=1)throw const PineRuntimeException('unsupported_broker_header','Explicit strategy declaration required');
    final args=_bind(headers.single);
    String? literal(String name){
      final e=args[name];if(e==null)return null;
      if(e is! PineLiteralExpression)throw const PineRuntimeException('unsupported_broker_header','Literal strategy settings required');
      return e.value;
    }
    for(final k in args.keys){literal(k);}
    final capital=literal('initial_capital');
    if((literal('pyramiding')??'0')!='0'||(literal('process_orders_on_close')??'false')!=config.processOnClose.toString()||
      capital==null||double.tryParse(capital)!=config.initialCapital){
      throw const PineRuntimeException('unsupported_broker_header','Explicit matching capital, close processing and pyramiding=0 required');
    }
  }
  static void validateCall(PineCallExpression call){
    final a=_bind(call);
    final required=switch(call.name){
      'strategy'=>['title'],'strategy.entry'=>['id','direction'],
      'strategy.exit'=>['id','from_entry'],_=>['trade_num'],
    };
    if(!required.every(a.containsKey)||call.name=='strategy.exit'&&!a.containsKey('stop')&&!a.containsKey('limit')){
      throw const PineRuntimeException('broker_arguments','Missing required broker argument');
    }
  }
  static Object? execute(PineBrokerEmulator b,PineCallExpression call,List<Object?> values){
    final keys=_bind(call).keys.toList(),args=<String,Object?>{for(var i=0;i<keys.length;i++)keys[i]:values[i]};
    String str(String k){final v=args[k];if(v is String)return v;throw const PineRuntimeException('broker_type','Expected string ID');}
    double? numValue(String k){final v=args[k];if(v==null)return null;if(v is num)return v.toDouble();throw const PineRuntimeException('broker_type','Expected numeric value');}
    switch(call.name){
      case 'strategy.entry':
        final d=args['direction'];
        if(d is! PineBrokerDirection)throw const PineRuntimeException('broker_type','Expected strategy direction');
        b.entry(str('id'),d,numValue('qty')??b.config.defaultQty);return null;
      case 'strategy.exit':
        b.exit(str('id'),str('from_entry'),numValue('stop'),numValue('limit'));return null;
      default:
        final n=numValue('trade_num');if(n==null||!n.isFinite||n!=n.truncateToDouble())return null;
        return b.closed(call.name!,n.toInt());
    }
  }
}
