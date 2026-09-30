$ErrorActionPreference = 'Stop'
# 时段 × 天气 的回归。切的是**真代码**，不是抄的：
#   TIMES / WEATHER / MOOD_FIELDS / mixHex / hex6 / skyHex / composeMood
#   WX·WY·WZ / makeRain / makeSnow / wetRoad / updateWeather / applyWeather
# 断言分四组：表结构、晴=原样（回归底线）、正交性、粒子循环的数值不变式。
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
# 数组字面量（[...]）不能用花括号配平，从头找以 ];  收尾的那一行
function ArrEnd([int]$open) {
  for ($i = $open; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\];') { return $i } }
  return -1
}
# ⚠️ 切出来的行号信息**不能**用 Write-Output 报 —— 函数里 Write-Output 的东西
#    会和返回值一起进输出流，于是「lines 830..861」这行字符串会被当成源码
#    一起塞进 harness（而且因为带括号还可能把配平算歪，症状是浏览器里 SyntaxError）。
$script:CUTS = @()
function Grab([string]$startPat) {
  $a = Find $startPat
  if ($a -lt 0) { throw "not found: $startPat" }
  $b = BlockEnd $a
  $script:CUTS += ('  {0,-16} lines {1}..{2}' -f $startPat, ($a+1), ($b+1))
  return ($lines[$a..$b] -join "`n")
}
function GrabArr([string]$startPat) {
  $a = Find $startPat
  if ($a -lt 0) { throw "not found: $startPat" }
  $b = ArrEnd $a
  $script:CUTS += ('  {0,-16} lines {1}..{2}' -f $startPat, ($a+1), ($b+1))
  return ($lines[$a..$b] -join "`n")
}
# 括号开头（new THREE.Mesh( … )）的构造：花括号配平在第一行就归零了，
# 必须一路走到明确的结束标记，否则只切走一行，harness 里直接 SyntaxError。
function GrabTo([string]$startPat, [string]$endPat) {
  $a = Find $startPat
  if ($a -lt 0) { throw "not found: $startPat" }
  $b = -1
  for ($i = $a; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $endPat) { $b = $i; break } }
  if ($b -lt 0) { throw "end not found: $endPat" }
  $script:CUTS += ('  {0,-16} lines {1}..{2}' -f $startPat, ($a+1), ($b+1))
  return ($lines[$a..$b] -join "`n")
}

$src = @()
# ⚠️ 顺序有讲究：makeRain() 里要用 WX/WY/WZ，而 `const RAIN = makeRain()`
#    是**当场执行**的 —— WX 的 const 声明排在它后面就是 TDZ ReferenceError。
$iWX = Find '^const WX = '
if ($iWX -lt 0) { throw 'WX const not found' }
$script:CUTS += ('  {0,-16} line {1}' -f 'const WX', ($iWX+1))
$src += $lines[$iWX]
$src += Grab '^const TIMES = \{'
$src += Grab '^const WEATHER = \{'
$src += GrabArr '^const MOOD_FIELDS = \['
$src += Grab '^function mixHex'
$iCap = Find '^function capHex'
if ($iCap -lt 0) { throw 'capHex not found' }
$script:CUTS += ('  {0,-16} lines {1}..{2}' -f 'capHex', ($iCap+1), ((BlockEnd $iCap)+1))
$src += $lines[$iCap..(BlockEnd $iCap)]
$i6 = Find '^const hex6 ='; $is = Find '^const skyHex ='
if ($i6 -lt 0 -or $is -lt 0) { throw 'hex6/skyHex not found' }
$script:CUTS += ('  {0,-16} lines {1}..{2}' -f 'hex6/skyHex', ($i6+1), ($is+1))
$src += ($lines[$i6] + "`n" + $lines[$is])
$src += Grab '^function composeMood'
$src += Grab '^const frostTex = '
$src += GrabTo '^const groundFx = ' '^scene\.add\(groundFx\);'
$src += Grab '^function makeRain'
# ⚠️ BlockEnd 只到函数的 }，紧跟其后的 `const RAIN = makeRain();` 是另一条语句 ——
#    漏掉它，harness 里 RAIN 就是 undefined，跑到断言才炸。
$iR = Find '^const RAIN = makeRain\(\);'
if ($iR -lt 0) { throw 'const RAIN not found' }
$script:CUTS += ('  {0,-16} line {1}' -f 'const RAIN', ($iR+1))
$src += $lines[$iR]
$src += Grab '^function makeSnow'
$iS = Find '^const SNOW = makeSnow\(\);'
if ($iS -lt 0) { throw 'const SNOW not found' }
$script:CUTS += ('  {0,-16} line {1}' -f 'const SNOW', ($iS+1))
$src += $lines[$iS]
$src += GrabTo '^const roadFx = ' '^scene\.add\(roadFx\);'
$src += Grab '^function updateWeather'
$src += Grab '^function applyWeather'
$src += GrabArr '^const SNOWY = \['
$src += Grab '^for \(const \[k\] of SNOWY\)'
$script:CUTS | Write-Output

# ⚠️ SNOWY 里每个键都必须在**真的** const M 里存在。替身 M 是按真 M 的键造出来的，
#    所以「表里写错一个键」在 harness 里会变成 undefined.color → 一眼能看见；
#    但更早一步就该在这里拦住，免得构建产物悄悄少一种材质被染雪。
#    $src2 必须在**这段之前**读，否则下面拿到的还是 $null —— 而
#    [regex]::Match($null, …) 不报错，只是 Groups[1].Value 给你空串。
$src2 = [IO.File]::ReadAllText((Join-Path $dir '_app3d.html'))
# ⚠️ 正则里凡是跨行的 \n 都要写成 \r?\n —— 源文件是 CRLF。
#    `(.*?)\n\];` 匹配不到 `(.*?)\r\n];`，结果整张表抓成空字符串，
#    后面只会报「SNOWY 列了 0 种」—— 不报错、不炸，最难查的一类。
#    所以下面两行数量断言不是摆设：认得太少就直接停下，别让它悄悄流过去。
$mblock = [regex]::Match($src2, '(?s)const M = \{(.*?)\r?\n\};').Groups[1].Value
$mkeys = [regex]::Matches($mblock, '(?m)^\s{2}([A-Za-z]\w*):') | ForEach-Object { $_.Groups[1].Value }
$snowy = [regex]::Match($src2, '(?s)const SNOWY = \[(.*?)\r?\n\];').Groups[1].Value
$skeys = [regex]::Matches($snowy, "\['(\w+)'") | ForEach-Object { $_.Groups[1].Value }
if ($mkeys.Count -lt 20) { throw "M 表只认出 $($mkeys.Count) 种材质，正则多半没匹配上（CRLF？）" }
if ($skeys.Count -lt 10) { throw "SNOWY 只认出 $($skeys.Count) 个键，正则多半没匹配上（CRLF？）" }
Write-Output ("  M 材质 {0} 种，SNOWY 列了 {1} 种" -f $mkeys.Count, $skeys.Count)
$miss = $skeys | Where-Object { $mkeys -notcontains $_ }
if ($miss) { throw ("SNOWY 里的键不在 M 里: " + ($miss -join ',')) }
Write-Output ("  PASS SNOWY 的 {0} 个键全在 M 里" -f $skeys.Count)

$src2 = [IO.File]::ReadAllText((Join-Path $dir '_app3d.html'))
$tpl = [IO.File]::ReadAllText((Join-Path $dir '_moodharness.tpl.html'))
$tpl = $tpl.Replace('/*__MOOD__*/', "`n" + ($src -join "`n") + "`n")
$tpl = $tpl.Replace('/*__MKEYS__*/', (($mkeys | ForEach-Object { "'$_'" }) -join ', '))
[IO.File]::WriteAllText((Join-Path $dir '_moodharness.html'), $tpl, (New-Object Text.UTF8Encoding($false)))
"harness bytes: {0:N0}" -f (Get-Item (Join-Path $dir '_moodharness.html')).Length

# ---- 语法体检：括号配平（// 必须按行剥，否则注释里的括号会污染统计）----
# ⚠️ 圆括号也得查：只查花括号的话，「只切走构造器第一行」这种错误查不出来 ——
#    new THREE.Mesh( 后面少了三行，花括号仍然是配平的，浏览器才炸。
$t = [IO.File]::ReadAllText((Join-Path $dir '_moodharness.html'))
$js = [regex]::Match($t, '(?s)<script>(.*)</script>').Groups[1].Value
# ⚠️ 块注释必须**在切行之前**整体剥掉。按行剥是剥不干净的 ——
#    /* 第一行 … 第二行 { … */ 会被当成两行代码，注释里的花括号
#    就被算进配平。本项目自己的注释里就出现过一个 `const M = {`，
#    害我以为源码少了一个花括号。用换行把注释占的位置补回来，行数才不会错位。
$js = [regex]::Replace($js, '(?s)/\*.*?\*/', { param($m) ($m.Value -replace '[^\r\n]','') })
$d = 0; $min = 0; $p = 0; $pmin = 0
foreach ($line in ($js -split "`r`n|`n")) {
  $x = [regex]::Replace($line, "'(\\.|[^'\\])*'", "''")
  $x = [regex]::Replace($x, '"(\\.|[^"\\])*"', '""')
  $x = [regex]::Replace($x, '//.*$', '')
  $d += ([regex]::Matches($x,'\{')).Count - ([regex]::Matches($x,'\}')).Count
  $p += ([regex]::Matches($x,'\(')).Count - ([regex]::Matches($x,'\)')).Count
  if ($d -lt $min) { $min = $d }
  if ($p -lt $pmin) { $pmin = $p }
}
"brace balance: $d (min $min)   paren balance: $p (min $pmin)"
if ($d -ne 0) { throw "brace imbalance in harness" }
if ($p -ne 0) { throw "paren imbalance in harness" }

# ---- 面板按钮和表必须对得上（这里能查，harness 里没有 DOM）----
$htmlIds = [regex]::Matches($src2, 'id="(t_[a-z]+|w_[a-z]+)"') | ForEach-Object { $_.Groups[1].Value }
$onIds   = [regex]::Matches($src2, 'class="on" id="(t_[a-z]+|w_[a-z]+)"') | ForEach-Object { $_.Groups[1].Value }
$bad = 0
$tk = [regex]::Match($src2, '(?s)const TIMES = \{(.*?)\r?\n\};').Groups[1].Value
$wk = [regex]::Match($src2, '(?s)const WEATHER = \{(.*?)\r?\n\};').Groups[1].Value
$want = @()
foreach ($m in [regex]::Matches($tk, '(?m)^  ([a-z]+): \{')) { $want += 't_' + $m.Groups[1].Value }
foreach ($m in [regex]::Matches($wk, '(?m)^  ([a-z]+): '))   { $want += 'w_' + $m.Groups[1].Value }
foreach ($w in $want) {
  if ($htmlIds -notcontains $w) { Write-Output "  FAIL 面板缺按钮 $w"; $bad++ }
  else { Write-Output "  PASS 面板有按钮 $w" }
}
$extra = $htmlIds | Where-Object { $want -notcontains $_ }
foreach ($e in $extra) { Write-Output "  FAIL 面板多了孤儿按钮 $e"; $bad++ }
if ($onIds.Count -ne 2 -or $onIds -notcontains 't_day' -or $onIds -notcontains 'w_clear') {
  Write-Output "  FAIL 默认高亮不是 t_day + w_clear，而是 $($onIds -join ',')"; $bad++
} else { Write-Output "  PASS 默认高亮 t_day + w_clear" }
if ($bad -gt 0) { throw "button/table mismatch" }

# ---- 接线体检：光有表和函数不够，得真的被调用到 ----
$checks = @(
  @('applyMood 调 applyWeather',      'applyWeather\(m\);'),
  @('frame 调 updateWeather',         'updateWeather\(dt, d\);'),
  @('时段按钮按表循环',               "for \(const k in TIMES\)"),
  @('天气按钮按表循环',               "for \(const k in WEATHER\)"),
  @('雨声总线建起来了',               'AU\.rain\.connect\('),
  @('雨声按雨量推',                   'AU\.rainG\.gain\.setTargetAtTime\(MOOD\.rain'),
  @('胎噪按湿度调',                   'wet\*0\.35'),
  @('下雨天鸟不叫',                   'const quiet = MOOD\.rain'),
  @('旧的两键 day/night 已无',        '^# 旧')
)
$b2 = 0
foreach ($c in $checks){
  $n = $c[0]; $p = $c[1]
  if ($n -like '旧*'){
    $okv = -not [regex]::IsMatch($src2, "(?m)`$('bDay'|'bNight')")
  } else {
    $okv = [regex]::IsMatch($src2, $p)
  }
  if (-not $okv) { $b2++ }
  Write-Output ("  {0}  {1}" -f $(if($okv){'PASS'}else{'FAIL'}), $n)
}
if ($b2 -gt 0) { throw "wiring check failed" }
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir '_harnesslint.ps1') -Path (Join-Path $dir '_moodharness.html')
# ⚠️ 这句 `exit` 千万不能少 —— 见 _mkdrive.ps1 末尾的说明。
#    2026-09-30 就是在这里丢的：paintBirdBtn 悬空调用被 lint 抓到了，
#    但 mood 那一页照样在「全绿」里，浏览器打开是一片 running…（整页一条断言没跑）。
exit $LASTEXITCODE
