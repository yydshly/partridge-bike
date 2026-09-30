param([string]$File, [string]$Entry = 'frame')
$ErrorActionPreference = 'Stop'
# 作用域体检：入口函数调用的那些函数，有没有被关在别的函数体里（局部声明）。
#
# 背景：hitQuip 曾经被误插在 rotateCaption 的函数体里面，缩进是 0 所以肉眼看
# 不出来，但花括号深度是 2 —— 它只是 rotateCaption 的局部函数。于是 frame()
# 里的 hitQuip(side) 抛 ReferenceError：撞车时鹧鸪一句话都没有、控制台一条红字，
# 而且那一帧的后半段（lat 夹回、HUD、镜头、render、FRAMES++）全被跳过。
# rAF 在 frame() 开头就挂好了，所以循环不会停，只是每次撞车掉一帧。
#
# 这种 bug **任何运行时回归都抓不到**：harness 里 hitQuip 是桩，作用域是对的。
# 只能静态查。
#
# 基线：整个 app 都在主 IIFE 里，所以顶层函数的声明深度是 **1**，不是 0。
# 用法：_scopecheck.ps1            查 _app3d.html（入口 frame）
#      _scopecheck.ps1 <文件> <入口函数名>
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
$dir = $ROOT
if (-not $File) { $File = $APP }

$raw = [IO.File]::ReadAllText($File) -split "`r`n|`n"
# 先把字符串字面量和注释抹掉，免得里面的括号/花括号污染统计
$clean = foreach ($line in $raw) {
  $x = [regex]::Replace($line, "'(\\.|[^'\\])*'", "''")
  $x = [regex]::Replace($x, '"(\\.|[^"\\])*"', '""')
  $x = [regex]::Replace($x, '/\*.*?\*/', '')
  [regex]::Replace($x, '//.*$', '')
}

$depth = 0
$decl = @{}; $at = @{}
for ($i = 0; $i -lt $clean.Count; $i++) {
  foreach ($m in [regex]::Matches($clean[$i], '\bfunction\s+([A-Za-z_$][\w$]*)\s*\(')) {
    $n = $m.Groups[1].Value
    if (-not $decl.ContainsKey($n)) { $decl[$n] = $depth; $at[$n] = $i + 1 }
  }
  $depth += ([regex]::Matches($clean[$i],'\{')).Count - ([regex]::Matches($clean[$i],'\}')).Count
}

$s = -1
for ($i = 0; $i -lt $clean.Count; $i++) {
  if ($clean[$i] -match '^\s*function\s+' + [regex]::Escape($Entry) + '\s*\(') { $s = $i; break }
}
if ($s -lt 0) { throw "entry '$Entry' not found in $File" }
$d = 0; $e = -1
for ($i = $s; $i -lt $clean.Count; $i++) {
  $d += ([regex]::Matches($clean[$i],'\{')).Count - ([regex]::Matches($clean[$i],'\}')).Count
  if ($d -eq 0 -and $i -gt $s) { $e = $i; break }
}
if ($e -lt 0) { throw "entry '$Entry' end not found" }

$TOP = ($decl.Values | Measure-Object -Minimum).Minimum
$bad = @()
$hop = 0
for ($i = $s; $i -le $e; $i++) {
  foreach ($m in [regex]::Matches($clean[$i], '(?<![.\w$])([A-Za-z_$][\w$]*)\s*\(')) {
    $n = $m.Groups[1].Value
    if (-not $decl.ContainsKey($n)) { continue }
    $hop++
    if ($decl[$n] -ne $TOP) { $bad += [pscustomobject]@{Name=$n; Depth=$decl[$n]; At=$at[$n]} }
  }
}

"file    : $(Split-Path $File -Leaf)"
"entry   : $Entry  (第 $($s+1)..$($e+1) 行)"
"baseline: 顶层函数声明深度 = $TOP  (主 IIFE 里，所以不是 0)"
"scanned : 全文件 $($decl.Count) 个函数声明，入口体内命中 $hop 次调用"
if ($bad.Count -eq 0) {
  "PASS    入口调用的函数全部在顶层"
  exit 0
} else {
  "FAIL    $($bad.Count) 个函数被关在别的函数体里："
  $bad | Sort-Object Name -Unique | ForEach-Object {
    "          {0,-22} 深度 {1}（第 {2} 行）" -f $_.Name, $_.Depth, $_.At
  }
  exit 1
}