import 'pine_v6_ast.dart';

class PineLexResult {
  const PineLexResult(this.tokens,this.diagnostics);
  final List<PineToken> tokens;
  final List<PineDiagnostic> diagnostics;
}

/// Source positions are 1-based. INDENT/DEDENT denote Pine local blocks.
/// In parentheses or brackets, continuation may have any indentation.
/// Outside them, an unfinished expression can continue on non-block lines.
class PineV6Lexer {
  const PineV6Lexer({
    this.maxSourceLength=60000,
    this.maxTokens=12000,
    this.maxDuration=const Duration(seconds: 3),
    this.maxIndent=64,
  });
  final int maxSourceLength,maxTokens,maxIndent;
  final Duration maxDuration;

  static const _words=<String>{
    'indicator','strategy','library','var','varip','if','else','switch',
    'for','while','to','by','break','continue','true','false','na',
    'and','or','not','const','input','simple','series','int','float',
    'bool','string','color','import','export','method','type','enum',
  };
  static const _symbols=<String>{
    ':=','=>','+=','-=','*=','/=','%=','==','!=','<=','>=','&&','||',
    '**','+','-','*','/','%','=','<','>','!','?',';',':',',','.','(',
    ')','[',']','{','}',
  };
  static const _continuedAfter=<String>{
    '+','-','*','/','%','=',':=','+=','-=','*=','/=','%=',
    '==','!=','<=','>=','<','>','?','and','or','not',',','.',':',
  };

  PineLexResult lex(String source) {
    final tokens=<PineToken>[];
    final diagnostics=<PineDiagnostic>[];
    if(source.length>maxSourceLength) {
      return PineLexResult(const [],[
        const PineDiagnostic(PineDiagnosticStage.lexer,
          'source_limit','Pine source exceeds lexical size budget',
          PineSourceSpan(1,1)),
      ]);
    }
    final clock=Stopwatch()..start();
    final src=source.replaceAll('\r\n','\n').replaceAll('\r','\n');
    final indents=<int>[0];
    var i=0,line=1,col=1,depth=0,atStart=true,continued=false;
    String? previousText;
    bool isAlpha(String c)=>RegExp(r'[A-Za-z_\u0080-\uFFFF]').hasMatch(c);
    bool isDigit(String c)=>c.codeUnitAt(0)>=48&&c.codeUnitAt(0)<=57;
    bool isWord(String c)=>isAlpha(c)||isDigit(c);
    bool isHex(String c)=>RegExp(r'[0-9a-fA-F]').hasMatch(c);

    void issue(String code,String message,int l,int c) {
      if(diagnostics.length<48) {
        diagnostics.add(PineDiagnostic(PineDiagnosticStage.lexer,
          code,message,PineSourceSpan(l,c)));
      }
    }
    void put(PineTokenKind kind,String text,int l,int c,[int? eLine,int? eCol]) {
      if(tokens.length>=maxTokens) {
        issue('token_limit','Pine token budget exceeded',l,c);
        return;
      }
      tokens.add(PineToken(kind,text,PineSourceSpan(l,c,eLine,eCol)));
      if(kind!=PineTokenKind.indent&&kind!=PineTokenKind.dedent&&
          kind!=PineTokenKind.newline) previousText=text;
    }
    void tick() {
      if(i>=src.length)return;
      if(src[i]=='\n'){line++;col=1;atStart=true;}else{col++;}
      i++;
    }
    while(i<src.length) {
      if(tokens.length>=maxTokens)break;
      if((i&127)==0 && clock.elapsed>=maxDuration) {
        issue('lexer_timeout','Pine lexical deadline exceeded',line,col);
        break;
      }
      if(atStart) {
        final l=line;
        var spaces=0;
        while(i<src.length && (src[i]==' '||src[i]=='\t')) {
          spaces+=src[i]=='\t'?4:1;
          tick();
        }
        if(i>=src.length)break;
        if(src[i]=='\n'){tick();continue;}
        if(src.startsWith('//',i)) {
          while(i<src.length&&src[i]!='\n')tick();
          if(i<src.length)tick();
          continue;
        }
        if(depth==0&&!continued) {
          if(spaces>maxIndent*4) {
            issue('indent_limit','Pine indentation too deep',l,1);
          }
          if(spaces%4!=0) {
            issue('indent_width','Pine local scope needs four-space indentation',l,1);
          }
          if(spaces>indents.last) {
            indents.add(spaces);
            put(PineTokenKind.indent,'<indent>',l,1);
          } else if(spaces<indents.last) {
            while(indents.length>1 && spaces<indents.last) {
              indents.removeLast();
              put(PineTokenKind.dedent,'<dedent>',l,1);
            }
            if(spaces!=indents.last) {
              issue('inconsistent_indent','Pine indentation does not match an enclosing scope',l,1);
            }
          }
        } else if(depth==0&&continued && spaces>0 && spaces%4==0) {
          issue('continuation_indent',
            'Unparenthesized continuation must not look like a local block',l,1);
        }
        atStart=false;
        continued=false;
      }
      if(i>=src.length)break;
      final c=src[i];
      if(c==' '||c=='\t'){tick();continue;}
      if(c=='\n') {
        final wasContinuation=depth>0||_continuedAfter.contains(previousText);
        if(!wasContinuation) {
          put(PineTokenKind.newline,'<newline>',line,col);
          previousText=null;
        }
        continued=wasContinuation;
        tick();
        continue;
      }
      if(src.startsWith('//',i)) {
        while(i<src.length&&src[i]!='\n')tick();
        continue;
      }
      final l=line,startCol=col,start=i;
      if(c=="'"||c=='"') {
        final triple=src.startsWith(c+c+c,i);
        final delim=triple?c+c+c:c;
        for(var n=0;n<delim.length;n++)tick();
        var closed=false;
        while(i<src.length) {
          if(src[i]=='\\'&&i+1<src.length) {tick();tick();continue;}
          if(src.startsWith(delim,i)) {
            for(var n=0;n<delim.length;n++)tick();
            closed=true;break;
          }
          if(!triple&&src[i]=='\n')break;
          tick();
        }
        if(!closed)issue('unterminated_string','Unterminated string literal',l,startCol);
        put(PineTokenKind.string,src.substring(start,i),l,startCol,line,col);
        continue;
      }
      if(c=='#') {
        tick();
        while(i<src.length&&isHex(src[i]))tick();
        final text=src.substring(start,i);
        if(text.length!=7&&text.length!=9) {
          issue('invalid_color','Expected #RRGGBB or #RRGGBBAA',l,startCol);
        }
        put(PineTokenKind.color,text,l,startCol,line,col);
        continue;
      }
      if(isAlpha(c)) {
        tick();
        while(i<src.length&&isWord(src[i]))tick();
        final word=src.substring(start,i);
        put(_words.contains(word)?PineTokenKind.keyword:
            PineTokenKind.identifier,word,l,startCol,line,col);
        continue;
      }
      if(isDigit(c)||(c=='.'&&i+1<src.length&&isDigit(src[i+1]))) {
        var decimal=false;
        if(c=='.'){decimal=true;tick();}
        while(i<src.length&&isDigit(src[i]))tick();
        if(!decimal&&i<src.length&&src[i]=='.'&&
            i+1<src.length&&isDigit(src[i+1])) {
          tick();
          while(i<src.length&&isDigit(src[i]))tick();
        }
        if(i<src.length&&(src[i]=='e'||src[i]=='E')) {
          final save=i,saveCol=col;
          tick();
          if(i<src.length&&(src[i]=='+'||src[i]=='-'))tick();
          if(i<src.length&&isDigit(src[i])) {
            while(i<src.length&&isDigit(src[i]))tick();
          } else {
            i=save;col=saveCol;
          }
        }
        put(PineTokenKind.number,src.substring(start,i),l,startCol,line,col);
        continue;
      }
      String? matched;
      for(final size in [2,1]) {
        if(i+size<=src.length) {
          final candidate=src.substring(i,i+size);
          if(_symbols.contains(candidate)){matched=candidate;break;}
        }
      }
      if(matched!=null) {
        for(var n=0;n<matched.length;n++)tick();
        if(matched=='('||matched=='['||matched=='{')depth++;
        if(matched==')'||matched==']'||matched=='}') {
          depth--;
          if(depth<0) {
            issue('unbalanced_delimiter','Unexpected closing delimiter',l,startCol);
            depth=0;
          }
        }
        put(PineTokenKind.symbol,matched,l,startCol,line,col);
        continue;
      }
      issue('unexpected_character','Unsupported Pine character: '+c,l,startCol);
      tick();
    }
    if(depth>0)issue('unclosed_delimiter','Unclosed Pine delimiter',line,col);
    if(tokens.isNotEmpty&&tokens.last.kind!=PineTokenKind.newline) {
      put(PineTokenKind.newline,'<newline>',line,col);
    }
    while(indents.length>1) {
      indents.removeLast();
      put(PineTokenKind.dedent,'<dedent>',line,col);
    }
    tokens.add(PineToken(PineTokenKind.eof,'<eof>',
        PineSourceSpan(line,col)));
    clock.stop();
    return PineLexResult(tokens,diagnostics);
  }
}
