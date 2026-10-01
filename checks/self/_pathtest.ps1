param()
# _pathcheck.ps1 的反查：恒过的检查等于没有检查。
#
# 三个用例，两头都要：
#   ① 现在的源码（干净）           → 必须 exit 0
#   ② 注入一处已知的硬编码路径      → 必须 exit 1 且**点名那一行**
#   ③ 注入一处「路径来自数据」的写法  → 必须 exit 1 且**点名 Join-Path**
#
# ②③ 为什么必须点名那一行：只报「有 1 处硬编码」的话，
# 删掉别的东西也一样会 FAIL —— 报得出**位置**才算真的抓到了那个 bug。
# 第 ① 条是「反查的反查」：一把永远说「没事」的尺子，光有 ②③ 也是全绿。
#
# ⚠️ 反查的靶子是一份**真源码副本**（_mkdrive.ps1 + 一处改动），
#    不碰真文件。用真源码是因为「已知坏」必须是真代码改出来的 ——
#    自己编一份假源码，测不出这套判据在真代码上准不准。
#
# ⚠️⚠️ 本文件自己**故意包含**它要测的那两种写法，所以注入用的片段
#    必须在**运行时**拼出来：
#      - 文件名从 $APP 取叶子，不写字面量 —— 否则 _pathcheck 会把
#        本文件自己报成一处硬编码
#      - 基准目录变量名拆成 '$' + 'dir' 拼出来 —— 否则本文件自己
#        就会被判据 ② 抓出来
#    一份能测出别人问题的检查，不该自己先犯规。这不是洁癖：
#    判据扫的是**全部**脚本，它自己也在射程内。
$ErrorActionPreference = 'Continue'
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')

$check   = $S_PATHCHECK
$realGen = $S_MKDRIVE
$victim  = Join-Path $DIR_GEN '_mkpathtest.ps1'
$victimRel = 'gen\_mkpathtest.ps1'

# 运行时才成形的两块
$dl   = '$' + 'dir'              # 基准目录变量名
$leaf = Split-Path $APP -Leaf     # 被硬编码的那个文件名
$jpLit = 'Join-Path ' + $dl + ' ' # 判据 ② 输出里的那串字

$fail = 0

function Run-Check([string]$Pf) {
  $o = if ($Pf) { & powershell -NoProfile -ExecutionPolicy Bypass -File $check -PathsFile $Pf 2>&1 | Out-String }
       else     { & powershell -NoProfile -ExecutionPolicy Bypass -File $check 2>&1 | Out-String }
  return @{ code = $LASTEXITCODE; out = $o }
}
function Expect($name, $wantCode, $wantText, [string]$Pf) {
  $r = Run-Check $Pf
  $okExit = ($r.code -eq $wantCode)
  $okText = if ($wantText) { ($r.out -match [regex]::Escape($wantText)) } else { $true }
  $ok = $okExit -and $okText
  if (-not $ok) { $script:fail++ }
  Write-Output ("  {0}  {1}  (退出码 {2}，期望 {3}{4})" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $r.code, $wantCode,
                $(if ($wantText) { "，输出里要有「$wantText」" } else { '' }))
  if (-not $ok) { Write-Output (($r.out.TrimEnd() -split "`n" | ForEach-Object { '        ' + $_ }) -join "`n") }
}

# 锚点：_mkdrive.ps1 里一定会有的那一行。
# ⚠️ 锚点是从 $APP 的名字**推**出来的，不是抄的 ——
#    抄的锚点会和判据靶子一起过期，于是反查悄悄变成测一个不存在的锚点。
$anchor = '$lines = [IO.File]::ReadAllLines'
$orig = [IO.File]::ReadAllText($realGen)
if ($orig.IndexOf($anchor) -lt 0) { throw "反查注入失败：_mkdrive.ps1 里没有锚点，这把尺子就成了恒过的" }

function Inject([string]$payload) {
  $bad = $orig.Replace($anchor, ($payload + "`r`n" + $anchor))
  if ($bad -eq $orig) { throw "反查注入失败：替换没有生效" }
  if (Test-Path $victim) { mavis-trash $victim }
  [IO.File]::WriteAllText($victim, $bad, (New-Object Text.UTF8Encoding($true)))
}

Write-Output '=== 1) 现在的源码：必须 exit 0（好样本不误伤）==='
Expect '全部路径都走 _paths.ps1' 0 '路径收口成立'

Write-Output ''
Write-Output '=== 2) 注入一处硬编码文件名：必须 exit 1 且点名那一行 ==='
Inject ('x = ' + $jpLit + ("'" + $leaf + "'"))
try {
  Expect 'gen\_mkpathtest.ps1 里写死了源文件名' 1 ($victimRel + ':')
} finally {
  mavis-trash $victim
}

Write-Output ''
Write-Output '=== 3) 注入一处「路径来自数据」的写法：必须 exit 1 且点名 Join-Path ==='
# 判据 ① 是静态的，认的是引号里的文件名。
# 「第二个参数运行时才有」这种，脚本里根本没有字面量，① 看不见 ——
# 而它照样会在文件一搬走时断掉（_build.ps1 的 Join-Path $dir $t.f 就是）。
# 所以必须有第二道判据专门盯它，而且反查里必须有这一条 ——
# 不然 ② 就是一道没人验过的判据。
Inject ('x = ' + $jpLit + '$t.f')
try {
  Expect 'gen\_mkpathtest.ps1 里 Join-Path + 非字面量' 1 $jpLit
} finally {
  mavis-trash $victim
}

Write-Output ''
Write-Output '=== 4) 注入一处变量名碰撞：必须 exit 1 且点名那个变量 ==='
# 这条对应的是**真的发生过**的事故：2026-10-01 的路径收口把
# `$app = ReadAllText((Join-Path $dir '_app3d.html'))` 改成了
# `$app = ReadAllText($APP)` —— 而 PowerShell 变量名大小写不敏感，
# `$app` 就是 `$APP`，于是这行把**路径变量**改成了源文件正文，
# 之后每一行再拿 $APP 当路径用都炸。
# 注入时用**小写** `$app` 而不是 `$APP` —— 「只差大小写」才是这个坑的形态；
# 注入一个完全不同的名字，判据抓到了也证明不了它认得大小写不敏感这件事。
# 片段在运行时拼出来，免得本文件自己被扫成一处碰撞
# （本文件的那一行以 Inject 开头，判据的 `^\s*\$\w+\s*=` 匹配不到它）。
Inject ('$a' + 'pp = 1')
try {
  Expect 'gen\_mkpathtest.ps1 里给路径变量名赋值' 1 'PowerShell 大小写不敏感'
} finally {
  mavis-trash $victim
}

Write-Output ''
# ── 判据 ④ 的反查：三个实拍探针的输出文件不许撞车 ──────────────
# 病是真的：_mkdbg / _mkpause / _mkrec 三个探针**共用**一个 $OUT_DBG。
# 三个脚本每一个都 exit 0、每一行输出都正常，可谁后跑谁把前一个的页覆盖掉 ——
# 「我刚那个取景页还在不在」这件事，改之前没有任何一个脚本问过。
# 也就是说这类错**不产生任何失败信号**：别的判据全都抓不到它。
#
# 靶子是一份**改造过的 _paths.ps1 副本**，用 -PathsFile 指过去 ——
# 判据只认真文件的话，这条反查就无从下手。
# 副本放 dist\：pathcheck 的脚本扫描跳过 dist\，所以 ① 看不见它，
# 于是这里 exit 1 只可能来自 ④ —— 证的是 ④ 本身，不是「反正红了吧」。
$pfOrig = [IO.File]::ReadAllLines((Join-Path $ROOT '_paths.ps1'))
$fixtureDir = Join-Path $DIR_OUT '_pathtest'
$pfIdx = @{}
for ($i = 0; $i -lt $pfOrig.Count; $i++) {
  if ($pfOrig[$i] -match '^\$(OUT_[A-Z]+)\s*=') { $pfIdx[$Matches[1]] = $i }
}
foreach ($need in @('OUT_DBG','OUT_PAUSE','OUT_REC')) {
  if (-not $pfIdx.ContainsKey($need)) {
    throw ("反查注入失败：_paths.ps1 里没有 `$$need 这一行 —— 判据 ④ 的三个变量名和 _paths.ps1 已经对不上了，" +
           "这两边同时过期的话，④ 会去查一个不存在的变量，而「查不到」和「有冲突」是两回事。")
  }
}
$pfFile = Join-Path $fixtureDir '_paths.ps1'
# ⚠️ mavis-trash 往 **stdout** 打一行「moved to trash」。不接住的话，
#    PowerShell 会把它一起收进函数的返回值，返回值就变成
#    @('那行字', '路径')，再被 [string] 形参一拼成一句带空格的话，
#    pathcheck 于是报「The given path's format is not supported」。
#    而那次的 exit 0 和「判据放过坏样本」在终端上**长得一模一样**。
#    这也是为什么这里不写 `return $pfFile`：函数一旦有多余输出就全盘失真。
function Build-Fixture([string[]]$lines) {
  if (Test-Path $fixtureDir) { $null = mavis-trash $fixtureDir }
  $null = New-Item -ItemType Directory -Path $fixtureDir -Force
  [IO.File]::WriteAllLines($pfFile, $lines, (New-Object Text.UTF8Encoding($true)))
  if (-not (Test-Path -LiteralPath $pfFile)) { throw '反查注入失败：夹具没写成' }
  $script:pfBuilt = $pfFile
}
try {
  # 5) 把 $OUT_REC 的**值**换成 $OUT_PAUSE 那个文件 —— 当年的病原样。
  #    ⚠️ 第一版是在上面**多插一行** $OUT_REC = <_pause 的值>，判据却放行了。
  #    原因是 PowerShell 里同一个变量**后一行生效**：真 _paths.ps1 里那行
  #    原本的 $OUT_REC 还在、且在下面，于是实际值没变，判据（也用哈希表只留
  #    后者）读到的就是没撞车的那个值。教训：造坏样本必须让「坏」在**最终生效值**上，
  #    光在文件里留一行错字是不够的 —— 判据和解释器一致，也会被解释器的规则骗。
  $src = $pfOrig[$pfIdx['OUT_PAUSE']]
  $valTail = $src.Substring($src.IndexOf('='))          # '= "$DIR_OUT\_pause.html"  # …'
  $clashVar = '$' + 'OUT_REC'
  $clashLines = @($pfOrig[0..($pfIdx['OUT_REC'] - 1)]) + @(($clashVar + '     ' + $valTail)) +
                @($pfOrig[($pfIdx['OUT_REC'] + 1)..($pfOrig.Count - 1)])
  Build-Fixture $clashLines
  Expect '两个探针写到同一个文件' 1 'OUT_REC' $script:pfBuilt

  # 6) 整个变量没定义：必须单独报「没有定义」，不能当成「有冲突」糊过去
  $missLines = @($pfOrig[0..($pfIdx['OUT_REC'] - 1)]) + @($pfOrig[($pfIdx['OUT_REC'] + 1)..($pfOrig.Count - 1)])
  Build-Fixture $missLines
  Expect '少一个探针输出变量' 1 '没有定义' $script:pfBuilt

  # 7) 同名变量被定义两次且值不同（就是第 5 条第一版骗判据的那一招）：
  #    必须被单独报出来，不许因为「后一行生效」而被放过
  $dupLines = @($pfOrig[0..($pfIdx['OUT_REC'] - 1)]) + @($clashVar + '     ' + $valTail) +
              @($pfOrig[$pfIdx['OUT_REC']..($pfOrig.Count - 1)])
  Build-Fixture $dupLines
  Expect '同一个输出变量被定义两次' 1 '被定义了两次' $script:pfBuilt
} finally {
  if (Test-Path $fixtureDir) { mavis-trash $fixtureDir }
}

Write-Output ''
if (Test-Path $victim) { mavis-trash $victim }
if ($fail -eq 0) {
  Write-Output 'pathcheck 反查成立：好源码放行，注入的硬编码 / 数据来源路径 / 变量名碰撞 / 探针输出撞车都拦得住（不是恒过）'
  exit 0
}
Write-Output "pathcheck 反查失败 $fail 条"
exit 1
