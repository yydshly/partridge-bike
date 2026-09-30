$ErrorActionPreference = 'Stop'
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
$d = $ROOT
# ⚠️ 这里原来叫 $p —— 和上面「往上找 _paths.ps1」的 $p 是两个完全不同的东西，
#    同一个变量名在 5 行之内换了含义。改名叫 $tool。
$tool = $S_SCOPE
$t = [IO.File]::ReadAllText($tool, (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($tool, $t, (New-Object Text.UTF8Encoding($true)))
cd $d

Write-Output '=== 1) 现在的源码（应该 PASS）==='
# ⚠️ 原来写的是 `-File .\_scopecheck.ps1` —— **相对当前工作目录**的路径。
#    本脚本自己会 cd，所以在这儿看不出问题；但那是路径的第二个出处，
#    换个 CWD 跑就找不到文件，而 B 阶段把脚本搬进 checks\ 之后更是直接失效。
#    路径只能来自 _paths.ps1。
powershell -NoProfile -ExecutionPolicy Bypass -File $tool
"exit=$LASTEXITCODE"

Write-Output ''
Write-Output '=== 2) 反向验证：把 hitQuip 塞回 rotateCaption 体内的坏副本（应该 FAIL）==='
$src = [IO.File]::ReadAllText(($APP))
$nl = if ($src.Contains("`r`n")) { "`r`n" } else { "`n" }

# 精确重建原来的 bug 形状：rotateCaption 先开一个口，hitQuip 声明在它体内
$a = 'function hitQuip(side){'
if ($src.IndexOf($a) -lt 0) { throw 'anchor A not found' }
$mut = $src.Replace($a, 'function rotateCaption(){' + $nl + $a)

$b = '}' + $nl + $nl + 'function rotateCaption(){'
if ($mut.IndexOf($b) -lt 0) { throw 'anchor B not found' }
$mut = $mut.Replace($b, '}' + $nl + $nl + '}' + $nl + $nl + 'function rotateCaption(){')

$tmp = Join-Path $d '_scopecheck_mutant.html'
[IO.File]::WriteAllText($tmp, $mut, (New-Object Text.UTF8Encoding($true)))
Select-String -LiteralPath $tmp -Pattern 'function rotateCaption\(|function hitQuip\(' -Encoding UTF8 |
  ForEach-Object { "   mutant 第 $($_.LineNumber) 行: $($_.Line.Trim())" }

powershell -NoProfile -ExecutionPolicy Bypass -File $tool $tmp frame
$rc = $LASTEXITCODE
Write-Output "exit=$rc"

# 造出来的坏副本用完就删，别在项目里留一份被改坏的源文件
if ($rc -eq 0) { throw "反向验证失败：坏副本竟然 PASS，检查器抓不到这个 bug" }
Write-Output "反向验证成立：检查器确实能抓到这个 bug（不是恒过）"
mavis-trash $tmp
exit 0