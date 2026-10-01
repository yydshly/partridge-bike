param([string]$File)
# 「事件监听挂在谁身上」的静态判据。
#
# 为什么需要它：这一类 bug **能防住它的检查必须在真浏览器里跑**
# （得真的进全屏、真的按 Esc、真的切标签页），而 GitHub 的 CI 跑不了浏览器页面。
# 于是 syncFs 那个 bug 当初只能靠人眼发现：监听写成了顶层裸
# addEventListener（= 绑 window），而 fullscreenchange 只在 document 上派发
# 且不冒泡 → syncFs 一次都没跑过 → Esc 退全屏后界面还藏着。
# 动态反查能抓住这一处，但**只覆盖它测过的那一处**；
# 以后再写第二处、第三处，没有人会记得去扩那条反查。
#
# 所以在这里把它提成一道**常驻静态判据**：源码里凡是监听「只在 document 上
# 派发且不冒泡」的事件，对象必须是 document.，写别的（含裸写）就判红。
#
# ⚠️ 这张表**只收本项目实测过的事件**，不要凭记忆往里加。
#   收录的门槛是「我有一条本仓库内的证据能证明绑 window 收不到」。
#   拿不准的事件加进来 = 误报，而**会误报的守卫最后会被关掉**。
#   反例：visibilitychange 的「冒不冒泡」各来源就自相矛盾 ——
#   caniuse 的兼容性注记说 Safari 14 之前不冒泡，MDN 新页面却标 Bubbles: Yes。
#   本机也实测不了（只在真实切标签时触发，工具链切不回上一个标签页）。
#   所以它**不进这张表**；那一行改成绑 document，绕开了「冒不冒泡」这个问题 ——
#   绑到事件的 target 上，在所有浏览器所有版本上都成立。
$ErrorActionPreference = 'Stop'
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
if (-not $File) { $File = $APP }

$st = @{ fail = 0; seen = 0 }
function Chk($name, $cond, $detail) {
  if ($cond) { Write-Output ('  PASS  ' + $name) }
  else { $script:st.fail++; Write-Output ('  FAIL  ' + $name); Write-Output ('        ' + $detail) }
}

Write-Output '=== 只在 document 上派发、不冒泡的事件，监听必须绑 document ==='
if (-not (Test-Path -LiteralPath $File)) {
  Write-Output ('  ! 读不到源文件：' + $File); exit 1
}
$text = [IO.File]::ReadAllText($File)
Chk '源文件非空' ($text.Length -gt 1000) ('len=' + $text.Length)

# ── 先剥注释 ────────────────────────────────────────────────
# 不剥的话，注释里举的例子会被当成真代码判红 —— 而这个项目的注释密度很高。
# ⚠️ 剥的时候**必须保住行结构**：块注释用 MatchEvaluator 把非换行字符换成空格，
#    换行符留着。第一版直接 Replace 成一个空格，跨行注释于是被压成一行，
#    后面所有行号全部前移 —— 判据说「第 3659 行」，编辑器里却是 3961 行，
#    人跳过去根本找不到。**报出来的行号必须能直接定位**，
#    这条由 checks\self\_eventtargettest.ps1 的 ③ 验。
# 去行注释时用一个朴素的引号状态机，避免把 'http://…' 里的 // 当注释。
$noBlock = [regex]::Replace($text, '(?s)/\*.*?\*/', {
  param($m) ($m.Value -replace '[^\n]', ' ')
})
$lines = $noBlock -split "`r?`n"
$clean = @()
foreach ($ln in $lines) {
  $inS = $false; $inD = $false; $cut = $ln.Length
  for ($i = 0; $i -lt $ln.Length; $i++) {
    $c = $ln[$i]
    if ($c -eq '\' -and $i -gt 0) { $i++; continue }          # 跳过被转义的字符
    if ($c -eq "'" -and -not $inD) { $inS = -not $inS }
    elseif ($c -eq '"' -and -not $inS) { $inD = -not $inD }
    elseif ($c -eq '/' -and -not $inS -and -not $inD -and ($i + 1) -lt $ln.Length -and $ln[$i+1] -eq '/') {
      $cut = $i; break
    }
  }
  $clean += $ln.Substring(0, $cut)
}
$code = ($clean -join "`n")
Chk '剥掉注释之后代码明显变短（说明真的剥了，不是空转）' ($code.Length -lt $text.Length) `
    ('原 ' + $text.Length + ' 字 → 剩 ' + $code.Length + ' 字')

# ── 扫描 ────────────────────────────────────────────────────
# 只收实测过的事件（理由见抬头）。webkit 家族和标准名要**一起**匹配，
# 但引号紧贴事件名，所以 'webkitfullscreenchange' 不会被 'fullscreenchange' 误命中。
$names = @('fullscreenchange', 'webkitfullscreenchange', 'fullscreenerror', 'webkitfullscreenerror')
# ⚠️ 三组**全都起名**，不要靠 Groups[1]/[2] 取值：
#    .NET 里命名组和未命名组是**分别编号**的 —— 上面那个未命名的事件名组
#    永远是 Groups[1]，而 tgt/fn 落在 2 和 3。
#    凭「按左括号顺序数下来」写死编号，会安静地取到**另一个组**：
#    第一版就取成了 Groups[3] = 函数名，于是报出
#    「'addEventListener' 只在 document 上派发」这种驴唇不对马嘴的话。
$rx = [regex]('(?<tgt>[A-Za-z_$][\w$]*\s*\.\s*)?(?<fn>addEventListener|removeEventListener)\(\s*[''"](?<ev>' +
       ($names -join '|') + ')[''"]')
$hits = @($rx.Matches($code))
Chk '真的扫到了这些监听（扫不到时，全绿是没有意义的）' ($hits.Count -ge 2) `
    ('只扫到 ' + $hits.Count + ' 处 —— 正则可能已经和代码对不上了')

$bad = 0
foreach ($h in $hits) {
  $st.seen++
  $ev = $h.Groups['ev'].Value
  $fn = $h.Groups['fn'].Value
  # 目标组连着那个点一起捕到了（`document.`），所以点号和空白都得去掉
  # 才能和 'document' 比 —— 只剥空白的话它会判成「绑在 document. 上」而报红。
  $tgt = ($h.Groups['tgt'].Value -replace '[\s\.]', '')
  $line = 1 + ([regex]::Matches($code.Substring(0, $h.Index), "`n")).Count
  if ($tgt -eq 'document') {
    Write-Output ('  PASS  第 {0,5} 行  document.{1}(''{2}'' …)' -f $line, $fn, $ev)
  } else {
    $bad++
    $shown = if ($tgt) { $tgt } else { '(裸写 = 绑在 window 上)' }
    Write-Output ('  FAIL  第 {0,5} 行  {1}{2}(''{3}'' …)' -f $line, $shown, $fn, $ev)
    Write-Output ('        ''{0}'' 只在 document 上派发且不冒泡，绑在 {1} 上收不到' -f $ev, $shown)
  }
}

Write-Output ''
if ($bad -eq 0) {
  Write-Output ('  事件监听目标成立：扫到 ' + $st.seen + ' 处，全部绑在 document 上。')
  exit 0
}
Write-Output ('  eventtarget 失败 ' + $bad + ' 处')
exit 1
