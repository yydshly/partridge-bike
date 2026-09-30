param()
# 验 _mkdrive.ps1 里那条「S.km 的累加在 if (S.running) 里面」不是恒过的。
# 判据本身是从 if (S.running){ 起到里程那行为止的花括号是否**还没配平**。
$ErrorActionPreference = 'Stop'
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')

function Test-Inside([string]$app) {
  $kmAt = $app.IndexOf('S.km += v*dt/1000;')
  if ($kmAt -lt 0) { return $false }
  $guardAt = $app.LastIndexOf('if (S.running){', $kmAt)
  if ($guardAt -lt 0) { return $false }
  $mid = $app.Substring($guardAt, $kmAt - $guardAt)
  $mid = [regex]::Replace($mid, '(?s)/\*.*?\*/', '')
  $mid = [regex]::Replace($mid, '(?m)//.*$', '')
  $op = ([regex]::Matches($mid,'\{')).Count
  $cl = ([regex]::Matches($mid,'\}')).Count
  return ($op -gt $cl)
}

$bad = @'
function frame(){
  const dt = 1;
  if (S.running){
    const v = S.speed / 3.6;
  }
  S.km += v*dt/1000;
}
'@
$good = @'
function frame(){
  const dt = 1;
  if (S.running){
    const v = S.speed / 3.6;
    S.km += v*dt/1000;
  }
}
'@
$noLine = @'
function frame(){
  const dt = 1;
  if (S.running){
    const v = S.speed / 3.6;
  }
}
'@
# 注释里的花括号不能算进去（产品注释里就有 `const M = {`）
$comment = @'
function frame(){
  const dt = 1;
  /* 表里有 const M = { a:1 } 这种花括号 */
  if (S.running){
    const v = S.speed / 3.6;
    S.km += v*dt/1000;
  }
}
'@

$cases = @(
  @{ n = '坏样本：里程那行落在 if (S.running) 外面'; s = $bad;    want = $false }
  @{ n = '好样本：里程那行在 if (S.running) 里面';   s = $good;   want = $true  }
  @{ n = '好样本：注释里的花括号不算';             s = $comment;want = $true  }
  @{ n = '坏样本：整行不见了（切空/改名）';        s = $noLine; want = $false }
)
$fail = 0
foreach ($c in $cases) {
  $got = Test-Inside $c.s
  $ok = ($got -eq $c.want)
  if (-not $ok) { $fail++ }
  Write-Output ("  {0}  {1}  (判据给出 {2}，期望 {3})" -f $(if($ok){'PASS'}else{'FAIL'}), $c.n, $got, $c.want)
}
if ($fail -gt 0) { Write-Output "接线判据反查失败 $fail 条"; exit 1 }
Write-Output '接线判据反查成立：能分辨「在 if 里面 / 在外面 / 整行没了」'
exit 0