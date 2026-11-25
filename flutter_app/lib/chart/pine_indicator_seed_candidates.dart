import 'dart:math' as math;
import '../data/tradelab_data.dart';
import 'pine_runtime_core.dart';

/// Separate candidate for the owner's second capture's SMA-seeded EMA
/// contract. The existing executable ta.ema() is deliberately unchanged
/// until actual first-bar reference parity and legacy regressions are proven.
/// https://www.tradingview.com/support/solutions/43000592270-exponential-moving-average/
final class PineSmaSeededEma {
  PineSmaSeededEma(this.budget,this.length) {
    if(length<1||length>budget.limits.maxHistory) {
      throw const PineRuntimeException('length','Invalid bounded EMA length');
    }
    budget.consume(work:0,values:3);
  }
  final PineRuntimeBudget budget;
  final int length;
  int _count=0;
  double _sum=0;
  double? _value;

  double? step(double? source) {
    budget.consume();
    if(source==null){
      if(_value!=null)throw const PineRuntimeException(
        'unverified_ema_na','Interior na after EMA initialization needs reference proof');
      return null;
    }
    if(!source.isFinite)throw const PineRuntimeException('ta_type','Nonfinite EMA input');
    if(_value==null){
      _sum+=source;
      _count++;
      if(_count==length)_value=_sum/length;
    }else{
      final alpha=2.0/(length+1);
      _value=alpha*source+(1-alpha)*_value!;
    }
    if(_value!=null&&!_value!.isFinite)throw const PineRuntimeException('ta_range','EMA result overflow');
    return _value;
  }
}

/// MACD candidate composed from SMA-seeded EMAs, with explicit independent
/// signal warm-up. No Pine tuple/runtime dispatch is registered here.
final class PineSeededMacd {
  PineSeededMacd(PineRuntimeBudget budget,{required int fast,required int slow,required int signal})
      :_fast=PineSmaSeededEma(budget,fast),
       _slow=PineSmaSeededEma(budget,slow),
       _signal=PineSmaSeededEma(budget,signal);
  final PineSmaSeededEma _fast,_slow,_signal;
  ({double? line,double? signal,double? histogram}) step(double? source){
    final fast=_fast.step(source),slow=_slow.step(source);
    final line=fast==null||slow==null?null:fast-slow;
    final signal=_signal.step(line);
    return (line:line,signal:signal,histogram:line==null||signal==null?null:line-signal);
  }
}

/// Closed-bar Supertrend candidate. Band continuation and direction use
/// the documented formulas; the previous band is nz(...,0). First-bar and
/// warm-up expectations are owner-reported until the real capture arrives.
/// https://www.tradingview.com/support/solutions/43000634738-supertrend/
/// https://www.tradingview.com/support/solutions/43000501823-average-true-range-atr/
final class PineSupertrendCandidate {
  PineSupertrendCandidate(this.budget,{required this.factor,required this.length}){
    if(!factor.isFinite||factor<0||length<1||length>budget.limits.maxHistory){
      throw const PineRuntimeException('ta_arguments','Invalid bounded Supertrend settings');
    }
    budget.consume(work:0,values:9);
  }
  final PineRuntimeBudget budget;
  final double factor;
  final int length;
  int _samples=0;
  double _trSum=0;
  double? _atr,_previousClose,_upper,_lower,_trend;

  ({double? value,int direction}) step(TradeCandle bar){
    budget.consume();
    if(!bar.open.isFinite||!bar.high.isFinite||!bar.low.isFinite||!bar.close.isFinite||
        bar.high<math.max(bar.open,bar.close)||bar.low>math.min(bar.open,bar.close)){
      throw const PineRuntimeException('ta_type','Invalid OHLC input');
    }
    final prevClose=_previousClose,previousAtr=_atr;
    final tr=prevClose==null?bar.high-bar.low:
      math.max(bar.high-bar.low,math.max((bar.high-prevClose).abs(),(bar.low-prevClose).abs()));
    if(_atr==null){
      _trSum+=tr;
      _samples++;
      if(_samples==length)_atr=_trSum/length;
    }else{
      _atr=(tr+(length-1)*_atr!)/length;
    }
    final atr=_atr,mid=(bar.high+bar.low)/2;
    final upper=atr==null?null:mid+factor*atr;
    final lower=atr==null?null:mid-factor*atr;
    final prevUpper=_upper??0.0,prevLower=_lower??0.0;
    _upper=((upper!=null&&upper<prevUpper)||(prevClose!=null&&prevClose>prevUpper))
      ?upper:prevUpper;
    _lower=((lower!=null&&lower>prevLower)||(prevClose!=null&&prevClose<prevLower))
      ?lower:prevLower;
    final int direction;
    if(previousAtr==null){
      direction=1;
    }else if(_trend!=null&&_trend==prevUpper){
      direction=_upper!=null&&bar.close>_upper!?-1:1;
    }else{
      direction=_lower!=null&&bar.close<_lower!?1:-1;
    }
    _trend=direction==-1?_lower:_upper;
    _previousClose=bar.close;
    return (value:_trend,direction:direction);
  }
}

/// DMI candidate, first pair of bars supplies TR and directional movement.
/// https://www.tradingview.com/support/solutions/43000502250-directional-movement-dmi/
final class PineDmiCandidate {
  PineDmiCandidate(this.budget,{required int length,required int smoothing})
      :_tr=_WilderSeed(budget,length),_plus=_WilderSeed(budget,length),
       _minus=_WilderSeed(budget,length),_adx=_WilderSeed(budget,smoothing);
  final PineRuntimeBudget budget;
  final _WilderSeed _tr,_plus,_minus,_adx;
  TradeCandle? _previous;
  ({double? plus,double? minus,double? adx}) step(TradeCandle bar){
    budget.consume();
    final prev=_previous;
    _previous=bar;
    if(prev==null)return (plus:null,minus:null,adx:null);
    final up=bar.high-prev.high,down=prev.low-bar.low;
    final tr=math.max(bar.high-bar.low,
      math.max((bar.high-prev.close).abs(),(bar.low-prev.close).abs()));
    final t=_tr.step(tr),p=_plus.step(up>down&&up>0?up:0),
      m=_minus.step(down>up&&down>0?down:0);
    if(t==null||p==null||m==null)return (plus:null,minus:null,adx:null);
    if(t==0)throw const PineRuntimeException('unverified_dmi_zero_tr',
      'Zero true range needs separate reference validation');
    final diP=100*p/t,diM=100*m/t,total=diP+diM;
    final adx=_adx.step(total==0?0:(diP-diM).abs()/total);
    return (plus:diP,minus:diM,adx:adx==null?null:100*adx);
  }
}
final class _WilderSeed {
  _WilderSeed(this.budget,this.length){
    if(length<1||length>budget.limits.maxHistory){
      throw const PineRuntimeException('length','Invalid bounded Wilder length');
    }
    budget.consume(work:0,values:3);
  }
  final PineRuntimeBudget budget;
  final int length;
  int _samples=0;
  double _sum=0;
  double? _last;
  double? step(double value){
    budget.consume();
    if(_last==null){
      _sum+=value;
      if(++_samples==length)_last=_sum/length;
    }else{
      _last=(value+(length-1)*_last!)/length;
    }
    return _last;
  }
}
