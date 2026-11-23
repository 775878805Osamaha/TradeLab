import 'dart:math' as math;
import '../data/tradelab_data.dart';
import 'pine_function_registry.dart';
import 'pine_runtime_core.dart';

/// One state per written call, owned by one indicator instance.
/// Only verified closed bars are passed to step. Null means numeric na.
class PineTaState {
  PineTaState(this.signature,this.budget);
  final PineTaSignature signature;
  final PineRuntimeBudget budget;
  final List<double?> _window=[];
  final List<int> _lengths=[];
  double? _last,_previous,_other,_gain,_loss;
  double _sumGain=0,_sumLoss=0;
  int _samples=0;
  PineTaState? _fast,_slow,_signal,_basis,_deviation;

  double? _number(Object? x){
    if(x==null)return null;
    if(x is num&&x.isFinite)return x.toDouble();
    throw const PineRuntimeException('ta_type','Expected finite numeric source');
  }
  bool _boolean(Object? x){
    if(x is bool)return x;
    throw const PineRuntimeException('ta_type','Expected bool');
  }
  int _length(Object? x){
    final n=_number(x);
    if(n==null||n!=n.truncateToDouble()||n<1||n>math.min(500,budget.limits.maxHistory-1)){
      throw const PineRuntimeException('length','TA length outside fixed 1..500 bound');
    }
    return n.toInt();
  }
  void _push(double? x,int cap,{bool skipNa=false}){
    if(skipNa&&x==null)return;
    if(_window.length==cap)_window.removeAt(0);
    _window.add(x);
    budget.consume(work:cap);
  }
  double? _mean(int n){
    if(_window.length<n||_window.any((x)=>x==null))return null;
    return _window.fold<double>(0,(a,x)=>a+x!)/n;
  }
  double? _rma(double? x,int n){
    if(_last==null){
      _push(x,n,skipNa:true);
      _last=_mean(n);
    }else if(x!=null){
      _last=(_last!*(n-1)+x)/n;
    }
    return _last;
  }
  double? _tr(TradeCandle bar,double? prev,bool handleNa){
    if(prev==null)return handleNa?bar.high-bar.low:null;
    return math.max(bar.high-bar.low,
      math.max((bar.high-prev).abs(),(bar.low-prev).abs()));
  }
  PineTaState _child(String name)=>PineTaState(PineFunctionRegistry.ta[name]!,budget);

  Object? step(List<Object?> args,TradeCandle bar,double? previousClose){
    budget.consume();
    if(args.length!=signature.parameters.length){
      throw const PineRuntimeException('ta_arguments','Wrong TA arity');
    }
    final lens=[for(final slot in signature.lengthSlots)_length(args[slot])];
    if(_lengths.isEmpty&&lens.isNotEmpty){
      _lengths.addAll(lens);
      // Reserve a conservative bounded window even for scalar recurrences.
      budget.reserveHistory(lens.reduce((a,b)=>math.max(a,b))+1);
    }else if(lens.length!=_lengths.length||
        List.generate(lens.length,(i)=>lens[i]!=_lengths[i]).any((x)=>x)){
      throw const PineRuntimeException('ta_dynamic_length','Changing TA length is not supported in batch 1');
    }
    final n=lens.isEmpty?1:lens.first;
    final name=signature.name;
    if(name=='ta.tr')return _tr(bar,previousClose,_boolean(args[0]));
    if(name=='ta.atr')return _rma(_tr(bar,previousClose,true),n);
    final x=_number(args[0]);
    switch(name){
      case 'ta.sma':
        _push(x,n,skipNa:true);return _mean(n);
      case 'ta.ema':
        if(x!=null)_last=_last==null?x:(2*x+(n-1)*_last!)/(n+1);
        return _last;
      case 'ta.rma':return _rma(x,n);
      case 'ta.wma':
        _push(x,n,skipNa:true);
        if(_window.length<n)return null;
        var weighted=0.0;
        for(var i=0;i<n;i++){weighted+=(i+1)*_window[i]!;}
        return weighted/(n*(n+1)/2);
      case 'ta.rsi':
        if(x==null)return null;
        final p=_previous;_previous=x;
        if(p==null)return null;
        final d=x-p,g=math.max(0.0,d),loss=math.max(0.0,-d);
        if(_gain==null){
          _sumGain+=g;_sumLoss+=loss;_samples++;
          if(_samples<n)return null;
          _gain=_sumGain/n;_loss=_sumLoss/n;
        }else{
          _gain=(_gain!*(n-1)+g)/n;
          _loss=(_loss!*(n-1)+loss)/n;
        }
        return _loss==0?100.0:_gain==0?0.0:100-100/(1+_gain!/_loss!);
      case 'ta.highest':case 'ta.lowest':
        // Preserve the existing runtime's full non-null bar-window policy.
        // TradingView missing-value parity is not asserted for this case.
        _push(x,n);
        if(_window.length<n||_window.any((v)=>v==null))return null;
        return _window.cast<double>().reduce(name=='ta.highest'
            ?(a,b)=>math.max(a,b):(a,b)=>math.min(a,b));
      case 'ta.change':case 'ta.roc':
        _push(x,n+1);
        if(_window.length<=n||x==null||_window.first==null)return null;
        final p=_window.first!;
        return name=='ta.change'?x-p:p==0?null:100*(x-p)/p;
      case 'ta.stdev':
        final biased=_boolean(args[2]);
        _push(x,n,skipNa:true);
        final mean=_mean(n);
        if(mean==null||(!biased&&n==1))return null;
        var squares=0.0;
        for(final v in _window){final d=v!-mean;squares+=d*d;}
        return math.sqrt(squares/(biased?n:n-1));
      case 'ta.crossover':case 'ta.crossunder':
        final y=_number(args[1]),p=_previous,q=_other;
        _previous=x;_other=y;
        if(x==null||y==null||p==null||q==null)return false;
        return name=='ta.crossover'?x>y&&p<=q:x<y&&p>=q;
      case 'ta.macd':
        _fast??=_child('ta.ema');_slow??=_child('ta.ema');_signal??=_child('ta.ema');
        final fast=_fast!.step([x,lens[0]],bar,previousClose) as double?;
        final slow=_slow!.step([x,lens[1]],bar,previousClose) as double?;
        final line=fast==null||slow==null?null:fast-slow;
        final signal=_signal!.step([line,lens[2]],bar,previousClose) as double?;
        return <double?>[line,signal,line==null||signal==null?null:line-signal];
      case 'ta.bb':
        _basis??=_child('ta.sma');_deviation??=_child('ta.stdev');
        final mult=_number(args[2]);
        final mid=_basis!.step([x,n],bar,previousClose) as double?;
        final sd=_deviation!.step([x,n,true],bar,previousClose) as double?;
        final d=sd==null||mult==null?null:sd*mult;
        return <double?>[mid,mid==null||d==null?null:mid+d,
          mid==null||d==null?null:mid-d];
    }
    throw PineRuntimeException('unsupported_function',name);
  }
}
