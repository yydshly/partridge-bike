$ErrorActionPreference = 'Stop'
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
$dir = $ROOT
$lines = [IO.File]::ReadAllLines(($APP))

# 抽出 frame() 里的驾驶块（油门/刹车 + 转向 + 边界 + **里程累加**），逐行原样复制，不手抄
# ⚠️ 终止标记必须是 `S.km += v*dt/1000` 这一行本身，不能停在它上面那行 `const v = ...`。
#    2026-09-30：原来正好差一行，于是 harness 里的 S.km 永远是 0 ——
#    而**七套 harness 没有一套检查里程**，所以一直是绿的。
#    现在有了里程断言，这一行差一格立刻就是两条 FAIL。
#    写成具体那行还有个好处：产品改了写法，切不出来就 throw，而不是静默少切。
$from = -1; $to = -1
for ($i = 0; $i -lt $lines.Count; $i++){
  if ($lines[$i] -match 'throttle & brake'){ $from = $i }
  if ($from -ge 0 -and $lines[$i] -match 'S\.km \+= v\*dt/1000;'){ $to = $i; break }
}
if ($from -lt 0 -or $to -lt 0){ throw "driving block not found ($from..$to)" }
"driving block: app lines $($from+1)..$($to+1)"
$body = $lines[$from..$to]
# 去掉那层 if (S.running){ 的缩进（块内 4 空格），让 harness 里能直接当函数体
$body = $body | ForEach-Object { if ($_.Length -ge 4) { $_.Substring(4) } else { '' } }
$fn = @("function driveTick(dt){", "  S.tSec += dt;") + $body + "}"
$fnStr = $fn -join "`n"

# ---- 巡航代码也要切 ----
# 驾驶块里有 `S.steerIn = S.cruise ? cruiseTick(dt) : ...`，cruiseTick 是它的
# 依赖。不切的话页面一打开就 ReferenceError，58 条断言一条都不跑 ——
# 而生成器只检查括号配平，看起来一切正常。
function FindIdx([string]$pat, [int]$from = 0) {
  for ($i = $from; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pat) { return $i } }
  return -1
}
function BlockEndIdx([int]$open) {
  $d = 0
  for ($i = $open; $i -lt $lines.Count; $i++) {
    $d += ([regex]::Matches($lines[$i],'\{')).Count - ([regex]::Matches($lines[$i],'\}')).Count
    if ($d -eq 0) { return $i }
  }
  return -1
}
$ca = FindIdx '^const LANE_HALF = ROAD_W/4;'
if ($ca -lt 0) { throw 'LANE_HALF not found' }
$cb = $ca
while ($cb -lt $lines.Count -and $lines[$cb] -notmatch 'KD_YAW') { $cb++ }
if ($cb -ge $lines.Count) { throw 'KD_YAW not found after LANE_HALF' }
$fa = FindIdx '^function cruiseTick\(dt\)\{'
if ($fa -lt 0) { throw 'cruiseTick not found' }
$fb = BlockEndIdx $fa
if ($fb -lt 0) { throw 'cruiseTick end not found' }
$cruise = (@($lines[$ca..$cb]) + @($lines[$fa..$fb])) -join "`n"
"cruise block: app lines $($ca+1)..$($cb+1) + $($fa+1)..$($fb+1)"

$tpl = [IO.File]::ReadAllText(($TPL_DRIVE))
$out = $tpl.Replace('/*__CRUISE__*/', "`n" + $cruise + "`n")
$out = $out.Replace('/*__DRIVE__*/', $fnStr)
[IO.File]::WriteAllText(($OUT_DRIVE), $out, (New-Object Text.UTF8Encoding($false)))
"harness bytes: {0:N0}" -f (Get-Item ($OUT_DRIVE)).Length

# ═══ 接线检查：切出来的东西必须**包含**该包含的 ═══
# 2026-09-30 的真事故：切片终止在 `const v = S.speed / 3.6;`，
# 正好差一行 `S.km += v*dt/1000;` —— 于是 harness 里的 S.km 永远是 0，
# 而**七套 harness 没有一套检查里程**，所以一直是绿的、全量检查也是绿的。
# 浏览器里反而看出来了：车速 14.9 km/h 而 DIST 死活 0.00 km。
$wires = @(
  @{ n = '切出来的块里有 S.km 累加（里程那条线没被切掉）'
     o = ($body -join "`n") -match 'S\.km \+= v\*dt/1000;' }
  @{ n = 'harness 的 run() 带着 if (S.running)（和产品 frame() 同结构）'
     o = $tpl -match 'if \(S\.running\) driveTick' }
  @{ n = 'harness 里有里程断言（不然切掉也看不出来）'
     o = $tpl -match '逐帧积分' }
)
$wbad = 0
foreach ($w in $wires){
  Write-Output ("  {0}  {1}" -f $(if($w.o){'PASS'}else{'FAIL'}), $w.n)
  if (-not $w.o) { $wbad++ }
}
if ($wbad -gt 0) { throw "drive 接线检查失败 $wbad 条" }

# 产品里那段驾驶逻辑必须**真的**在 if (S.running) 里面 ——
# 「暂停时什么都不动」全靠它，而 harness 里的 run() 只是在模仿这个结构。
$appText = [IO.File]::ReadAllText(($APP))
$kmAt = $appText.IndexOf('S.km += v*dt/1000;')
$guardAt = if ($kmAt -ge 0) { $appText.LastIndexOf('if (S.running){', $kmAt) } else { -1 }
$insideRun = $false
if ($kmAt -ge 0 -and $guardAt -ge 0) {
  $mid = $appText.Substring($guardAt, $kmAt - $guardAt)
  $mid = [regex]::Replace($mid, '(?s)/\*.*?\*/', '')
  $mid = [regex]::Replace($mid, '(?m)//.*$', '')
  $op = ([regex]::Matches($mid,'\{')).Count
  $cl = ([regex]::Matches($mid,'\}')).Count
  $insideRun = ($op -gt $cl)      # 到里程那行为止这层还没闭合
}
Write-Output ("  {0}  产品里 S.km 的累加在 if (S.running) 里面" -f $(if($insideRun){'PASS'}else{'FAIL'}))
if (-not $insideRun) { throw '产品里 S.km 的累加不在 if (S.running) 里 —— 暂停时里程还会涨' }

& powershell -NoProfile -ExecutionPolicy Bypass -File ($S_LINT) -Path ($OUT_DRIVE)
# ⚠️ 这句 `exit` 千万不能少。2026-09-30：lint 明明报出了悬空调用、退出码是 1，
#    但生成器正常跑完就返回 0，_checkall 只看 $LASTEXITCODE，于是判成「通过」。
#    检查跑了、判对了、结论被丢掉 —— 和 frame() 缺 dt 是同一个家族。
#    子进程往 stderr 写 throw 正文**不会**让父脚本拿到非 0 退出码。
exit $LASTEXITCODE