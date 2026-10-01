param()
# _eventtarget.ps1 自己的反查。
#
# 这道判据的**输入边界**是「剥掉注释之后的源码文本」，而那层剥离本身就有洞：
# 剥狠了会漏检（假绿），剥松了会误报（假红）。而这个项目的注释密度非常高，
# 两边的后果都很现实。
#
# 所以除了「造坏样证明它抓得住」，这里还必须验：
#   ① 注释里写违规写法 → **不许**报（剥注释是真的在生效）
#   ② 报出来的行号能**直接定位**到真源码那一行
#   ③ 表里不只 fullscreenchange 一个事件真的生效
#
# 坏样全部做在**副本**上，判据用 -File 指向副本 —— 真源码一个字节都不碰。
$ErrorActionPreference = 'Continue'
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')

$st = @{ fail = 0 }
function Chk($name, $cond, $detail) {
  if ($cond) { Write-Output ('  PASS  ' + $name) }
  else { $st.fail++; Write-Output ('  FAIL  ' + $name); Write-Output ('        ' + $detail) }
}
function RunCheck($file) {
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $S_EVENTTARGET -File $file 2>&1 | Out-String
  return @{ code = $LASTEXITCODE; out = $out }
}
# 把副本恢复成真源码：按字节重新拷贝，而不是「把注入的那段删掉」——
# 删片段这种反向操作自己就会出错，而错法是「删漏了」，判据照样绿。
function Restore($copy) {
  Copy-Item -LiteralPath $APP -Destination $copy -Force
}

Write-Output '=== A) 前提与好样本 ==='
$copy = Join-Path $DIR_OUT '_eventtarget'
if (Test-Path $copy) { mavis-trash $copy }
$null = New-Item -ItemType Directory -Path $copy -Force
$copySrc = Join-Path $copy 'app-copy.html'
Copy-Item -LiteralPath $APP -Destination $copySrc
$appBefore = (Get-FileHash -LiteralPath $APP -Algorithm SHA256).Hash
Chk '副本和真源码一模一样' ((Get-FileHash -LiteralPath $copySrc -Algorithm SHA256).Hash -eq $appBefore) '拷贝没成功'
$r0 = RunCheck $APP
Chk '判据对**真源码**就是绿的（这就是 CI 里跑的那一次）' ($r0.code -eq 0) ('退出码=' + $r0.code + "`n" + $r0.out)

Write-Output ''
Write-Output '=== B) 坏样一：document. 前缀没了（这正是当初那个真 bug）==='
$before = (Get-FileHash -LiteralPath $copySrc -Algorithm SHA256).Hash
$t = [IO.File]::ReadAllText($copySrc)
$t2 = $t -replace "document\.addEventListener\('fullscreenchange'", "addEventListener('fullscreenchange'"
[IO.File]::WriteAllText($copySrc, $t2, (New-Object Text.UTF8Encoding($false)))
# 造完坏样先证明它真的坏了 —— -replace 匹配不上时是**静默**返回原串的。
$afterHash = (Get-FileHash -LiteralPath $copySrc -Algorithm SHA256).Hash
Chk '坏样确实和原文件不同（没替换成功就是好样，不是坏样）' ($afterHash -ne $before) '两个哈希一样'
$r1 = RunCheck $copySrc
Chk '去掉 document. → 判据必须 exit 1' ($r1.code -ne 0) ('退出码=' + $r1.code)
Chk '...并且点名 fullscreenchange' ($r1.out -match 'fullscreenchange') $r1.out
Chk '...并且说清「裸写 = 绑在 window 上」' ($r1.out -match '绑在 window 上') $r1.out

Write-Output ''
Write-Output '=== C) 报出来的行号必须能直接定位（第一版在这里是错的）==='
# 第一版剥块注释时把跨行注释压成了一行，于是所有行号前移：
# 判据说「第 3659 行」，编辑器里其实是 3961 行 —— 人跳过去根本找不到。
# 这里拿副本的真实行号和判据报的行号对一次。
$realLine = 0
$lns = [IO.File]::ReadAllLines($copySrc)
for ($i = 0; $i -lt $lns.Count; $i++) {
  if ($lns[$i] -match "^\s*addEventListener\('fullscreenchange'") { $realLine = $i + 1; break }
}
Chk '副本里那行确实能被独立找到（定位基准本身有效）' ($realLine -gt 0) '没找到'
$mm = [regex]::Match($r1.out, '第\s*(\d+)\s*行')
Chk '判据输出里解析得出行号' $mm.Success $r1.out
if ($mm.Success) {
  Chk ('判据报的行号和副本里的真实行号一致（报 ' + $mm.Groups[1].Value + '，实际 ' + $realLine + '）') `
      ([int]$mm.Groups[1].Value -eq $realLine) `
      ('判据报 ' + $mm.Groups[1].Value + '，副本实际在 ' + $realLine)
}
Restore $copySrc
Chk '还原之后判据重新变绿' ((RunCheck $copySrc).code -eq 0) '还原没成功'

Write-Output ''
Write-Output '=== D) 坏样二：明写 window. ==='
$t = [IO.File]::ReadAllText($copySrc)
$t2 = $t -replace "document\.addEventListener\('webkitfullscreenchange'", "window.addEventListener('webkitfullscreenchange'"
[IO.File]::WriteAllText($copySrc, $t2, (New-Object Text.UTF8Encoding($false)))
Chk '坏样 b 确实改动了' ((Get-FileHash -LiteralPath $copySrc -Algorithm SHA256).Hash -ne $appBefore) '没改成'
$r2 = RunCheck $copySrc
Chk '明写 window. → 判据必须 exit 1' ($r2.code -ne 0) ('退出码=' + $r2.code)
Chk '...并且点名 window' ($r2.out -match 'window') $r2.out
Restore $copySrc

Write-Output ''
Write-Output '=== E) 坏样三：表里不只 fullscreenchange 一个事件生效 ==='
# 拿一个源码里**根本没出现**过的事件（fullscreenerror）注入到别的对象上。
# 如果只有 fullscreenchange 那条在真算，注入它就不会红。
$t = [IO.File]::ReadAllText($copySrc)
$inject = "window.addEventListener('fullscreenerror', () => {});`r`n"
[IO.File]::WriteAllText($copySrc, ($t + $inject), (New-Object Text.UTF8Encoding($false)))
$r3 = RunCheck $copySrc
Chk '注入 window 上的 fullscreenerror → 判据必须 exit 1' ($r3.code -ne 0) ('退出码=' + $r3.code)
Chk '...并且点名 fullscreenerror' ($r3.out -match 'fullscreenerror') $r3.out
Restore $copySrc

Write-Output ''
Write-Output '=== F) 输入边界：注释里的违规写法**不许**报 ==='
# 这一段验的是判据的「输入边界」，而边界必须有人验 ——
# 剥注释失效的话，这里会红；而它红了人只会去关掉判据，不会想到去修剥离。
$blk = "`r`n/* 教学示例：document.addEventListener('fullscreenchange', syncFs) 这一行如果写成 addEventListener(...) 就绑错对象了 */`r`n"
$lin = "`r`n// 同理：addEventListener('webkitfullscreenerror', x) 也是错的`r`n"
[IO.File]::WriteAllText($copySrc, ([IO.File]::ReadAllText($copySrc) + $blk + $lin), (New-Object Text.UTF8Encoding($false)))
$hasBad = ([IO.File]::ReadAllText($copySrc) -match "addEventListener\('fullscreenchange'")
Chk '注释里**确实**含有违规写法（好样本的前提）' $hasBad '没注进去，这条会变成恒过的假绿'
$r4 = RunCheck $copySrc
Chk '注释里的违规写法不许报（剥注释在生效）' ($r4.code -eq 0) ('退出码=' + $r4.code + "`n" + $r4.out)
Restore $copySrc

Write-Output ''
Write-Output '=== G) 收尾：真源码一个字节都没被碰 ==='
Chk '真源码哈希没变' ((Get-FileHash -LiteralPath $APP -Algorithm SHA256).Hash -eq $appBefore) '反查碰了真源码'
if (Test-Path $copy) { mavis-trash $copy }

Write-Output ''
if ($st.fail -eq 0) {
  Write-Output '  eventtarget 判据成立：好样本不误伤、三种坏样各自红并点名、行号能定位、注释里的写法不误报、没碰真源码。'
  exit 0
}
Write-Output ('  eventtargettest 失败 ' + $st.fail + ' 条')
exit 1
