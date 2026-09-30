# harness 静态体检：切出来的页面**能不能跑**，在生成时就查。
#
# 为什么非得有这个：生成器只保证「代码切出来了」，不保证「切出来的东西
# 自洽」。2026-09-30 连续踩了两次：
#   1) _mktraffic 撞上一个同名注释，切走的是 cruiseTick 的车流循环，
#      真正的碰撞段没进去 —— harness 照样生成、括号差 4 也没人拦。
#   2) _mkdrive 切了 frame() 的驾驶块，里面有 cruiseTick(dt)，
#      而 cruiseTick 定义在块外 —— 页面一打开就 ReferenceError，
#      整页 58 条断言一条没跑，生成器却报「PASS」。
# 这两次的共同点：**输出看起来是正常的**。所以检查不能靠人眼，
# 得在生成这一步就挡。
#
# 查法：把 harness 的 script 掏出来，收集所有「被调用」的标识符，
# 减去「在本文件里声明过的」和「JS 自带的」，剩下的就是悬空引用。
# 声明集合是**全文件并集**（不分作用域），所以只会漏报不会误报。
param([Parameter(Mandatory=$true)][string]$Path)

$ErrorActionPreference = 'Stop'
$t = [IO.File]::ReadAllText($Path)
$m = [regex]::Match($t, '(?s)<script>(.*)</script>')
if (-not $m.Success) { throw "$Path : no <script> block found" }
$js = $m.Groups[1].Value
# 剥注释和字符串，免得注释里写的名字被当成调用
$js = [regex]::Replace($js, '(?s)/\*.*?\*/', '')
$js = [regex]::Replace($js, '(?m)//.*$', '')
$js = [regex]::Replace($js, '(?s)`(\\.|[^`\\])*`', '``')
$js = [regex]::Replace($js, "'(\\.|[^'\\])*'", "''")
$js = [regex]::Replace($js, '"(\\.|[^"\\])*"', '""')

# 本文件里声明过的名字
$decl = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($mm in [regex]::Matches($js, '(?m)\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)')) { [void]$decl.Add($mm.Groups[1].Value) }
# 同一条声明里的**后续**声明符：`const lin = …, sat = …`
# 只认第一个的话 sat() 会被报成悬空调用（2026-09-30 在反查里踩到过）。
# 这一条只收「等号左边是个裸标识符」的部分，不去解析解构。
foreach ($mm in [regex]::Matches($js, '(?m)^\s*(?:const|let|var)\s+([^;\n]+)')) {
  foreach ($part in ($mm.Groups[1].Value -split ',')) {
    $n = ($part -split '=')[0].Trim()
    if ($n -match '^[A-Za-z_$][\w$]*$') { [void]$decl.Add($n) }
  }
}
foreach ($mm in [regex]::Matches($js, '(?m)\bfunction\s+([A-Za-z_$][\w$]*)')) { [void]$decl.Add($mm.Groups[1].Value) }
foreach ($mm in [regex]::Matches($js, '\(([^()]*)\)')) {
  foreach ($p in ($mm.Groups[1].Value -split ',')) {
    $n = ($p -split '=')[0].Trim() -replace '^\.\.\.',''
    if ($n -match '^[A-Za-z_$][\w$]*$') { [void]$decl.Add($n) }
  }
}
# 箭头函数的**裸**参数：`s => s.vig.every(f => VIGNETTES.includes(f()))`
# 上一条的正则只认带括号的参数表，f 这种就漏了，于是 f() 被当成悬空调用。
foreach ($mm in [regex]::Matches($js, '(?<![.\w$])([A-Za-z_$][\w$]*)\s*=>')) { [void]$decl.Add($mm.Groups[1].Value) }

# JS 自带 / 语言关键字
$builtin = @('if','for','while','switch','catch','return','typeof','function','Math','JSON','Object',
  'Array','String','Number','Boolean','Date','Map','Set','WeakMap','Promise','parseInt','parseFloat','isNaN',
  'isFinite','encodeURIComponent','decodeURIComponent','Error','RegExp','console','window','document',
  'Intl','Symbol','BigInt','void','new','delete','do','else','try','throw','await','async','of','in',
  'this','super','case','break','continue','default','instanceof','yield','class','extends','import',
  'export','null','true','false','undefined','arguments','eval','Infinity','NaN',
  'Float32Array','Float64Array','Uint8Array','Uint16Array','Uint32Array','Int8Array','Int16Array',
  'Int32Array','ArrayBuffer','DataView','WeakSet','Proxy','Reflect','Atomics','SharedArrayBuffer')
foreach ($b in $builtin) { [void]$decl.Add($b) }

# 被调用的名字（排除 a.b( 这种方法调用，以及对象字面量里的方法**定义**）
$called = @{}
foreach ($mm in [regex]::Matches($js, '(?<![.\w$])([A-Za-z_$][\w$]*)\s*\(')) {
  $n = $mm.Groups[1].Value
  if ($decl.Contains($n)) { continue }
  # 找到配对的 ')'，看后面紧跟的是不是 '{' —— 是的话这是方法定义
  # （`set innerHTML(v){}` / `add(){}` / `toggle(cls,on){}` / `getHex(){}`），
  # 不是调用。少这一步 mood/route/cruise 三个 harness 全是误报。
  $i = $mm.Index + $mm.Length - 1
  $d = 0; $tail = ''
  for (; $i -lt $js.Length; $i++){
    if ($js[$i] -eq '(') { $d++ }
    elseif ($js[$i] -eq ')') { $d--; if ($d -eq 0) { break } }
  }
  if ($i -lt $js.Length) {
    $rest = $js.Substring($i + 1)
    if ($rest -match '^\s*\{') { continue }
    if ($rest -match '^\s*=>') { continue }
  }
  if (-not $called.ContainsKey($n)) { $called[$n] = 0 }
  $called[$n]++
}
$name = Split-Path $Path -Leaf
if ($called.Count -eq 0) {
  Write-Output ("  harness lint  {0,-22} PASS（没有悬空调用）" -f $name)
  return
}
foreach ($n in @($called.Keys | Sort-Object)) { Write-Output ("  {0}  悬空调用 {1}() x{2}" -f 'FAIL', $n, $called[$n]) }
throw ("harness lint failed on {0}: {1} 个未声明的调用" -f $name, $called.Count)
