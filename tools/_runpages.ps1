param(
  # ⚠️ 这里接的是**一个逗号分隔的字符串**，不是数组 —— 是三个坑逼出来的：
  #   ① 数组参数不贪婪：`-Set 58/58 34/34 …` 会把 34/34 当成**位置参数**。
  #   ② 加了 ValueFromRemainingArguments 也救不回来：只要后面还有一个能接
  #      位置参数的形参（哪怕有默认值），那些数字仍然去绑它 ——
  #      实测 "Cannot convert 34/34 to Int32"。
  #   ③ 而 `powershell -File script.ps1` 这种**最常用的调法**下，
  #      ValueFromRemainingArguments 本身也不可靠（实测报
  #      "A positional parameter cannot be found that accepts argument '34/34'"）。
  #   收成一个字符串自己 split(',') 是唯一在 -File 模式下稳的写法。
  #   宁可少两个旋钮，也不要一个会把九个数字吃掉一半的参数。
  [string]$Set
)
$GAP = 6
# 把九套回归页的**真实条数**取出来，交给 README 写回去。
#
# 它解决的是「README 里那九个数字会悄悄过期」：
# 九套 harness 由生成器从**成品**切代码段产生，所以改一行 src，
# 九套页面全部被重新生成，条数可能变。而 _doccheck 查的是步数、命令路径、
# 产物名 —— 唯独查不了运行时条数（静态数调用点不等于条数，循环会展开）。
# 于是那九个数字是**手打的**，而没有任何检查能发现它开始说谎。
#
# ⚠️ 这件事**只能做一半**，原因写在下面，请先读完再用：
#   能做的：读出 README 现在的九个数字 / 打开九页 / 把新数字写回 README。
#   做不到的：**读标题**。无头 Chrome 渲染不了这些页面（11 MB 单文件 +
#     持续 rAF + 软件 WebGL；实测 150 秒被看门狗杀掉、dump 出 0 字节）。
#   所以「谁把标题读出来」这一步要么是人，要么是 agent 用浏览器逐个开。
#   这个脚本不假装自己能做它 —— 那样造出来的是一个「看起来全自动、实际
#   只会打印 0 条」的脚本，那比没有更糟。
#
# 典型用法：
#   1) 跑它（不带参数）→ 打开九页，并打印 README 现在的数字对照表
#   2) 在浏览器里逐个看标题，记下 PASS n/m
#   3) 跑它 -Set 58/58,34/34,... → 直接写回 README，格式不会错
$ErrorActionPreference = 'Stop'
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')

if (-not $README -or -not (Test-Path -LiteralPath $README)) { throw "找不到 README（_paths.ps1 里的 `$README）" }
$text = [IO.File]::ReadAllText($README)
$pages = @($OUT_NAMES)                    # 顺序即 README 里那九个数的顺序
$n = $pages.Count

# ── 从 README 读出「现在写着什么」 ───────────────────────────
# 找不到那一段就说清楚，而不是安静地按「空」处理 —— 后者会让 -Set
# 悄悄往 README 里插一段没人要的文字。
$anchor = $text.IndexOf('九套实测')
if ($anchor -lt 0) {
  Write-Output '  ! README 里找不到「九套实测」那一段。'
  Write-Output '    -Set 会拒绝写入（否则会插出一段没人要的新文字）。'
  Write-Output '    锚点被改过的话，把这里和 README 对齐。'
  exit 1
}
$lineStart = $text.LastIndexOf("`n", $anchor) + 1
$dotAt = $text.IndexOf('。', $anchor)
if ($dotAt -lt 0) { throw 'README 里「九套实测」那段没有句号，找不到它的结尾' }
$seg = $text.Substring($anchor, $dotAt - $anchor)
$cur = @([regex]::Matches($seg, '(\d+)\s*/\s*(\d+)') | ForEach-Object { $_.Value -replace '\s', '' })
$curOK = ($cur.Count -eq $n)

Write-Output '=== README 现在写的九个数 ==='
for ($i = 0; $i -lt $n; $i++) {
  $was = if ($curOK -and $i -lt $cur.Count) { $cur[$i] } else { '(没读到)' }
  $file = Join-Path $DIR_OUT $pages[$i]
  $st = if (Test-Path -LiteralPath $file) { ((Get-Item -LiteralPath $file).Length.ToString('N0') + ' bytes') } else { '缺页！' }
  Write-Output ('  {0,-22} {1,-10} {2}' -f $pages[$i], $was, $st)
}
if (-not $curOK) {
  Write-Output ('  ! 读到 ' + $cur.Count + ' 个数，期望 ' + $n + ' 个 —— README 那一段可能被手改过')
}

# ── -Set：写回 ─────────────────────────────────────────────
$vals = @()
if ($Set) { $vals = @($Set -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }) }

if ($vals.Count -gt 0) {
  if ($vals.Count -ne $n) {
    Write-Output ('  ! 给了 ' + $vals.Count + ' 个数，期望 ' + $n + ' 个。顺序 = $OUT_NAMES：')
    for ($i = 0; $i -lt $n; $i++) { Write-Output ('      ' + ($i+1) + '. ' + $pages[$i]) }
    exit 1
  }
  # 每项要么写 n，要么写 n/m。分母缺省等于分子（PASS n/n 的常态）。
  $norm = @()
  for ($i = 0; $i -lt $n; $i++) {
    $s = ($vals[$i] -replace '\s', '')
    if ($s -notmatch '^\d+(/\d+)?$') {
      Write-Output ('  ! 第 ' + ($i+1) + ' 项「' + $vals[$i] + '」不是 n 或 n/m 的样子，没写')
      exit 1
    }
    if ($s -notmatch '/') { $s = $s + '/' + $s }
    $norm += $s
  }
  $bad = @($norm | Where-Object { ($_ -split '/')[0] -ne ($_ -split '/')[1] })
  if ($bad.Count -gt 0) {
    Write-Output ('  ! 下面这些不是全过：' + ($bad -join ' '))
    Write-Output '    这一行是「九套实测」= 全部 PASS。有没过的那套，把数字照实写上（n/m 形式）。'
  }
  $line = '九套实测（' + (Get-Date -Format 'yyyy-MM-dd') + '，实跑见 tools\_runpages.ps1）：' +
          (($norm | ForEach-Object { '`' + $_ + '`' }) -join ' · ') + '。'
  $newText = $text.Substring(0, $lineStart) + $line + $text.Substring($dotAt + 1)
  [IO.File]::WriteAllText($README, $newText, (New-Object Text.UTF8Encoding($false)))

  # 写完**立刻自证写对了**。锚点是按「九套实测」+「第一个句号」算出来的，
  # 万一哪天 README 前面出现一个句号，整段就可能被写歪 —— 而那之后
  # doccheck 不会报（它查命令路径/步数/产物名，不查这一段）。
  # 所以这里重新读回来核对：九个数字对得上，且**没吞掉别的东西**
  # （长度差应当只有几十个字符，那是日期和「实跑见…」那几个字的长度）。
  $after = [IO.File]::ReadAllText($README)
  $a2 = $after.IndexOf('九套实测')
  $d2 = $after.IndexOf('。', $a2)
  $got = @([regex]::Matches($after.Substring($a2, $d2 - $a2), '(\d+)\s*/\s*(\d+)') |
          ForEach-Object { $_.Value -replace '\s', '' })
  $same = ($got.Count -eq $n)
  for ($i = 0; $same -and $i -lt $n; $i++) { if ($got[$i] -ne $norm[$i]) { $same = $false } }
  $delta = [Math]::Abs($after.Length - $text.Length)
  if (-not $same) {
    Write-Output '  ! 写完之后重新读回来对不上 —— README 可能已经被写歪了，请立刻看一眼：'
    Write-Output ('    写进去的是：' + ($norm -join ' '))
    Write-Output ('    读回来的是：' + ($got -join ' '))
    exit 1
  }
  if ($delta -gt 200) {
    Write-Output ('  ! README 长度变了 ' + $delta + ' 字符（预期几十个）—— 可能吞掉了别的内容，请检查')
    exit 1
  }

  Write-Output ''
  # ⚠️ 这里必须用 -f，不能用 `+ $delta +`：
  #   $delta 是 Int32，它在**左操作数**的位置上 → PowerShell 选数值加法 →
  #   `'…变了 ' + $delta + ' 字符'` 抛 "Cannot convert value" 或吐出 `+0+` 这种
  #   带换行的怪东西。凡是把数字接进句子，一律 -f。
  Write-Output ('  README 已改写成（读回核对过：九个数字一致，长度只变了 {0} 字符）：' -f $delta)
  Write-Output ('    ' + $line)
  Write-Output ''
  Write-Output '  ⚠️ 这九个数字是**人/agent 实跑出来的**，不是本脚本算出来的。'
  Write-Output '     它们只在你真的逐个看过标题之后才能写进来。'
  exit 0
}

# ── 默认：打开九页 ─────────────────────────────────────────
Write-Output ''
Write-Output '=== 正在逐个打开九页（每页间隔 ' + $GAP + ' 秒）==='
Write-Output '  打开之后**逐个看标签页标题**，那里会变成 PASS n/m。'
Write-Output ''
$opened = 0
foreach ($pg in $pages) {
  $f = Join-Path $DIR_OUT $pg
  if (-not (Test-Path -LiteralPath $f)) {
    Write-Output ('  ! 缺页，跳过：' + $pg)
    Write-Output '    先跑 checks\_checkall.ps1（它负责生成 harness 页）'
    continue
  }
  Start-Process $f
  $opened++
  Start-Sleep -Seconds $GAP
}
Write-Output ('  已打开 ' + $opened + '/' + $n + ' 页。')
Write-Output ''
Write-Output '下一步：把九页标题里的 PASS n/m 抄下来，然后（**逗号分隔**）'
# 模板直接取 README 现在写的九个数，**不写死** ——
# 写死过一次（39/39），真跑出来 41/41 之后它就成了一句谎话，
# 而 -Set 的建议行恰恰是最容易被照抄的那一行。
Write-Output ('  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\_runpages.ps1 -Set ' + (($cur | ForEach-Object { $_ }) -join ','))
Write-Output '（顺序 = 上表；n 可以只写一个数，省略 /n）'
exit 0
