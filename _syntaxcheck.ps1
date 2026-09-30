# 源码语法体检：注释和字符串有没有配平。
#
# 为什么非得有这个：2026-09-30 交付前抓到一次 —— 自动巡航那段说明的
# 块注释在 ① 小节末尾就写了 `*/`，② 小节整段裸露在代码里，又跟了
# 第二个 `*/`。**整份 app 是一个 SyntaxError，双击就白屏。**
# 而当时所有检查全绿：括号配平是 0（裸露那段里恰好没有花括号）、
# 作用域体检过、harness 全过、构建「成功」。因为配平检查在
# 「代码已经是合法 JS」这个前提下才有意义，语法坏了它就失效。
#
# 这里查的就是那个前提：把 JS 走一遍状态机（普通/单引号/双引号/
# 模板/行注释/块注释/正则），报出这几种错：
#   - 多出来的 `*/`（没有对应开头的）
#   - 走到文件尾还没闭合的块注释 / 字符串 / 模板
#   - 正则字面量没闭合
# 不是完整的 JS 解析器（不查语法树），但「括号配平」查不到的
# 恰恰是这一类，它能兜住。
#
# ⚠️ 扫描器用 Add-Type 编译成 C# 再跑。纯 PowerShell 逐字符循环扫
#    11.7 MB 的成品要好几分钟 —— 一道每次都要跑的检查不能这么慢。
param(
  [Parameter(Mandatory=$true)][string]$Path,
  [switch]$Quiet
)
$ErrorActionPreference = 'Stop'

if (-not ('JsLex' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Text;

public class JsLex {
  // 返回错误描述；空列表 = 注释/字符串都配平
  public static List<string> Scan(string js) {
    var errs = new List<string>();
    // 状态：0 code 1 sq 2 dq 3 tpl 4 line 5 block 6 regex
    int st = 0, blkStart = 0, strStart = 0;
    char prevSig = '\0';
    for (int i = 0; i < js.Length; i++) {
      char c = js[i];
      char n = (i + 1 < js.Length) ? js[i + 1] : '\0';
      switch (st) {
        case 0:
          if (c == '\'')      { st = 1; strStart = i; }
          else if (c == '"')  { st = 2; strStart = i; }
          else if (c == '`')  { st = 3; strStart = i; }
          else if (c == '/' && n == '*') { st = 5; blkStart = i; i++; }
          else if (c == '/' && n == '/') { st = 4; i++; }
          else if (c == '/' && IsRegexLead(prevSig)) { st = 6; }
          // ★ 关键的一条：在**代码**状态下撞见 `*/`，说明前面那段注释
          //   被提前关掉了，后面的说明文字整段裸露在代码里 —— 那就是
          //   2026-09-30 白屏的那次。由状态机报，而不是事后拿正则数
          //   `/*` 和 `*/` 的个数：后者分不清字符串里的 `/*`
          //   （three.js 里到处都是），在 11.7 MB 的成品上会误报。
          else if (c == '*' && n == '/') {
            errs.Add("第 " + Line(js, i) + " 行有个没有对应开头的 */（前面那段块注释被提前闭合了）: "
                     + Snippet(js, i));
            i++; prevSig = '\0';
          }
          else if (!char.IsWhiteSpace(c)) { prevSig = c; }
          break;
        case 4: if (c == '\n') { st = 0; prevSig = '\0'; } break;
        case 5: if (c == '*' && n == '/') { st = 0; i++; prevSig = '\0'; } break;
        case 1: if (c == '\\') i++; else if (c == '\'') { st = 0; prevSig = '\0'; } break;
        case 2: if (c == '\\') i++; else if (c == '"')  { st = 0; prevSig = '\0'; } break;
        case 6: if (c == '\\') i++; else if (c == '/')  { st = 0; prevSig = '\0'; } break;
        case 3: // 模板：只管转义和收尾，${ } 内部当普通文本（里面再出错的概率极低）
                 if (c == '\\') i++; else if (c == '`') { st = 0; prevSig = '\0'; } break;
      }
    }
    if (st == 5) errs.Add("块注释没闭合：第 " + Line(js, blkStart) + " 行开的 /* 一直到文件尾");
    else if (st == 1 || st == 2 || st == 3) {
      string[] names = { "普通", "单引号字符串", "双引号字符串", "模板字符串", "行注释", "块注释", "正则" };
      errs.Add(names[st] + "没闭合：第 " + Line(js, strStart) + " 行");
    }
    else if (st == 6) errs.Add("正则没闭合：从文件头扫到尾都没关上");
    return errs;
  }
  // 「/ 是正则还是除法」只取保守集。判据放宽到 + - * % ~ ^ <> 之后，
  // 那个**坏样本**里的 `*/`（* 后面跟 /）被当成正则开头，
  // 凭空多报一条「正则没闭合」。宁可漏判正则，也不误伤。
  static bool IsRegexLead(char c) {
    return c == '(' || c == '[' || c == '{' || c == ',' || c == ';' || c == '='
        || c == ':' || c == '!' || c == '&' || c == '|' || c == '?' || c == '\0';
  }
  static string Line(string s, int off) {
    int n = 1;
    for (int i = 0; i < off && i < s.Length; i++) if (s[i] == '\n') n++;
    return n.ToString();
  }
  static string Snippet(string s, int off) {
    int a = Math.Max(0, off - 70);
    int l = Math.Min(170, s.Length - a);
    return s.Substring(a, l).Replace('\n', ' ').Replace('\r', ' ');
  }
}
'@
}

$html = [IO.File]::ReadAllText($Path)
$ms = [regex]::Match($html, '(?s)<script>(.*)</script>')
if (-not $ms.Success) { throw "$Path : no <script> block" }
$errs = [JsLex]::Scan($ms.Groups[1].Value)

if ($errs.Count -eq 0) {
  if (-not $Quiet) { Write-Output ("  syntax  {0,-24} PASS（注释/字符串都配平）" -f (Split-Path $Path -Leaf)) }
  exit 0
}
foreach ($e in $errs) { Write-Output ("  {0}  {1}" -f 'FAIL', $e) }
exit 1
