# 自由变量体检：用到的标识符，在**它所在的作用域**里有没有声明过。
#
# 为什么非得有这个：2026-09-30 交付前抓到一次 —— `frame()` 里第一行就是
# `S.tSec += dt;`，而 dt **在 frame 里一次都没声明过**（它在别的函数里当形参）。
# 于是 frame() 每次调用都抛 ReferenceError，画面永远是黑的（rAF 在函数开头
# 就挂好了，所以循环不停、控制台刷屏，但一帧都没画出来）。
#
# 而当时**所有检查全绿**：语法配平 0、作用域体检过、六套 harness 全过
# （448 + 85 + 58 + 41 + 36 + 41 全 PASS）、交付自检 18 项全 PASS、构建报成功。
#
# 为什么全都抓不到，这就是本检查存在的全部理由：
#   ① 每一套 harness 都自己 supply 一个 dt —— 替身里 dt 永远是有的；
#   ② _scopecheck 查的是「调用的**函数**有没有声明」，不是「用到的**变量**
#      有没有声明」。dt 是个量，压根不在它的射程里；
#   ③ 语法检查的前提是「已经是合法 JS」，而 ReferenceError 是**合法**的，
#      它要等运行那一刻才炸。
#
# ⚠️⚠️ 第一版犯的错，值得单独记：declared 集合取的是**全文件并集**。
#     那样 `dt` 因为在 updateWeather / bgmTick / audioUpdate / cruiseTick /
#     moodTick / approach 里都当形参，就被判成「有声明」—— 坏样本照样 PASS。
#     **并集看不见作用域**，而这个 bug 恰恰是「在 A 里用、只在 B 里声明」。
#     反查一上来就把它顶回来了（这正是反查存在的意义）。
#     所以这里老老实实建函数表：每个函数记下形参 + 函数体范围，
#     一次「用到」要能在**外层链上任意一层**找到出处才算数。
#
# 精度定位：宁可漏报不可误报。块级作用域（{} 里的 let）不细分 ——
# 同一个块里的声明会算给整个函数，方向是漏判不是误报。
# 已知不支持：class 的方法体内部作用域（方法名会当自由变量报出来），
#  这个源文件里没有 class，真要用会立刻报出来、到时候再扩。
#
# 自检在 _freevartest.ps1：喂一份「删掉 dt 声明」的坏副本，必须 FAIL **并点名 dt**。
param(
  [Parameter(Mandatory=$true)][string]$Path,
  [switch]$Quiet,
  [int]$Dump = 0
)
$ErrorActionPreference = 'Stop'

if (-not ('JsFreeVar' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Text;

public class FvTok {
  public int kind;          // 0 标识符 1 符号 2 数字/字面量
  public string t;
  public int line;
  public FvTok prev;
  public FvTok next;
}

public class FvRes {
  public List<string> report = new List<string>();
  public List<string> dump = new List<string>();
  public int usedCount;
  public int declaredCount;
  public int fnCount;
}

public class FvFn {
  public int ps, pe;                       // 形参括号组（含），裸箭头函数时 ps>pe
  public int bs, be;                       // 函数体 token 区间（含）
  public string name = "";
  public HashSet<string> decl = new HashSet<string>();
}

public class JsFreeVar {

  static readonly HashSet<string> GLOBALS = new HashSet<string>(new string[]{
    "Object","Array","String","Number","Boolean","Math","JSON","Date","RegExp","Error",
    "TypeError","RangeError","SyntaxError","EvalError","Map","Set","WeakMap","WeakSet",
    "Promise","Symbol","Proxy","Reflect","BigInt","Intl","parseInt","parseFloat","isNaN",
    "isFinite","NaN","Infinity","undefined","null","true","false","eval","Function",
    "ArrayBuffer","Uint8Array","Int8Array","Uint8ClampedArray","Float32Array","Float64Array",
    "Int32Array","Uint32Array","DataView","TextEncoder","TextDecoder","URL","URLSearchParams",
    "Blob","FormData","Headers","Request","Response","fetch","AbortController",
    "setTimeout","clearTimeout","setInterval","clearInterval","queueMicrotask",
    "requestAnimationFrame","cancelAnimationFrame","requestIdleCallback",
    "structuredClone","console","window","document","navigator","location","history",
    "localStorage","sessionStorage","performance","crypto","self","globalThis",
    "alert","prompt","confirm","atob","btoa","Image","ImageData","ImageBitmap",
    "OffscreenCanvas","Audio","AudioContext","webkitAudioContext","OfflineAudioContext",
    "FileReader","XMLHttpRequest","WebSocket","Worker","MessageChannel",
    "HTMLElement","HTMLCanvasElement","HTMLVideoElement","HTMLAudioElement","CSS",
    "customElements","getComputedStyle","matchMedia","screen","devicePixelRatio",
    "innerWidth","innerHeight","outerWidth","outerHeight","scrollX","scrollY",
    "Event","CustomEvent","MouseEvent","KeyboardEvent","PointerEvent","WheelEvent",
    "TouchEvent","UIEvent","FocusEvent","AnimationEvent","TransitionEvent",
    "ResizeObserver","IntersectionObserver","MutationObserver",
    "MediaRecorder","MediaStream","VideoEncoder","AudioWorklet","speechSynthesis",
    "Notification","CanvasRenderingContext2D","WebGL2RenderingContext","ImageCapture",
    "addEventListener","removeEventListener","dispatchEvent","postMessage",
    "THREE","Stats","OrbitControls","Pathfinding"
  });

  static readonly HashSet<string> KEYWORDS = new HashSet<string>(new string[]{
    "var","let","const","function","return","if","else","for","while","do","switch",
    "case","default","break","continue","new","delete","typeof","instanceof","in",
    "of","this","super","class","extends","static","get","set","async","throw","try",
    "catch","finally","void","yield","await","import","export","from","as","with",
    "debugger","enum"
  });

  public static FvRes Scan(string js) {
    var r = new FvRes();
    List<FvTok> T = Tokenize(js);
    int n = T.Count;
    r.fnCount = 0;

    // ── 1) 函数表 ──
    var fns = new List<FvFn>();
    var classBodies = new List<KeyValuePair<int,int>>();
    var skip = new HashSet<string>();          // 明确不是变量的名字（class 方法名等）
    var declAt = new List<KeyValuePair<int,string>>();   // 声明所在的 token 下标
    var catchDecl = new HashSet<string>();

    for (int i = 0; i < n; i++) {
      FvTok t = T[i];
      if (t.kind != 0) continue;

      if (t.t == "function" && i + 1 < n && T[i + 1].kind == 0) {
        int j = i + 2;
        int o = FindSymbol(T, j, "(");
        if (o < 0) continue;
        int c = Match(T, o, "(", ")");
        int b = FindSymbol(T, c + 1, "{");
        if (b < 0) continue;
        int e = Match(T, b, "{", "}");
        var f = new FvFn { ps = o, pe = c, bs = b, be = e, name = T[i + 1].t };
        ParamNames(T, o, c, f.decl);
        fns.Add(f);
        declAt.Add(new KeyValuePair<int,string>(i + 1, f.name));
        r.fnCount++;
        continue;
      }

      if (t.t == "class" && i + 1 < n && T[i + 1].kind == 0) {
        declAt.Add(new KeyValuePair<int,string>(i + 1, T[i + 1].t));
        int b = FindSymbol(T, i + 2, "{");
        if (b >= 0) {
          int e = Match(T, b, "{", "}");
          classBodies.Add(new KeyValuePair<int,int>(b, e));
          SkipMethodNames(T, b, e, skip);
          // 每个方法也是一个作用域：形参 + 方法体。第一版没做，
          // 于是 constructor(n) / m(a,b) 的 a b n 全成了自由变量。
          for (int mi = b + 1; mi < e; mi++) {
            if (T[mi].kind != 0) continue;
            FvTok pp = T[mi].prev;
            if (pp != null && (pp.t == "." || pp.t == "?.")) continue;
            FvTok nn = T[mi].next;
            if (nn == null || nn.kind != 1 || nn.t != "(") continue;
            int cc = Match(T, mi, "(", ")");
            if (cc < 0 || cc + 1 >= T.Count) continue;
            if (!(T[cc + 1].kind == 1 && T[cc + 1].t == "{")) continue;
            int be2 = Match(T, cc + 1, "{", "}");
            if (be2 < 0) continue;
            var mf = new FvFn { ps = mi, pe = cc, bs = cc + 1, be = be2, name = T[mi].t };
            ParamNames(T, mi, cc, mf.decl);
            fns.Add(mf);
            r.fnCount++;
            mi = cc;
          }
        }
        continue;
      }

      if (t.t == "var" || t.t == "let" || t.t == "const") {
        Declarators(T, i + 1, declAt);
        continue;
      }
      if (t.t == "catch" && i + 1 < n && T[i + 1].kind == 1 && T[i + 1].t == "(") {
        // catch(e) 的 e 是声明。第一版漏了它，`catch(_){}` 里的 `_`
        // 被当成自由变量 —— 而 catch 并不属于任何函数形参表。
        int c2 = Match(T, i + 1, "(", ")");
        if (c2 > 0) ParamNames(T, i + 1, c2, catchDecl);
        continue;
      }
    }

    // 箭头函数（含表达式体）
    for (int i = 0; i < n; i++) {
      FvTok t = T[i];
      if (t.kind != 1 || t.t != "=>") continue;
      var f = new FvFn { ps = 0, pe = -1, bs = i + 1, be = i + 1, name = "(arrow)" };
      if (i > 0 && T[i - 1].kind == 1 && T[i - 1].t == ")") {
        int o = FindOpen(T, i - 1);
        if (o >= 0) { f.ps = o; f.pe = i - 1; ParamNames(T, o, i - 1, f.decl); }
      } else if (i > 0 && T[i - 1].kind == 0 && !KEYWORDS.Contains(T[i - 1].t)) {
        f.decl.Add(T[i - 1].t);
      }
      // 体
      if (i + 1 < n && T[i + 1].kind == 1 && T[i + 1].t == "{") {
        f.bs = i + 1;
        f.be = Match(T, i + 1, "{", "}");
      } else {
        f.bs = i + 1;
        f.be = ExprEnd(T, i + 1);
      }
      fns.Add(f);
      r.fnCount++;
    }

    // ── 2) 把声明摊到「包含它的每一层函数」上；不在任何函数里的算全局 ──
    var globals = new HashSet<string>();
    foreach (var d in declAt) {
      bool inside = false;
      for (int k = 0; k < fns.Count; k++) {
        if (d.Key >= fns[k].bs && d.Key <= fns[k].be) { fns[k].decl.Add(d.Value); inside = true; }
      }
      if (!inside) globals.Add(d.Value);
    }
    // catch 的形参在块级作用域里，但把它摊到全局 + 每一层函数上，
    // 方向是漏判不是误判。
    foreach (var nm in catchDecl) {
      globals.Add(nm);
      for (int k = 0; k < fns.Count; k++) fns[k].decl.Add(nm);
    }
    r.declaredCount = globals.Count;

    // ── 3) 逐个「用到」判定 ──
    var used = new Dictionary<string,int>();
    for (int i = 0; i < n; i++) {
      FvTok t = T[i];
      if (t.kind != 0) continue;
      if (KEYWORDS.Contains(t.t)) continue;
      if (GLOBALS.Contains(t.t)) continue;                           // 浏览器/三方内置
      FvTok p = t.prev, nx = t.next;
      if (p != null && (p.t == "." || p.t == "?.")) continue;      // 属性访问
      if (nx != null && nx.kind == 1 && nx.t == ":") continue;     // 对象字面量的键 / 三元标签
      if (skip.Contains(t.t)) continue;                            // class 方法名
      if (declAtContains(declAt, i)) continue;                     // 它自己就是声明
      if (t.next != null && t.next.kind == 1 && t.next.t == "=>") continue;  // 箭头形参
      bool inParamList = InAnyParamList(fns, i);
      if (inParamList) continue;                                   // 形参位置 = 声明
      // 某层的形参表里出现过 → 是声明
      bool isParam = false;
      for (int k = 0; k < fns.Count; k++) {
        if (fns[k].ps <= i && i <= fns[k].pe && i > fns[k].ps && i < fns[k].pe) { isParam = true; break; }
      }
      if (isParam) continue;

      if (!used.ContainsKey(t.t)) used[t.t] = t.line;
      r.usedCount++;

      if (globals.Contains(t.t)) continue;
      bool ok = false;
      for (int k = 0; k < fns.Count; k++) {
        if (i < fns[k].bs || i > fns[k].be) continue;
        if (fns[k].decl.Contains(t.t)) { ok = true; break; }
      }
      if (!ok) {
        // 外层链上任意一层有出处就算数
        for (int k = 0; k < fns.Count && !ok; k++) {
          if (i < fns[k].bs || i > fns[k].be) continue;
          if (fns[k].decl.Contains(t.t)) ok = true;
        }
      }
      if (!ok) r.report.Add(t.t + "  第 " + t.line + " 行（外层链上也没有它的声明）");
    }

    if (r.dump.Count < 4000) {
      for (int k = 0; k < n && r.dump.Count < 3000; k++) {
        FvTok t2 = T[k];
        r.dump.Add(k + " L" + t2.line + " k" + t2.kind + " '" + t2.t + "'"
          + (t2.prev != null ? " prev='" + t2.prev.t + "'" : "")
          + (t2.next != null ? " next='" + t2.next.t + "'" : ""));
      }
    }
    var names = new List<string>(used.Keys);
    names.Sort();
    return r;
  }

  static bool declAtContains(List<KeyValuePair<int,string>> d, int i) {
    for (int k = 0; k < d.Count; k++) if (d[k].Key == i) return true;
    return false;
  }
  static bool InAnyParamList(List<FvFn> fns, int i) {
    for (int k = 0; k < fns.Count; k++)
      if (fns[k].pe > fns[k].ps && i > fns[k].ps && i < fns[k].pe) return true;
    return false;
  }
  static void SkipMethodNames(List<FvTok> T, int b, int e, HashSet<string> skip) {
    for (int i = b + 1; i < e; i++) {
      if (T[i].kind != 0) continue;
      FvTok p = T[i].prev;
      if (p != null && (p.t == "." || p.t == "?.")) continue;
      FvTok nx = T[i].next;
      if (nx == null || nx.kind != 1 || nx.t != "(") continue;
      int c = Match(T, i, "(", ")");
      if (c < 0 || c + 1 >= T.Count) continue;
      if (T[c + 1].kind == 1 && T[c + 1].t == "{") skip.Add(T[i].t);
    }
  }

  static int ExprEnd(List<FvTok> T, int start) {
    int d = 0;
    for (int i = start; i < T.Count; i++) {
      FvTok t = T[i];
      if (t.kind != 1) continue;
      if (t.t == "(" || t.t == "[" || t.t == "{") { d++; continue; }
      if (t.t == ")" || t.t == "]" || t.t == "}") { if (d == 0) return i; d--; continue; }
      if (d == 0 && (t.t == ";" || t.t == ",")) return i;
    }
    return T.Count - 1;
  }

  static int FindSymbol(List<FvTok> T, int from, string sym) {
    for (int i = from; i < T.Count; i++) if (T[i].kind == 1 && T[i].t == sym) return i;
    return -1;
  }
  static int Match(List<FvTok> T, int open, string o, string c) {
    int d = 0;
    for (int i = open; i < T.Count; i++) {
      if (T[i].kind != 1) continue;
      if (T[i].t == o) d++;
      else if (T[i].t == c) { d--; if (d == 0) return i; }
    }
    return -1;
  }
  static int FindOpen(List<FvTok> T, int close) {
    int d = 0;
    for (int i = close; i >= 0; i--) {
      if (T[i].kind != 1) continue;
      if (T[i].t == ")") d++;
      else if (T[i].t == "(") { d--; if (d == 0) return i; }
    }
    return -1;
  }

  // 括号组里的一层标识符（形参 / 解构模式）
  static void ParamNames(List<FvTok> T, int open, int close, HashSet<string> into) {
    for (int i = open + 1; i < close; i++) {
      FvTok t = T[i];
      if (t.kind == 1) {
        if (t.t == "{" || t.t == "[") { int e = Match2(T, i); if (e > 0) { ParamNames(T, i, e, into); i = e; } continue; }
        if (t.t == "=") { i = SkipInitializer(T, i) - 1; continue; }
        continue;
      }
      FvTok p = t.prev;
      if (p != null && (p.t == "." || p.t == "?.")) continue;
      if (KEYWORDS.Contains(t.t)) continue;
      into.Add(t.t);
    }
  }
  static int Match2(List<FvTok> T, int open) {
    string o = T[open].t;
    string c = (o == "{") ? "}" : "]";
    int d = 0;
    for (int i = open; i < T.Count; i++) {
      if (T[i].kind != 1) continue;
      if (T[i].t == o) d++;
      else if (T[i].t == c) { d--; if (d == 0) return i; }
    }
    return -1;
  }
  static int SkipInitializer(List<FvTok> T, int eq) {
    int d = 0;
    for (int i = eq + 1; i < T.Count; i++) {
      FvTok t = T[i];
      if (t.kind != 1) continue;
      if (t.t == "(" || t.t == "[" || t.t == "{") d++;
      else if (t.t == ")" || t.t == "]" || t.t == "}") { d--; if (d < 0) return i; }
      else if (d == 0 && t.t == ",") return i + 1;
      else if (d == 0 && (t.t == ";" || t.t == "}")) return i;
    }
    return T.Count;
  }

  // var a = 1, b = 2；const {x, y: z} = o；let [p, , q] = arr
  static void Declarators(List<FvTok> T, int j, List<KeyValuePair<int,string>> into) {
    while (j < T.Count) {
      if (T[j].kind == 1 && (T[j].t == "{" || T[j].t == "[")) {
        int e = Match2(T, j);
        if (e < 0) return;
        var tmp = new HashSet<string>();
        ParamNames(T, j, e, tmp);
        foreach (var nm in tmp) into.Add(new KeyValuePair<int,string>(j, nm));
        j = e + 1;
      }
      if (j >= T.Count || T[j].kind != 0) return;
      into.Add(new KeyValuePair<int,string>(j, T[j].t));
      FvTok nx = (j + 1 < T.Count) ? T[j + 1] : null;
      if (nx == null) return;
      if (nx.kind == 1 && nx.t == "=") { j = SkipInitializer(T, j + 1); continue; }
      if (nx.kind == 1 && nx.t == ",") { j = j + 2; continue; }
      return;
    }
  }

  static List<FvTok> Tokenize(string js) {
    var L = new List<FvTok>();
    int line = 1;
    int st = 0;                       // 0 code 1 sq 2 dq 3 tpl 4 line 5 block 6 regex
    var stk = new Stack<int>();
    char prevSig = '\0';
    for (int i = 0; i < js.Length; i++) {
      char c = js[i];
      char n = (i + 1 < js.Length) ? js[i + 1] : '\0';
      if (c == '\n') line++;
      FvTok tk = null;
      switch (st) {
        case 0:
          if (c == '\'') { st = 1; prevSig = '\0'; }
          else if (c == '"') { st = 2; prevSig = '\0'; }
          else if (c == '`') { st = 3; prevSig = '\0'; }
          else if (c == '/' && n == '*') { st = 5; i++; }
          else if (c == '/' && n == '/') { st = 4; i++; }
          else if (c == '/' && IsRegexLead(prevSig)) { st = 6; prevSig = '\0'; }
          else if (char.IsLetter(c) || c == '_' || c == '$') {
            int a = i;
            while (i + 1 < js.Length && (char.IsLetterOrDigit(js[i + 1]) || js[i + 1] == '_' || js[i + 1] == '$')) i++;
            tk = new FvTok { kind = 0, t = js.Substring(a, i - a + 1), line = line };
            prevSig = 'a';
          }
          else if (char.IsDigit(c)) {
            int a = i;
            while (i + 1 < js.Length && (char.IsLetterOrDigit(js[i + 1]) || js[i + 1] == '.')) i++;
            tk = new FvTok { kind = 2, t = js.Substring(a, i - a + 1), line = line };
            prevSig = '0';
          }
          else if (char.IsWhiteSpace(c)) { /* 空白**不能**发成 token */ }
          else {
            string p = c.ToString();
            // `=>` 必须合成一个 token：分成 `=` 和 `>` 的话
            // 「`)` 后面跟着 `=>`」这个箭头形参判据永远不成立。
            if (c == '=' && n == '>') { p = "=>"; i++; }
            else if (c == '.' && n == '.') {
              if (i + 2 < js.Length && js[i + 2] == '.') { p = "..."; i += 2; }
              else if (i + 2 < js.Length && js[i + 2] == '?') { p = "?."; i += 2; }
            }
            tk = new FvTok { kind = 1, t = p, line = line };
            prevSig = c;
          }
          break;
        case 4: if (c == '\n') { st = 0; prevSig = '\0'; } break;
        case 5: if (c == '*' && n == '/') { st = 0; i++; prevSig = '\0'; } break;
        case 1: if (c == '\\') i++; else if (c == '\'') { st = 0; prevSig = '\0'; } break;
        case 2: if (c == '\\') i++; else if (c == '"') { st = 0; prevSig = '\0'; } break;
        case 6: if (c == '\\') i++; else if (c == '/') { st = 0; prevSig = '\0'; } break;
        case 3:
          if (c == '\\') i++;
          else if (c == '`') { st = 0; prevSig = '\0'; }
          else if (c == '$' && n == '{') {
            stk.Push(3);
            tk = new FvTok { kind = 1, t = "{", line = line };
            st = 0; prevSig = '{'; i++;
          }
          break;
      }
      if (tk != null) {
        tk.prev = (L.Count > 0) ? L[L.Count - 1] : null;
        if (L.Count > 0) L[L.Count - 1].next = tk;
        L.Add(tk);
      }
      if (stk.Count > 0 && c == '}' && st == 0) st = stk.Pop();
    }
    return L;
  }

  static bool IsRegexLead(char c) {
    return c == '(' || c == '[' || c == '{' || c == ',' || c == ';' || c == '='
        || c == ':' || c == '!' || c == '&' || c == '|' || c == '?' || c == '\0'
        || c == '+' || c == '-' || c == '*' || c == '%' || c == '~' || c == '^' || c == '>';
  }
}
'@
}

$html = [IO.File]::ReadAllText($Path)
# ⚠️ 这个文件有**两个** <script>：第一个是 `/*__THREE__*/` 占位（构建时才被替换成
#    11 MB 的 three.js），第二个才是 app。贪婪的 `(?s)<script>(.*)</script>`
#    会从第一个开到最后一个、把中间的 `</script><script>` 也吞进来 ——
#    冒出一个叫 `script` 的假变量。取**最后一个** script 块。
$all = [regex]::Matches($html, '(?s)<script[^>]*>(.*?)</script>')
if ($all.Count -eq 0) { throw "$Path : no <script> block" }
$res = [JsFreeVar]::Scan($all[$all.Count - 1].Groups[1].Value)

if ($Dump -gt 0) {
  $res.dump | Select-Object -First $Dump | ForEach-Object { Write-Output ("  tok {0}" -f $_) }
  Write-Output ("  -- used {0}  globals {1}  fns {2}  report {3}" -f `
    $res.usedCount, $res.declaredCount, $res.fnCount, $res.report.Count)
  exit 0
}

if ($res.report.Count -eq 0) {
  if (-not $Quiet) {
    Write-Output ("  freevar {0,-24} PASS（{1} 个标识符引用、{2} 个全局声明、{3} 个函数，全有出处）" -f `
      (Split-Path $Path -Leaf), $res.usedCount, $res.declaredCount, $res.fnCount)
  }
  exit 0
}
Write-Output ("  FAIL  {0}：{1} 个标识符用到了但在本作用域链上没声明过" -f (Split-Path $Path -Leaf), $res.report.Count)
$res.report | Select-Object -First 40 | ForEach-Object { Write-Output ("        {0}" -f $_) }
if ($res.report.Count -gt 40) { Write-Output ("        …… 还有 {0} 条" -f ($res.report.Count - 40)) }
exit 1
