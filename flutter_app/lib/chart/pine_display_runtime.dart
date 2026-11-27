import 'pine_runtime_core.dart';
import 'pine_scalar_primitives.dart';
import 'pine_v6_ast.dart';

/// Renderer-neutral, bounded historical output. Alerts are simulation records
/// only: no notification, webhook, external request, or real execution.
typedef PineVisualEvent=({int bar,String kind,Map<String,Object?> args});
typedef PineTableCell=({String text,PineRgba? textColor,PineRgba? background,String size});
typedef PineTableSnapshot=({int id,String position,int columns,int rows,
  PineRgba? background,PineRgba? borderColor,int borderWidth,Map<(int,int),PineTableCell> cells});
typedef PineDisplaySnapshot=({List<PineVisualEvent> events,List<PineTableSnapshot> tables});
final class PinePlotHandle {
  const PinePlotHandle(this.index);
  final int index;
}
final class PineDisplayTable {
  PineDisplayTable(this.id,this.position,this.columns,this.rows,this.background,this.borderColor,this.borderWidth);
  final int id,columns,rows,borderWidth;
  final String position;
  final PineRgba? background,borderColor;
  final Map<(int,int),PineTableCell> cells={};
  PineTableSnapshot get snapshot=>(id:id,position:position,columns:columns,rows:rows,
    background:background,borderColor:borderColor,borderWidth:borderWidth,cells:Map.unmodifiable(cells));
}
abstract final class PineDisplayDispatch {
  static const calls={'plot','plotshape','fill','bgcolor','table.new','table.cell','alert'};
  static const _styles={'plot.style_line','plot.style_linebr','plot.style_histogram','plot.style_circles','plot.style_stepline'};
  static const _shapes={'shape.circle','shape.labelup','shape.labeldown','shape.triangleup','shape.triangledown','shape.cross','shape.xcross','shape.square','shape.diamond'};
  static const _locations={'location.abovebar','location.belowbar','location.top','location.bottom'};
  static const _sizes={'size.tiny','size.small','size.normal','size.large','size.huge','size.auto'};
  static const _positions={'position.top_left','position.top_center','position.top_right','position.middle_left',
    'position.middle_center','position.middle_right','position.bottom_left','position.bottom_center','position.bottom_right'};
  static const _frequencies={'alert.freq_all','alert.freq_once_per_bar','alert.freq_once_per_bar_close'};
  static const members={..._styles,..._shapes,..._locations,..._sizes,..._positions,..._frequencies};
  static const _parameters=<String,List<String>>{
    'plot':['series','title','color','linewidth','style'],
    'plotshape':['series','title','style','location','color','text','textcolor','size'],
    'fill':['plot1','plot2','color','title'],
    'bgcolor':['color','title'],
    'table.new':['position','columns','rows','bgcolor','border_color','border_width'],
    'table.cell':['table_id','column','row','text','text_color','text_size','bgcolor'],
    'alert':['message','freq'],
  };
  static List<String> _keys(PineCallExpression call){
    final p=_parameters[call.name]!,keys=<String>[];
    final prefix=switch(call.name){'plot'=>2,'plotshape'=>2,'fill'=>2,'bgcolor'=>1,
      'table.new'=>3,'table.cell'=>4,'alert'=>2,_=>0};
    for(var i=0;i<call.arguments.length;i++){
      final a=call.arguments[i];
      if(a.name==null&&i>=prefix)throw const PineRuntimeException('unsupported_display_arguments','Use named optional display arguments');
      final key=a.name??(i<p.length?p[i]:'');
      if(!p.contains(key)||keys.contains(key))throw const PineRuntimeException('unsupported_display_arguments','Unsupported or duplicate display argument');
      keys.add(key);
    }
    final required=switch(call.name){'plot'||'plotshape'=>['series'],'fill'=>['plot1','plot2','color'],
      'bgcolor'=>['color'],'table.new'=>['position','columns','rows'],'table.cell'=>['table_id','column','row'],'alert'=>['message'],_=> <String>[]};
    if(!required.every(keys.contains))throw const PineRuntimeException('display_arguments','Missing display argument');
    return keys;
  }
  static void validate(PineCallExpression call,{required bool global}){
    _keys(call);
    if(const {'plot','plotshape','fill','bgcolor','table.new'}.contains(call.name)&&!global){
      throw const PineRuntimeException('display_scope','Global display declaration required');
    }
  }
  static Map<String,Object?> bind(PineCallExpression call,List<Object?> values){
    final keys=_keys(call);
    return {for(var i=0;i<keys.length;i++)keys[i]:values[i]};
  }
}
final class PineDisplayState {
  PineDisplayState(this.budget);
  final PineRuntimeBudget budget;
  final _events=<PineVisualEvent>[];
  final _tables=<PineDisplayTable>[];
  int? _lastAlertBar;
  PineDisplaySnapshot get snapshot=>(events:List.unmodifiable(_events),tables:List.unmodifiable(_tables.map((t)=>t.snapshot)));
  Never _bad(String message)=>throw PineRuntimeException('display_type',message);
  String _string(Object? x,{String fallback=''}) {
    if(x==null)return fallback;
    if(x is String&&x.length<=16384)return x;
    _bad('Expected bounded display string');
  }
  int _int(Object? x,{int? fallback,int min=0,int max=1000}){
    if(x==null&&fallback!=null)return fallback;
    if(x is num&&x.isFinite&&x==x.truncateToDouble()&&x>=min&&x<=max)return x.toInt();
    _bad('Expected bounded display integer');
  }
  PineRgba? _color(Object? x){
    if(x==null||x is PineRgba)return x as PineRgba?;
    _bad('Expected color or na');
  }
  String _enum(Object? x,Set<String> allowed,String fallback){
    final s=_string(x,fallback:fallback);
    if(!allowed.contains(s))_bad('Unsupported display constant: '+s);
    return s;
  }
  void _event(int bar,String kind,Map<String,Object?> args){
    budget.consume(work:1,values:args.length+3);
    _events.add((bar:bar,kind:kind,args:Map.unmodifiable(args)));
  }
  PinePlotHandle plot(int index,int bar,Map<String,Object?> a,double? value){
    _event(bar,'plot',{'index':index,'value':value,'title':_string(a['title']),
      'color':_color(a['color']),'linewidth':_int(a['linewidth'],fallback:1,min:1,max:4),
      'style':_enum(a['style'],PineDisplayDispatch._styles,'plot.style_line')});
    return PinePlotHandle(index);
  }
  Object? execute(String name,int bar,Map<String,Object?> a){
    switch(name){
      case 'plotshape':
        final show=a['series'];
        if(show is! bool)_bad('Only boolean shape conditions enabled');
        final args={'title':_string(a['title']),'text':_string(a['text']),
          'style':_enum(a['style'],PineDisplayDispatch._shapes,'shape.circle'),
          'location':_enum(a['location'],PineDisplayDispatch._locations,'location.abovebar'),
          'color':_color(a['color']),'textcolor':_color(a['textcolor']),
          'size':_enum(a['size'],PineDisplayDispatch._sizes,'size.auto')};
        if(show)_event(bar,name,args);
        return null;
      case 'fill':
        final x=a['plot1'],y=a['plot2'];
        if(x is! PinePlotHandle||y is! PinePlotHandle)_bad('Fill requires two written plot handles');
        _event(bar,name,{'plot1':x.index,'plot2':y.index,'color':_color(a['color']),'title':_string(a['title'])});
        return null;
      case 'bgcolor':
        _event(bar,name,{'color':_color(a['color']),'title':_string(a['title'])});return null;
      case 'table.new':
        final position=_enum(a['position'],PineDisplayDispatch._positions,'');
        final cols=_int(a['columns'],min:1,max:32),rows=_int(a['rows'],min:1,max:100);
        if(_tables.length>=9||cols*rows>1024||_tables.any((t)=>t.position==position)){
          _bad('Table budget or duplicate position');
        }
        budget.consume(work:1,values:cols*rows+8);
        final t=PineDisplayTable(_tables.length,position,cols,rows,_color(a['bgcolor']),
          _color(a['border_color']),_int(a['border_width'],fallback:0,max:4));
        _tables.add(t);return t;
      case 'table.cell':
        final t=a['table_id'];
        if(t is! PineDisplayTable||!_tables.contains(t))_bad('Unknown table handle');
        final col=_int(a['column'],max:t.columns-1),row=_int(a['row'],max:t.rows-1);
        final text=_string(a['text']);
        final rawSize=_string(a['text_size'],fallback:'size.normal');
        final size=rawSize.startsWith('size.')?rawSize:'size.'+rawSize;
        if(!PineDisplayDispatch._sizes.contains(size))_bad('Unsupported text size');
        budget.consume(work:1+text.length);
        t.cells[(col,row)]=(text:text,textColor:_color(a['text_color']),background:_color(a['bgcolor']),size:size);
        return null;
      case 'alert':
        final message=_string(a['message']);
        final freq=_enum(a['freq'],PineDisplayDispatch._frequencies,'alert.freq_once_per_bar');
        if(freq!='alert.freq_all'&&_lastAlertBar==bar)return null;
        _lastAlertBar=bar;
        budget.consume(work:message.length);
        _event(bar,'alert',{'message':message,'frequency':freq,'historicalOnly':true});return null;
      default:_bad('Unsupported display call');
    }
  }
}
