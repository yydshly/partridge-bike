$ErrorActionPreference = 'Stop'
# 诊断页生成器：切法和 _mkcruise.ps1 完全一样（同一套 cruiseTick，
# 换一张模板）。刻意不合并成一个脚本 —— 诊断页是可以随时改坏的，
# 断言页不能。
$dir = 'E:\minimax_code_project\0929_project\partridge-bike'
$lines = [IO.File]::ReadAllLines((Join-Path $dir '_app3d.html'))

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

$a = Find '^const LANE_HALF = ROAD_W/4;'
if ($a -lt 0) { throw 'LANE_HALF not found' }
$b = $a
while ($b -lt $lines.Count -and $lines[$b] -notmatch 'KD_YAW') { $b++ }
if ($b -ge $lines.Count) { throw 'KD_YAW not found after LANE_HALF' }
$script:CUTS += ('  {0,-30} lines {1}..{2}' -f 'cruise consts', ($a+1), ($b+1))
$src = @()
$src += ($lines[$a..$b] -join "`n")
$src += GrabBlock '^function cruiseTick\(dt\)\{'
$src += $lines[(Find 'S\.steerIn = S\.cruise \? cruiseTick\(dt\)')]
$script:CUTS | Write-Output

$tpl = [IO.File]::ReadAllText((Join-Path $dir '_cruisediag.tpl.html'))
$tpl = $tpl.Replace('/*__CRUISE__*/', "`n" + ($src -join "`n") + "`n")
[IO.File]::WriteAllText((Join-Path $dir '_cruisediag.html'), $tpl, (New-Object Text.UTF8Encoding($false)))
"diag bytes: {0:N0}" -f (Get-Item (Join-Path $dir '_cruisediag.html')).Length
