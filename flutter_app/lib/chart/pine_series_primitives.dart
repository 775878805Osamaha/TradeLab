import 'pine_runtime_core.dart';

/// Candidate bounded history for a globally evaluated expression/call.
/// One committed result per closed bar, including numeric na. Scope-local
/// execution histories require a separate adapter; never fill skipped bars
/// using future values or re-evaluate a stateful call to read its past.
/// https://www.tradingview.com/pine-script-docs/language/operators/
/// https://www.tradingview.com/pine-script-docs/language/execution-model/
final class PineCommittedHistory<T> {
  PineCommittedHistory(this.budget, {required this.capacity, this.missing}) {
    budget.reserveHistory(capacity);
    _ring = List<T?>.filled(capacity,missing);
  }
  final PineRuntimeBudget budget;
  final int capacity;
  final T? missing;
  late final List<T?> _ring;
  int _count=0;
  int get count=>_count;

  void commit(int barIndex,T? value){
    if(barIndex!=_count){
      throw const PineRuntimeException('history_order',
          'A global call result must commit exactly once on each closed bar');
    }
    budget.consume();
    _ring[_count%capacity]=value;
    _count++;
  }

  T? read(int barsAgo){
    if(barsAgo<0||barsAgo>=capacity){
      throw const PineRuntimeException('history_limit',
          'History offset outside the verified retained window');
    }
    budget.consume();
    final index=_count-1-barsAgo;
    return index<0?missing:_ring[index%capacity];
  }
}

/// https://www.tradingview.com/pine-script-reference/v6/#fun_ta.barssince
/// Before the first true condition the result is na, then zero on true.
/// A state belongs to one independently evaluated call.
final class PineBarsSinceState {
  PineBarsSinceState(this.budget){budget.consume(work:0,values:1);}
  final PineRuntimeBudget budget;
  int? _since;
  int? step(bool condition){
    budget.consume();
    if(condition){_since=0;}
    else if(_since!=null){_since=_since!+1;}
    return _since;
  }
}

/// Strict-extremum candidate: returns a pivot on the *confirmation bar*.
/// Does not backdate the result, read future bars or invent a missing source.
/// Ties and incomplete windows are not claimed as Pine-equivalent; actual
/// TradingView output is required for the unresolved tie/na policy.
/// https://www.tradingview.com/pine-script-reference/v6/#fun_ta.pivothigh
/// https://www.tradingview.com/pine-script-reference/v6/#fun_ta.pivotlow
final class PinePivotState {
  PinePivotState(PineRuntimeBudget budget,{required int capacity,required this.high})
      :_history=PineCommittedHistory<double>(budget,capacity:capacity);
  final PineCommittedHistory<double> _history;
  final bool high;

  double? step(int barIndex,num? source,int left,int right){
    if(left<1||right<1||left>=_history.capacity||
        right>=_history.capacity||left+right>=_history.capacity){
      throw const PineRuntimeException('pivot_length',
          'Pivot legs outside the bounded positive candidate window');
    }
    _history.commit(barIndex,
        source!=null&&source.isFinite?source.toDouble():null);
    if(_history.count<=left+right)return null;
    final center=_history.read(right);
    if(center==null)return null;
    var tie=false;
    for(var n=0;n<=left+right;n++){
      if(n==right)continue;
      final other=_history.read(n);
      if(other==null)return null; // Explicit conservative missing-data policy.
      if(high?other>center:other<center)return null;
      if(other==center)tie=true;
    }
    if(tie){
      throw const PineRuntimeException('unverified_pivot_tie',
          'Equal extremum tie requires reference validation before activation');
    }
    return center;
  }
}
