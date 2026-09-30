param()
# 一次性迁移工具：把 28 个脚本里散落的硬编码路径，收口到 _paths.ps1。
#
# 它只做两件机械的事，剩下的散落写法留给人工：
#   ① 在每个脚本开头插入「往上找 _paths.ps1」的三行引导（+ 保留原来的 $dir/$d/$root 变量名）
#   ② 把 Join-Path $dir '文件名' 换成 _paths.ps1 里的对应变量
#
# ⚠️ 它**故意不碰**注释行、here-string 内部、以及 `& $ps '_build.ps1'` 这类
#    非 Join-Path 写法 —— 那几处要人工看，机器改容易改出恒过的假绿。
#    跑完会把「改了多少、哪些没动」打印出来，没动的部分就是人工待办清单。
$ErrorActionPreference = 'Stop'
$dir = 'E:\minimax_code_project\0929_project\partridge-bike'
$pathsFile = Join-Path $dir '_paths.ps1'
$NL = "`r`n"

# ── 从 _paths.ps1 自动推出「文件名 → 变量」映射 ──────────────
# ⚠️ 这里踩了三次同一类的坑，第三次才看明白：
#   ① 正则只认「整行就是赋值」，结果 $APP / $PRODUCT / $BGM_META / $THREE_LIB
#      这四行**后面有行尾注释**，一条都没进 map。工具照样报「共替换 23 处」，
#      23 看着是个合理数字，于是没人问「为什么不是 42」。
#      → 正则必须容忍行尾注释。
#   ② $DIR_VENDOR = "$ROOT\_vendor" 会推出一个 leaf `_vendor`，那是**目录**，
#      拿它去替换文件名是错的 → 变量名以 ROOT / DIR_ 开头的直接跳过。
#   ③ 计数不是判据，**覆盖率**才是。结尾的 gate 会把「map 里有、代码里还留着」
#      的字面量全部点名。
# 规律：迁移类工具报「改了多少处」几乎必然掩盖「漏了多少处」。
#      报出来的必须是**没改完的清单**，不是改成了多少。
$map = @{}
foreach ($line in [IO.File]::ReadAllLines($pathsFile)) {
  # \s*(?:#.*)?$ —— 行尾注释必须容忍
  if ($line -match '^\$(?<var>\w+)\s*=\s*"\$(?:ROOT|DIR_\w+)(?<rest>.*?)"\s*(?:#.*)?$') {
    $var = $Matches['var']
    if ($var -match '^(ROOT|DIR_)') { continue }   # 目录不是文件
    $leaf = Split-Path $Matches['rest'] -Leaf
    if ($leaf -and -not $map.ContainsKey($leaf)) { $map[$leaf] = "`$$var" }
  }
}
# 映射表自己也得体检：_paths.ps1 里声明过「关键文件」的，缺一个就当场炸。
# 少一个的代价是静默的 —— 对应文件不会被替换，然后所有检查照样全绿。
$declaredLeaves = @()
foreach ($line in [IO.File]::ReadAllLines($pathsFile)) {
  if ($line -match '^\$(?<var>\w+)\s*=\s*"\$(?:ROOT|DIR_\w+)(?<rest>.*?)"\s*(?:#.*)?$') {
    if ($Matches['var'] -notmatch '^(ROOT|DIR_)') { $declaredLeaves += (Split-Path $Matches['rest'] -Leaf) }
  }
}
$mapMiss = @($declaredLeaves | Sort-Object -Unique | Where-Object { -not $map.ContainsKey($_) })
if ($mapMiss.Count -gt 0) {
  throw ("映射表自检失败：_paths.ps1 声明了 " + $declaredLeaves.Count + " 个文件，映射表里只有 " +
         $map.Count + " 个。缺: " + [string]::Join(' ', $mapMiss))
}
Write-Output ("从 _paths.ps1 推出 {0} 条映射（声明 {1} 个文件，缺 0）" -f $map.Count, $declaredLeaves.Count)

# ── 三行引导：往上找，搬目录时永远不用改 ─────────────────────
$BOOT = @(
  '$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p ''_paths.ps1''))) { $p = Split-Path $p -Parent }',
  'if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }',
  '. (Join-Path $p ''_paths.ps1'')'
)

$enc = New-Object Text.UTF8Encoding($true)   # 带 BOM：.ps1 通例
$script:replCount = 0

# ═══════════════════════════════════════════════════════════════
#  步骤② 单独抽成一个函数 Apply-Repl
# ═══════════════════════════════════════════════════════════════
# 为什么不能内联在主循环里：自检需要**独立**地把 ② 跑在原文件上，
# 拼出「这次编辑之后应该长什么样」，再和实际结果整体比。
# 只有把 ② 做成能对任意一组行调用的东西，这个比对才做得出来。
function Apply-Repl([string[]]$ls) {
  $out = New-Object System.Collections.ArrayList
  foreach ($l in $ls) {
    if ($l -match '^\s*#') { [void]$out.Add($l); continue }
    [void]$out.Add([regex]::Replace($l, "Join-Path \`$(dir|d|root) '([^']+)'", {
        param($m)
        $leaf = $m.Groups[2].Value
        if ($map.ContainsKey($leaf)) { $script:replCount++; return $map[$leaf] }
        return $m.Value
      }))
  }
  return , $out.ToArray()
}

# ═══════════════════════════════════════════════════════════════
#  自检函数 Test-Edited —— 第一版就是缺这一步
# ═══════════════════════════════════════════════════════════════
# 2026-10-01 第一版**把 24 个脚本改成了坏的，而且报告说「成功」**。
# 根因是这一行：
#      (@($BOOT) + "`$" + $name + ' = $ROOT') -join "`r`n"
# `+` 作用在**数组**上是追加元素，不是连接字符串。结果数组变成
# [boot0, boot1, boot2, '$', 'dir', ' = $ROOT']，join 出六行：
#      $
#      dir
#       = $ROOT
# 24 个脚本全成这个形状，然后它照样打了「共替换 23 处」。
#
# ⚠️ 最阴的地方：**Parser::ParseFile 判定这是合法 PowerShell**。`$` 是个
#    合法的 token，只是运行时报「找不到命令 '$'」。所以事后加一道
#    「语法体检」根本抓不到它 —— 只有真跑文件才会炸。
#    因此除了「整体等值」之外，还要有一条针对**行的形状**的判据。
#
# 查四件事：
#   ① 整体：结果必须和「① ② 都跑完之后应该长什么样」**逐行相等**
#   ② 裸变量行：整行只有一个 `$` 或 `$word`（就是本 bug 的直接产物）
#   ③ 插入块：必须和预期**逐行**相符（不能只是「数量对」）
#   ④ 解析：不能有语法错误
#
# ① 为什么是整体等值而不是「比头部 + 比尾部」：
#    只比尾部那版第一轮就误伤了 21 个文件 —— 步骤 ② 会**合法地**改掉尾部
#    几行，拿结果去和 ② 之前的原文比，当然对不上。
#    正确做法是把 ② 也套在原文上，再拼出完整的期望值整体比。
#    整体等值还顺手排除了「两处错误互相抵消」这种 diff 看不出来的情况。
function Test-Edited([string[]]$new, [string[]]$expected, [int]$at, [string[]]$inserted) {
  $bad = @()

  $e1 = [string]::Join([char]10, @($new))
  $e2 = [string]::Join([char]10, @($expected))
  if ($e1 -ne $e2) {
    # 点名第一处不一样的行，否则「对不上」三个字等于没查
    $n = [Math]::Max($new.Count, $expected.Count)
    for ($i = 0; $i -lt $n; $i++) {
      $a = if ($i -lt $new.Count) { $new[$i] } else { '<无此行>' }
      $c = if ($i -lt $expected.Count) { $expected[$i] } else { '<无此行>' }
      if ($a -ne $c) { $bad += ("第 " + ($i + 1) + " 行对不上：实际 [" + $a + "] / 期望 [" + $c + "]"); break }
    }
  }

  for ($i = 0; $i -lt $new.Count; $i++) {
    if ($new[$i] -match '^\s*\$[A-Za-z_][A-Za-z0-9_]*\s*$' -or $new[$i] -match '^\s*\$\s*$') {
      $bad += ("第 " + ($i + 1) + " 行是裸变量行: [" + $new[$i] + "]")
    }
  }

  $n2 = $inserted.Count
  $gotIns = @(); for ($k = $at; $k -lt $at + $n2; $k++) { $gotIns += $new[$k] }
  if ([string]::Join([char]10, $gotIns) -ne [string]::Join([char]10, @($inserted))) {
    $bad += '插入块内容与预期不符'
  }

  $errs = $null
  [System.Management.Automation.Language.Parser]::ParseInput($e1, [ref]$null, [ref]$errs) | Out-Null
  if ($errs -and $errs.Count -gt 0) { $bad += ("解析失败: " + $errs[0].Message) }
  return $bad
}

# ── 自检自身的反查：恒过的检查等于没有检查 ─────────────────────
# 喂五个样本。对的**一条都不许报**，坏的**必须点名具体毛病**：
#   ① 正确结果             → 0 条
#   ② 第一版的 bug 原样注入 → 必须点名「裸变量行」
#   ③ 尾部被改             → 必须点名「第 7 行对不上」
#   ④ 头部被改             → 必须点名「第 1 行对不上」
#   ⑤ 引导少插一行         → 必须点名「第 5 行对不上」
# 只测 ① 的话，一把永远说「没事」的尺子也能过；只测 ② 的话，③④⑤ 恒过了也不知道。
# 点名是关键：只报「有问题」的话，别的错也会触发，同样抓不到真问题。
# ⚠️ 探针里那个文件名**运行时才取**（从 $APP 推叶子），不写字面量 ——
#    写了 checks\_pathcheck.ps1 就会把本文件自己报成一处硬编码。
#    一份能测出别人问题的工具，不该自己先犯规。
$probeLeaf  = Split-Path $APP -Leaf
$probeOrig = @('param()', '$ErrorActionPreference = ''Stop''', '$dir = ''E:\x''', ('$t = Join-Path $dir ' + [char]39 + $probeLeaf + [char]39))
$probeIns  = @($BOOT) + @('$dir = $ROOT')
# 正确结果长这样（7 行）：原头 2 行 + 引导 4 行 + 原尾 1 行
$probeGood = @($probeOrig[0..1]) + $probeIns + @($probeOrig[3..3])
$cases = @(
  @{ n = '① 正确结果';        v = $probeGood; mustNot = @() },
  @{ n = '② 第一版 bug 注入'; v = @($probeOrig[0..1]) + $BOOT + @('$', 'dir', ' = $ROOT') + @($probeOrig[3..3]); mustNot = @('第 6 行对不上', '裸变量行') },
  @{ n = '③ 尾部被改';        v = @($probeOrig[0..1]) + $probeIns + @('$t = 2'); mustNot = @('第 7 行对不上') },
  @{ n = '④ 头部被改';        v = @('$junk = 9') + $probeGood; mustNot = @('第 1 行对不上') },
  @{ n = '⑤ 引导少插一行';    v = @($probeOrig[0..1]) + @($BOOT[0], $BOOT[1], '$dir = $ROOT') + @($probeOrig[3..3]); mustNot = @('第 5 行对不上') }
)
foreach ($c in $cases) {
  $r = Test-Edited $c.v $probeGood 2 $probeIns
  $txt = [string]::Join('; ', @($r))
  if ($c.n -like '①*') {
    if ($r.Count -gt 0) { throw ("自检反查失败：正确的编辑结果被误判了 -> " + $txt) }
  }
  foreach ($m in $c.mustNot) {
    if ($txt -notlike ('*' + $m + '*')) { throw ("自检反查失败：" + $c.n + " 应该报 [" + $m + "]，实际: " + $txt) }
  }
  Write-Output ("  反查 " + $c.n + " → " + $r.Count + " 条: " + $(if ($txt) { $txt } else { '（干净）' }))
}
Write-Output '自检反查 OK：判据能放行正确的，也能点名第一版那个 bug、头尾被改、引导漏行'

# ═══════════════════════════════════════════════════════════════
#  主循环
# ═══════════════════════════════════════════════════════════════
$report = @()
$dead = @()

# 自己不在名单里：一次性工具不需要被自己改写（它跑完就要退休），
# 而且被自己改写之后就没法再重跑对照了。
# 排除名单**运行时算出来**，不写文件名字面量 ——
# checks\_pathcheck.ps1 扫全部脚本，而 '_refactor.ps1' 正是它认得的已知文件名，
# 这里写死就等于自己把自己报成一处硬编码。
$selfName = Split-Path $S_REFRACTOR -Leaf
$pathName = Split-Path $pathsFile -Leaf
$targets = Get-ChildItem $dir -Filter *.ps1 | Where-Object { $_.Name -notin @($pathName, $selfName) }

foreach ($f in $targets) {
  $lines = [IO.File]::ReadAllLines($f.FullName)
  $origLines = @($lines)
  $isComment = { param($s) $s -match '^\s*#' }

  # 幂等：已经插过引导的跳过，免得跑两遍就插两遍
  if ($lines -contains $BOOT[0]) {
    $report += [pscustomobject]@{ File = $f.Name; Boot = '已插入(跳过)'; Repl = 0; Left = '' }
    continue
  }

  # ── ① 头部：把绝对路径定义换成引导 ──
  # 统一用三段模型描述这次编辑，后面的拼接只有一处实现：
  #   位置 $firstIdx、吃掉 $consumed 个原行、换成 $newSeg 这一段
  #   A/B：替换 1 行              → ($i,      1, ins)
  #   C  ：param 里改 1 行 + 括号后插 → ($i, close-i+1, @($newHead) + ins)
  #   D  ：只插入，不替换          → ($idx+1,  0, ins)
  # ⚠️ $consumed 这一栏是踩出来的：形态 D 不替换任何行，尾部必须从
  #    $firstIdx 接而不是 $firstIdx+1。写成 +1 就少算一行，
  #    5 个文件被自检误伤。自检比实际更严是安全的，反过来才危险。
  $didBoot = $false; $firstIdx = -1; $consumed = 0; $newSeg = @()
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if (& $isComment $lines[$i]) { continue }

    # 形态 A/B：$dir = '...'  /  $dir  = '...'
    if ($lines[$i] -match '^\$(dir|d|root)\s*=\s*''E:\\') {
      $name = $Matches[1]
      # ⚠️ 赋值行必须做成**一个数组元素**（@("`$$name = `$ROOT")）。
      #    写成 @($BOOT) + "`$" + $name + ' = $ROOT' 就是把「拼字符串」
      #    当成「数组相加」，`+` 追加的是元素 —— 于是 `$` 单独成行、
      #    变量名单独成行、剩下的又单独成行，24 个脚本全被写坏。
      $newSeg = @($BOOT) + @("`$$name = `$ROOT")
      $firstIdx = $i; $consumed = 1
      $didBoot = $true
      break
    }

    # 形态 C：param(... [string]$Dir = 'E:\...' ...)
    if ($lines[$i] -match '^\s*\[string\]\$(Dir|Dir)\s*=\s*''E:\\') {
      # 引导必须插在 **param(...) 的右括号之后**。
      # 插在 param 里面会直接 SyntaxError（函数参数列表中缺少 ')'），
      # _deploy.ps1 和 _pages.ps1 两个文件当场就废了。
      $close = $i
      while ($close -lt $lines.Count -and $lines[$close].TrimEnd() -notmatch '\)\s*$') { $close++ }
      if ($close -ge $lines.Count) { break }   # 找不到右括号 → 交给人工
      $newHead = $lines[$i] -replace '\s*=\s*''E:\\[^'']*''', ''
      # ⚠️ 不能写 `$Dir = $ROOT`：_pagestest.ps1 会用 `-Dir <假目录>` 调它
      #    做反查（好目录/缺页/空页三种），无条件覆盖就等于把反查拆了 ——
      #    三个用例全都会去看真目录，2、3 两条必然假红。
      # $consumed 吃掉的是 i..close **整段**（包括 param 的右括号），
      # 所以右括号那一行必须**搬进 newSeg**，否则 `param(` 没了收尾 →
      # 「函数参数列表中缺少 ')'」，_deploy.ps1 和 _pages.ps1 当场废掉。
      $newSeg = @($newHead) + $origLines[($i + 1)..$close] + @('') + $BOOT + @('if (-not $Dir) { $Dir = $ROOT }')
      $firstIdx = $i; $consumed = $close - $i + 1
      $didBoot = $true
      break
    }
  }

  # 形态 D：完全没写绝对路径，但仍在仓库里 → 在 $ErrorActionPreference 之后插引导
  if (-not $didBoot) {
    $idx = 0..($lines.Count - 1) | Where-Object { $lines[$_] -match '^\$ErrorActionPreference' } | Select-Object -First 1
    if ($null -ne $idx) {
      $newSeg = @($BOOT)
      $firstIdx = $idx + 1; $consumed = 0
      $didBoot = $true
    }
  }

  if (-not $didBoot) {
    $report += [pscustomobject]@{ File = $f.Name; Boot = '未插入'; Repl = 0; Left = '（需人工看头几行）' }
    continue
  }

  # 按三段模型拼出实际结果（①）
  $n0 = $lines.Count
  $lines = @()
  if ($firstIdx -gt 0) { $lines += $origLines[0..($firstIdx - 1)] }
  $lines += $newSeg
  if ($firstIdx + $consumed -lt $n0) { $lines += $origLines[($firstIdx + $consumed)..($n0 - 1)] }

  # ── ② Join-Path $dir 'X'  →  $VAR ──
  $before = $script:replCount
  $lines = Apply-Repl $lines
  $repl = $script:replCount - $before

  # ── ③ 写盘之前先自检 —— 这正是第一版缺的那一步。被拒绝 = 一个字节都不写 ──
  #    期望值**独立构造**：把 ② 同样套在原文上，再按同一个三段模型拼。
  $orig2 = Apply-Repl $origLines
  $seg2  = Apply-Repl $newSeg
  $n1 = $orig2.Count
  $expected = @()
  if ($firstIdx -gt 0) { $expected += $orig2[0..($firstIdx - 1)] }
  $expected += $seg2
  if ($firstIdx + $consumed -lt $n1) { $expected += $orig2[($firstIdx + $consumed)..($n1 - 1)] }

  $problems = Test-Edited $lines $expected $firstIdx $seg2
  if ($problems.Count -gt 0) {
    $dead += $f.Name
    $report += [pscustomobject]@{ File = $f.Name; Boot = '自检拒绝'; Repl = 0; Left = ([string]::Join(' | ', @($problems))) }
    continue
  }

  [IO.File]::WriteAllText($f.FullName, ([string]::Join($NL, $lines)), $enc)

  # ── ④ 报告：还剩哪些硬编码路径字面量（人工待办）──
  $left = @()
  $now = [IO.File]::ReadAllText($f.FullName)
  foreach ($mm in [regex]::Matches($now, "'([A-Za-z0-9_\-\.]+\.(?:ps1|html|json|mp3))'")) {
    $leaf = $mm.Groups[1].Value
    if ($map.ContainsKey($leaf)) {
      $ln = ($now.Substring(0, $mm.Index) -split "`n").Count
      $src = (Get-Content $f.FullName)[$ln - 1]
      if ($src -notmatch '^\s*#' -and $src -notmatch '^\s*(//|\*)') { $left += $leaf }
    }
  }
  $report += [pscustomobject]@{ File = $f.Name; Boot = '已插入'; Repl = $repl; Left = ([string]::Join(' ', @($left | Sort-Object -Unique))) }
}

Write-Output ''
$report | Sort-Object File | ForEach-Object {
  "  {0,-20} 引导 {1}  替换 {2,2} 处  仍残留: {3}" -f $_.File, $_.Boot, $_.Repl, $(if ($_.Left) { $_.Left } else { '无' })
}
$total = ($report | Measure-Object -Property Repl -Sum).Sum
Write-Output ("共替换 {0} 处。" -f $total)

# ═══════════════════════════════════════════════════════════════
#  收尾闸门：覆盖率，不是计数
# ═══════════════════════════════════════════════════════════════
# 为什么必须单独一道：上面那个「共替换 N 处」是**计数**，不是判据。
# 第三轮踩出来的就是它 —— 映射表因为行尾注释少了 4 个 key，
# 于是 42 处该改的只改了 23 处，工具报「共替换 23 处」，
# 23 是个看着挺正常的数字，于是这件事就这么过去了。
#
# 这道闸门反过来问：**_paths.ps1 认得的文件名，代码里还有哪几处是硬写的？**
# 有就点名到「文件:行号」，退出码非 0。剩下 0 条才算这一阶段做完。
# 「不认得的字面量」（各脚本自己造的临时文件）不在射程内，
# 单独列出来当人工清单，不算失败。
#
# ⚠️ **第一版这闸门只认 `'名字.ext'` 这种光秃秃的叶子名**，
#    于是 `'_vendor\three149.min.js'` 这种**带目录前缀**的字面量
#    从它眼皮底下过去了（_build.ps1 就有一处）。所以现在匹配的是
#    `'任意前缀 + 叶子名'`，只拿**叶子名**去查表 —— 前缀是哪儿的不管，
#    只要文件是 _paths.ps1 认得的那个，就该走变量。
$stragglers = @()
$unknown = @()
$leafRx = [regex]"'(?:[^']*[\\/])?([A-Za-z0-9_\-\.]+\.(?:ps1|html|json|mp3|js|jpg))'"
foreach ($f in $targets) {
  $lines = [IO.File]::ReadAllLines($f.FullName)
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*#') { continue }
    foreach ($mm in $leafRx.Matches($lines[$i])) {
      $leaf = $mm.Groups[1].Value
      if ($leaf -eq '_paths.ps1') { continue }    # 引导本身必须写死这个名字
      $tag = ($f.Name + ':' + ($i + 1) + '  [' + $mm.Value + ']')
      if ($map.ContainsKey($leaf)) { $stragglers += $tag } else { $unknown += $tag }
    }
  }
}

if ($unknown.Count -gt 0) {
  Write-Output ''
  Write-Output ("以下 {0} 处字面量不在 _paths.ps1 认得的范围内（多为各脚本自造的临时文件，判为人工清单，不算失败）：" -f $unknown.Count)
  $unknown | ForEach-Object { Write-Output ("    " + $_) }
}

if ($stragglers.Count -gt 0) {
  Write-Output ''
  Write-Output ("########## 还有 {0} 处硬写的已知文件名没收口（必须改掉）##########" -f $stragglers.Count)
  $stragglers | ForEach-Object { Write-Output ("  ! " + $_) }
  exit 1
}
Write-Output ''
Write-Output '########## 覆盖率闸门通过：_paths.ps1 认得的文件名，代码里一处硬写的都没有了 ##########'

# ⚠️ 被自检拒绝的文件 = **一个字节都没写**。这不是「跳过」，是失败。
#   第一版就是在这里若无其事地打了「共替换 23 处」，然后留下 24 个坏文件。
#   退出码必须非 0，否则调用方会把它记成成功。
if ($dead.Count -gt 0) {
  Write-Output ''
  Write-Output ("########## {0} 个文件被自检拒绝（未写入，需人工处理）##########" -f $dead.Count)
  $dead | ForEach-Object { Write-Output ("  - " + $_) }
  exit 1
}
