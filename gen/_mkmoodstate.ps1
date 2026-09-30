$ErrorActionPreference = 'Stop'
# 鹧鸪状态的回归。moodTick 设计成**只碰 S / MOOD / RIDERS** 的纯函数，
# 就是为了能这么切出来用数值验 —— 它是这一节唯一能验的部分。
# 姿态（rig 那几行）验不了，只能靠看，所以这里把能验的全验掉。
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
$dir = $ROOT
$lines = [IO.File]::ReadAllLines(($APP))

function Find([string]$pat, [int]$from = 0) {
  for ($i = $from; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pat) { return $i } }
  return -1
}
function BlockEnd([int]$open) {
  $d = 0
  for ($i = $open; $i -lt $lines.Count; $i++) {
    $d += ([regex]::Matches($lines[$i],'\{')).Count - ([regex]::Matches($lines[$i],'\}')).Count
    if ($d -eq 0) { return $i }
  }
  return -1
}
$script:CUTS = @()
function GrabBlock([string]$pat) {
  $a = Find $pat
  if ($a -lt 0) { throw "not found: $pat" }
  $b = BlockEnd $a
  $script:CUTS += ('  {0,-30} lines {1}..{2}' -f $pat, ($a+1), ($b+1))
  return ($lines[$a..$b] -join "`n")
}

$a = Find '^const approach = '
if ($a -lt 0) { throw 'approach not found' }
$approach = $lines[$a]
$script:CUTS += ('  {0,-30} line {1}' -f 'approach', ($a+1))
$mood = GrabBlock '^function moodTick\(dt\)\{'
$script:CUTS | Write-Output

$tpl = [IO.File]::ReadAllText(($TPL_MOODSTATE))
$tpl = $tpl.Replace('/*__APPROACH__*/', $approach)
$tpl = $tpl.Replace('/*__MOODTICK__*/', "`n" + $mood + "`n")
[IO.File]::WriteAllText(($OUT_MOODSTATE), $tpl, (New-Object Text.UTF8Encoding($false)))
"harness bytes: {0:N0}" -f (Get-Item ($OUT_MOODSTATE)).Length

# ---- 语法体检 ----
$t = [IO.File]::ReadAllText(($OUT_MOODSTATE))
$js = [regex]::Match($t, '(?s)<script>(.*)</script>').Groups[1].Value
$js = [regex]::Replace($js, '(?s)/\*.*?\*/', { param($m) ($m.Value -replace '[^\r\n]','') })
$d = 0; $p = 0
foreach ($line in ($js -split "`r`n|`n")) {
  $x = [regex]::Replace($line, "'(\\.|[^'\\])*'", "''")
  $x = [regex]::Replace($x, '"(\\.|[^"\\])*"', '""')
  $x = [regex]::Replace($x, '//.*$', '')
  $d += ([regex]::Matches($x,'\{')).Count - ([regex]::Matches($x,'\}')).Count
  $p += ([regex]::Matches($x,'\(')).Count - ([regex]::Matches($x,'\)')).Count
}
"brace balance: $d   paren balance: $p"
if ($d -ne 0) { throw "brace imbalance in harness" }
if ($p -ne 0) { throw "paren imbalance in harness" }

& powershell -NoProfile -ExecutionPolicy Bypass -File ($S_LINT) -Path ($OUT_MOODSTATE)
# ⚠️ 这句 `exit` 千万不能少 —— 见 _mkdrive.ps1 末尾的说明。
exit $LASTEXITCODE