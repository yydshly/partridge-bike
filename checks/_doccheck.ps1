param(
  # 文档所在目录。默认 $ROOT，**但反查必须能对着别的目录跑** ——
  # 写在 _checkall.ps1 里的话就没法测「注入一条假路径会不会红」，
  # 跟 _pages.ps1 必须能对着任意 $Dir 跑是同一个道理。
  [string]$Dir
)
$ErrorActionPreference = 'Stop'
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
if (-not $Dir) { $Dir = $ROOT }
Set-Location $Dir

# 文档漂移检查。
#
# 为什么要有这个：B 阶段把 47 个文件搬进了 8 个目录，而 AGENTS.md 最顶上那节
# 「构建」——每个 agent 开工先读的那一节——一个字都没跟着搬：
#   `powershell -File .\_build.ps1` 和 `-File .\_checkall.ps1` 两条命令**照抄就报错**，
#   步数写着 16（当时已经 18），源码大小写着 ~100 KB（实际 252 KB）。
# 而没有任何检查会读文档，所以它能一路静默地漂完一整个阶段。
#
# 查五件事，每一条都点名到文件和行：
#   ① 文档里 `-File <路径>` 的路径**真实存在**（照抄会不会报错）
#   ② 文档里声明的**总步数** == _checkall.ps1 实际的 Step 条数
#   ③ 文档里写的产物文件数 == _paths.ps1 认得的产物数
#   ④ 文档里点名的 `dist\` 产物文件名，_paths.ps1 全部认得（不许有幻觉文件名）
#   ⑤ LICENSE 文件在不在，和 README 里的声明**一致**（不一致就是有一份过期了）
#
# ⚠️ ②③ 只查「总数声明」，**不查「第 N 步」**：
#    AGENTS.md 里有一堆「第 17 步」「4/15、5/15 步」，那些是**当时**的事，
#    是历史记录，写得对。判据一视同仁地去抓它们，报出来的全是假红，
#    报红的东西一旦没人信，这条判据就等于没有。

$bad = 0
function Bad($file, $line, $tag, $msg){
  Write-Output ("  {0}  {1}:{2}  {3}" -f $tag, $file, $line, $msg)
  $script:bad++
}
function LineNo($txt, $idx){
  $n = 1
  for ($i = 0; $i -lt $idx -and $i -lt $txt.Length; $i++){ if ($txt[$i] -eq "`n") { $n++ } }
  return $n
}

$docs = @($README, $AGENTS)
$docTxt = @{}
foreach ($f in $docs){
  $fp = Join-Path $Dir ([IO.Path]::GetFileName($f))
  if (-not (Test-Path $fp)) { Bad ([IO.Path]::GetFileName($f)) 0 'MISSING' "文档不在 $Dir（找不到）"; continue }
  $docTxt[$fp] = [IO.File]::ReadAllText($fp)
}
if ($docTxt.Count -eq 0) { Write-Output '  → 一份文档都没找到'; exit 1 }

# ── ① 文档里每条 -File 命令的路径都必须存在 ────────────────────
# 抓的是「照抄就报错」：B 阶段之后 AGENTS.md 里的 .\_build.ps1 / .\_checkall.ps1
# 两条都指到了根目录，而文件已经在 tools\ 和 checks\ 下了。
foreach ($fp in $docTxt.Keys){
  $name = [IO.Path]::GetFileName($fp)
  $txt  = $docTxt[$fp]
  # ⚠️ 括号不能少。少了它 $m.Groups[1].Value 恒为空串，
  #    于是 $full 算成仓库根目录、Test-Path 永远为真 —— 这条判据
  #    **永远不会红**。它第一版就是这样：跑出来「9 处漂移」很有气势，
  #    唯独 ① 那条一次都没响，而 ① 才是这个检查最值钱的一条。
  #
  # ⚠️ 路径按 **$ROOT** 解析，不按 $Dir。$Dir 只管「文档从哪儿读」——
  #    反查要把真文档复制到临时目录再注入坏内容，那里除了两个 md 什么也没有。
  #    文档里写的命令当然是在仓库根执行的，拿临时目录去解析它的话，
  #    好文档会凭空报四条 CMDPATH（反查第 1 条当场抓到的就是这个）。
  foreach ($m in [regex]::Matches($txt, '-File\s+(\.[\\/][^\s`''"）]+?\.ps1)')){
    $rel  = $m.Groups[1].Value -replace '/', '\'
    $full = Join-Path $ROOT ($rel.TrimStart('.\'))
    if (-not (Test-Path -LiteralPath $full)){
      Bad $name (LineNo $txt $m.Index) 'CMDPATH' ("文档里的命令 `-File $rel` 指向不存在的文件（照抄会报错）")
    }
  }
}

# ── ② 文档声明的总步数 == _checkall.ps1 实际的 Step 条数 ───────
$caFull = $S_CHECKALL
$caLocal = Join-Path $Dir ([IO.Path]::GetFileName($caFull))
if (-not (Test-Path -LiteralPath $caLocal)) { $caLocal = $caFull }
$ca = [IO.File]::ReadAllText($caLocal)
$steps = ([regex]::Matches($ca, "(?m)^Step\s+'")).Count
foreach ($fp in $docTxt.Keys){
  $name = [IO.Path]::GetFileName($fp)
  $txt  = $docTxt[$fp]
  foreach ($m in [regex]::Matches($txt, '(\d+)\s*步')){
    # 跳过「第 17 步」「4/15、5/15 步」这类**指某一具体步**的说法：
    # 那是历史记录，当时就是那个号，不是对当前总数的声明。
    $pre = $txt.Substring([Math]::Max(0, $m.Index - 14), [Math]::Min(14, $m.Index))
    if ($pre -match '第\s*$' -or $pre -match '[\d/、]\s*$') { continue }
    if ([int]$m.Groups[1].Value -ne $steps){
      Bad $name (LineNo $txt $m.Index) 'STEPS' ("文档写 $($m.Groups[1].Value) 步，_checkall.ps1 实际 $steps 步（只查总数声明，「第 N 步」是历史记录，不查）")
    }
  }
}

# ── ③ 文档写的产物个数 == _paths.ps1 认得的产物数 ─────────────
# 产物清单**从 _paths.ps1 的变量反推**，不在本文件里抄一遍 ——
# 抄一遍就是第二个会过期的地方，而过期的后果是「该查的没查」。
# ⚠️ 只收「值是 .html 路径」的变量：$OUT_NAMES（数组）和 $OUT_TOKENS（哈希表）
#    也叫 OUT_*，照样匹配这个通配符。照单全收的话判据会把自己算进去
#    （13 = 11 个真产物 + 这两个），然后 README 写 11 反而被判红。
#    又是一条「判据自己先犯规」。
$outLeaves = @()
Get-Variable -Name 'OUT_*' -ErrorAction SilentlyContinue | ForEach-Object {
  $v = [string]$_.Value
  # 三个条件缺一不可：① 以 .html 结尾 ② 含目录分隔符（排掉 $OUT_PROBE_* 那种
  # 光秃秃的文件名）③ 不含空白（排掉 $OUT_NAMES，它是数组，[string] 之后被
  # 拼成一长串，正好以 .html 结尾 —— 第一次写只判了 ①，产物数凭空多 1，
  # README 写 11 会被判红）。判据把自己算进去，是最难发现的一种错。
  if ($v -match '\.html$' -and $v -match '[\\/]' -and $v -notmatch '\s') {
    $outLeaves += [IO.Path]::GetFileName($v)
  }
}
$outLeaves += [IO.Path]::GetFileName($PRODUCT)
$outLeaves = @($outLeaves | Sort-Object -Unique)
$outCount  = $outLeaves.Count
foreach ($fp in $docTxt.Keys){
  $name = [IO.Path]::GetFileName($fp)
  $txt  = $docTxt[$fp]
  foreach ($m in [regex]::Matches($txt, '(\d+)\s*个产物')){
    if ([int]$m.Groups[1].Value -ne $outCount){
      Bad $name (LineNo $txt $m.Index) 'PRODNUM' ("文档写 $($m.Groups[1].Value) 个产物，_paths.ps1 认得 $outCount 个（判据认得：$($outLeaves.Count) 个产物变量 + 成品）")
    }
  }
}

# ── ④ 文档里点名的 dist\ 产物，_paths.ps1 全部认得 ────────────
# 比较不用 -contains，逐个 -ieq。倒不是因为 -contains 有问题（这个坑查了半天
# 最后是我自己在调试行里数错了字符数），而是这条判据一旦报红，报错信息里必须
# **同时带上文档那边的和清单那边的长度**：两边都是 17 还是 16，决定了是
# 「文档写错了」还是「清单算错了」，这是两种完全不同的修法。
foreach ($fp in $docTxt.Keys){
  $name = [IO.Path]::GetFileName($fp)
  $txt  = $docTxt[$fp]
  foreach ($m in [regex]::Matches($txt, 'dist\\([A-Za-z0-9_\-]+\.html)')){
    $leaf = ([string]$m.Groups[1].Value)
    $hit = $false; $cand = ''
    foreach ($o in $outLeaves){
      if (([string]$o).StartsWith($leaf.Substring(0,3))) { $cand = [string]$o }
      if ([string]$o -ieq $leaf) { $hit = $true; break }
    }
    if (-not $hit){
      $msg = 'doc=[' + $leaf + '] codes=' + (($leaf.ToCharArray() | ForEach-Object { [int]$_ }) -join ',')
      Bad $name (LineNo $txt $m.Index) 'PHANTOM' $msg
    }
  }
}

# ── ⑤ LICENSE 文件在不在，和 README 的声明必须一致 ────────────
# 2026-10-01 的决定是**不加 LICENSE**（保留所有权利）。决定本身没问题，
# 问题在于「决定不加」和「忘了加」在访客眼里**长得一模一样** ——
# 两种情况下仓库根目录都是空的。所以必须有一份写下来的声明，
# 把它从疏漏变成决定；判据再钉住「声明 ↔ 文件」两边不许各说各话。
#
# 四种组合，只有两种自洽：
#   没文件 + 写了「保留所有权利」   → 自洽（这是明写的决定）
#   有文件 + 没写「保留所有权利」   → 自洽（README 跟着文件走）
#   没文件 + 没写                  → 报红（看起来像忘了加）
#   有文件 + 还写着「保留所有权利」 → 报红（两份自相矛盾，总有一份是过期的）
# 只查第三种的话，「后来补了 LICENSE 却忘了改 README」这种就漏了。
#
# ⚠️ LICENSE 按 **$Dir** 解析（文档从哪儿读，它就从哪儿读），不按 $ROOT：
#    反查要把 README/AGENTS 复制到临时目录，再往那个目录里放/拿掉一个
#    LICENSE 文件。按 $ROOT 解析的话那个文件永远看不见，
#    第 4、5 两条反查就都是恒过的 —— 判据能对着真仓库跑，不等于它抓得住。
$licExists = Test-Path -LiteralPath (Join-Path $Dir 'LICENSE')
$rdName = [IO.Path]::GetFileName($README)
$rdTxt = ''
foreach ($k in $docTxt.Keys) { if ([IO.Path]::GetFileName($k) -eq $rdName) { $rdTxt = [string]$docTxt[$k] } }
$declaresNone = ($rdTxt -match '保留所有权利' -or $rdTxt -match '未选择许可证')
if (-not $licExists -and -not $declaresNone) {
  Bad $rdName 0 'LICENSE' '没有 LICENSE 文件，README 也没写明「保留所有权利」—— 对访客来说这不是一个决定，看起来是忘了加'
} elseif ($licExists -and $declaresNone) {
  Bad $rdName 0 'LICENSE' 'README 写着「保留所有权利」，但同一个目录里已经有 LICENSE 文件了 —— 两边自相矛盾，总有一份是过期的'
}

Write-Output ("  文档 {0} 份 · 产物清单 {1} 个 · _checkall 实际 {2} 步 · LICENSE {3}" -f $docTxt.Count, $outCount, $steps,
  $(if ($licExists) { '有文件' } elseif ($declaresNone) { '无文件，README 已写明保留所有权利' } else { '无文件且未声明' }))
if ($bad -gt 0) {
  Write-Output ("  → {0} 处文档漂移（照抄会报错 / 数字过期 / 文件名是幻觉 / 许可声明与文件矛盾）" -f $bad)
  exit 1
}
Write-Output '  文档没有漂：命令路径都在、步数对得上、产物名都认得、许可声明和 LICENSE 文件一致。'
exit 0
