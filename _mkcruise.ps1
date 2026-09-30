$ErrorActionPreference = 'Stop'
# 自动巡航的舵：切 cruiseTick + 车道常数 + frame() 里接舵的那一行。
# 这一节为什么必须有数值回归：打方向的**符号**错了，画面上只表现为
# 「车在路中间画圈」或者「一开巡航就冲下路肩」—— 看截图分不出是
# 「控制器极性反了」还是「增益不对」，反了以后有时看着还挺顺眼。
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
# 切出来的行号信息**不能**用 Write-Output 报（函数里 Write-Output 的东西
# 会和返回值一起进输出流，「lines 1234」这行字符串会被当成源码塞进 harness）
$script:CUTS = @()
function GrabLines([string]$pat, [int]$count) {
  $a = Find $pat
  if ($a -lt 0) { throw "not found: $pat" }
  $b = $a + $count - 1
  $script:CUTS += ('  {0,-30} line {1}' -f $pat, ($a+1))
  return ($lines[$a..$b] -join "`n")
}
function GrabBlock([string]$pat) {
  $a = Find $pat
  if ($a -lt 0) { throw "not found: $pat" }
  $b = BlockEnd $a
  $script:CUTS += ('  {0,-30} lines {1}..{2}' -f $pat, ($a+1), ($b+1))
  return ($lines[$a..$b] -join "`n")
}

# 车道/增益那几个 const 是一整组，但顺序会变（加一个 AVOID_HIT 就多一行），
# 所以**扫到 KD_YAW 那一行为止**，不要写死「四行/五行」——
# 写死的话下次加一个常数，这儿会静默少切一个，harness 里报 ReferenceError。
$a = Find '^const LANE_HALF = ROAD_W/4;'
if ($a -lt 0) { throw 'LANE_HALF not found' }
$b = $a
while ($b -lt $lines.Count -and $lines[$b] -notmatch 'KD_YAW') { $b++ }
if ($b -ge $lines.Count) { throw 'KD_YAW not found after LANE_HALF — const block changed shape' }
$script:CUTS += ('  {0,-30} lines {1}..{2}' -f 'cruise consts', ($a+1), ($b+1))
$consts = ($lines[$a..$b] -join "`n")

# 真实车道 + layoutRider：长时段集成回归要用真的车流摆法，
# 不是我手摆的 z。老实说前面那 76 条里有好几条（扫遍每个横向位置、
# 两辆分站左右）是我自己指定的工况；这一条用 layoutRider 的真实分布
# 再跑一遍 180 秒，才敢说「成片里也是对的」。
$la = Find '^const LANE_R = '
if ($la -lt 0) { throw 'LANE_R not found' }
$lanes = $lines[$la]
$ba = Find '^function layoutRider\(r, first\)\{'
if ($ba -lt 0) { throw 'layoutRider not found' }
$bb = BlockEnd $ba
if ($bb -lt 0) { throw 'layoutRider end not found' }
$layout = $lines[$ba..$bb] -join "`n"
$script:CUTS += ('  {0,-30} line {1}' -f 'LANE_R/LANE_L', ($la+1))
$script:CUTS += ('  {0,-30} lines {1}..{2}' -f 'layoutRider', ($ba+1), ($bb+1))

$src = @()
$src += $consts
$src += GrabBlock '^function cruiseTick\(dt\)\{'
$src += GrabLines 'S\.steerIn = S\.cruise \? cruiseTick\(dt\)' 1
$script:CUTS | Write-Output

$tpl = [IO.File]::ReadAllText((Join-Path $dir '_cruiseharness.tpl.html'))
$tpl = $tpl.Replace('/*__CRUISE__*/', "`n" + ($src -join "`n") + "`n")
$tpl = $tpl.Replace('/*__LANES__*/',  $lanes)
$tpl = $tpl.Replace('/*__LAYOUT__*/', "`n" + $layout + "`n")
[IO.File]::WriteAllText((Join-Path $dir '_cruiseharness.html'), $tpl, (New-Object Text.UTF8Encoding($false)))
"harness bytes: {0:N0}" -f (Get-Item (Join-Path $dir '_cruiseharness.html')).Length

# ---- 语法体检：花括号和圆括号都要查 ----
# ⚠️ 圆括号也得查：只查花括号的话，「只切走构造器第一行」这种错误查不出来。
# ⚠️ 块注释必须**在切行之前**整体剥掉。按行剥是剥不干净的 ——
#    /* 第一行 … 第二行 { … */ 会被当成两行代码，注释里的花括号
#    就被算进配平。注释里出现一个 `const M = {` 就够让人以为源码少了个花括号。
$t = [IO.File]::ReadAllText((Join-Path $dir '_cruiseharness.html'))
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

# ---- 接线体检：光有控制器不够，得真的被喂进 steerIn ----
$src2 = [IO.File]::ReadAllText((Join-Path $dir '_app3d.html'))
$checks = @(
  @('巡航时才吃 cruiseTick',  'S\.steerIn = S\.cruise \? cruiseTick\(dt\) :'),
  @('手动仍只读键盘',         ': \(keys\.right \? 1 : 0\) - \(keys\.left \? 1 : 0\);'),
  @('steerCmd 在 S 里',       'steerCmd:0, autoLat:0, autoSide:0'),
  # ⚠️ 「重置时清掉 autoLat」原来是一条 grep 源码里 `S.autoLat=0; S.autoSide=0;`
  #    的判据。重置改成 `for (const k in S0) S[k] = S0[k]` 之后行为一点没变，
  #    那条 grep 反而红了 —— **判据咬死了实现写法，实现一改好它就误报**。
  #    它已经挪到 _uistate.ps1 去了：那边有闭包作用域，能真的调 resetRide()
  #    再读 S.autoLat，比看源码文本可靠得多。
  @('避让只看同向车',         'if \(u\.dir <= 0\) continue;')
)
$bad = 0
foreach ($c in $checks){
  $o = [regex]::IsMatch($src2, $c[1])
  if (-not $o) { $bad++ }
  Write-Output ("  {0}  {1}" -f $(if($o){'PASS'}else{'FAIL'}), $c[0])
}
if ($bad -gt 0) { throw 'cruise wiring check failed' }
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir '_harnesslint.ps1') -Path (Join-Path $dir '_cruiseharness.html')
# ⚠️ 这句 `exit` 千万不能少 —— 见 _mkdrive.ps1 末尾的说明。
exit $LASTEXITCODE
