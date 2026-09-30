$ErrorActionPreference = 'Stop'
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
$dir = $ROOT
$lines = [IO.File]::ReadAllLines(($APP))

function Find([string]$pat, [int]$from = 0) {
  for ($i = $from; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pat) { return $i } }
  return -1
}
# 从 $open 那一行开始走花括号，返回配平的那一行
function BlockEnd([int]$open) {
  $d = 0
  for ($i = $open; $i -lt $lines.Count; $i++) {
    $d += ([regex]::Matches($lines[$i],'\{')).Count - ([regex]::Matches($lines[$i],'\}')).Count
    if ($d -eq 0) { return $i }
  }
  return -1
}
function Dedent($b) { $b | ForEach-Object { if ($_.Length -ge 4) { $_.Substring(4) } else { '' } } }

# ---- 1. ROUTE 表 ----
$a = Find '^const ROUTE = \['
if ($a -lt 0) { throw "ROUTE not found" }
$b = -1
for ($i = $a; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\];') { $b = $i; break } }
if ($b -lt 0) { throw "ROUTE end not found" }
$route = ($lines[$a..$b] -join "`n")
"route  : lines $($a+1)..$($b+1)"

# ---- 2. ROUTE_LEN + segAt + routeName ----
$a = Find '^let ROUTE_LEN = 0;'
$b = Find '^function routeName\(km\)' $a
if ($a -lt 0 -or $b -lt 0) { throw "segAt block not found" }
$seg = ($lines[$a..$b] -join "`n")
"segAt  : lines $($a+1)..$($b+1)"

# ---- 3. applyRoute ----
$a = Find '^function applyRoute\(i\)\{'
if ($a -lt 0) { throw "applyRoute not found" }
$b = BlockEnd $a
$apply = ($lines[$a..$b] -join "`n")
"apply  : lines $($a+1)..$($b+1)"

# ---- 4. frame() 里的路段切换块 ----
$a = Find 'const seg = segAt\(S\.km\);'
if ($a -lt 0) { throw "frame seg block not found" }
$b = BlockEnd ($a + 1)          # 从 if (seg !== S.seg){ 那一行开始走
$tick = (Dedent $lines[$a..$b]) -join "`n"
"frame  : lines $($a+1)..$($b+1)"

$tpl = [IO.File]::ReadAllText(($TPL_ROUTE))
$tpl = $tpl.Replace('/*__ROUTE__*/',
  "`n" + $route + "`n`n" + $seg + "`n`n" + $apply + "`n`nfunction routeTick(dt){" + $tick + "`n}`n")
[IO.File]::WriteAllText(($OUT_ROUTE), $tpl, (New-Object Text.UTF8Encoding($false)))
"harness bytes: {0:N0}" -f (Get-Item ($OUT_ROUTE)).Length

# ---- 语法体检：括号配平（// 必须按行剥，否则注释里的括号会污染统计）----
$t = [IO.File]::ReadAllText(($OUT_ROUTE))
$js = [regex]::Match($t, '(?s)<script>(.*)</script>').Groups[1].Value
$d = 0; $min = 0
foreach ($line in ($js -split "`r`n|`n")) {
  $x = [regex]::Replace($line, "'(\\.|[^'\\])*'", "''")
  $x = [regex]::Replace($x, '"(\\.|[^"\\])*"', '""')
  $x = [regex]::Replace($x, '/\*.*?\*/', '')
  $x = [regex]::Replace($x, '//.*$', '')
  $d += ([regex]::Matches($x,'\{')).Count - ([regex]::Matches($x,'\}')).Count
  if ($d -lt $min) { $min = $d }
}
"brace balance: $d (min $min)"
if ($d -ne 0) { throw "brace imbalance in harness" }
& powershell -NoProfile -ExecutionPolicy Bypass -File ($S_LINT) -Path ($OUT_ROUTE)
# ⚠️ 这句 `exit` 千万不能少 —— 见 _mkdrive.ps1 末尾的说明。
exit $LASTEXITCODE