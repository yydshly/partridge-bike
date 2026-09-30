param()
# 路径收口的**常驻**判据：_paths.ps1 认得的文件名，代码里一处硬写的都不能有。
#
# 为什么它必须常驻、而不是只活在 _refactor.ps1 里：
# 迁移工具是一次性的，它跑完就退休了。而「零处硬编码」这个不变量
# 会在**以后每一次**改动里被破坏 —— 有人新写一个脚本，里面
# `Join-Path $dir '_app3d.html'`，没有任何东西会响。
# 只在迁移时验过一次的，不叫检查，叫一次性观察。
#
# 它查三件事：
#   ① 硬编码：引号里的文件名凡是 _paths.ps1 认得的，都该走变量
#   ② 数据来源的路径：'Join-Path <根目录别名> <非字面量>' ——
#      静态判据 ① 看不见这类（_build.ps1 的 `Join-Path $dir $t.f`
#      就是，$t.f 来自 _bgm-meta.json，脚本里根本没有那个文件名字面量）
#   ③ 源有没有被 .gitignore 悄悄踢出版本库
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
$ErrorActionPreference = 'Stop'

# ── 从 _paths.ps1 自动推出「文件名 → 变量」映射 ──────────────
# ⚠️ 正则必须容忍行尾注释：`$APP = "..." # 唯一可编辑源` 这种行
#    曾经整条没进 map，于是 42 处只改了 23 处，而 23 看着挺正常。
# ⚠️ 变量名以 ROOT / DIR_ 开头的必须跳过 —— 那是**目录**。
#    $DIR_BGM = "$DIR_ASSETS\bgm" 会推出一个叫 bgm 的叶子，
#    拿它去替换「文件名 bgm」必然是错的；而 $THREE_LIB、
#    $OUT_DRIVE 这些是文件，必须收进来。区别在**变量名**，不在叶子名。
$map = @{}
$dirCount = 0
foreach ($line in [IO.File]::ReadAllLines((Join-Path $ROOT '_paths.ps1'))) {
  if ($line -match '^\$(?<var>\w+)\s*=\s*"\$(?:ROOT|DIR_\w+)(?<rest>.*?)"\s*(?:#.*)?$') {
    if ($Matches['var'] -match '^(ROOT|DIR_)') { $dirCount++; continue }
    $leaf = Split-Path $Matches['rest'] -Leaf
    if ($leaf -and -not $map.ContainsKey($leaf)) { $map[$leaf] = "`$$($Matches['var'])" }
  }
}
Write-Output ("_paths.ps1：{0} 个文件映射 + {1} 个目录定义" -f $map.Count, $dirCount)

# ── 扫所有 .ps1（跳过 dist/ 与 .git/）──────────────────────
$scripts = @(Get-ChildItem -LiteralPath $ROOT -Recurse -Filter '*.ps1' -File |
  Where-Object { $_.FullName -notlike "$ROOT\dist\*" -and $_.FullName -notlike "$ROOT\.git\*" })
Write-Output ("扫描 {0} 个脚本" -f $scripts.Count)

$stragglers = @()
$joins = @()
# ① 匹配「任意前缀 + 叶子名」：前缀是哪儿的不管，只拿叶子名去查表。
#   第一版只认光秃秃的 '^?名字.ext$'，于是 '_vendor\three149.min.js'
#   这种带目录前缀的字面量从它眼皮底下过去了。
$leafRx = [regex]"'(?:[^']*[\\/])?([A-Za-z0-9_\-\.]+\.(?:ps1|html|json|mp3|js|jpg))'"
foreach ($f in $scripts) {
  $rel = $f.FullName.Substring($ROOT.Length + 1)
  # _paths.ps1 **整份跳过**：它就是映射表本身，文件名字面量是它的职责
  # （$OUT_NAMES / $OUT_TOKENS / $OUT_PROBE_* 都必须按名字列出）。
  # 它自己的正确性由末尾那份 mustExist 自检保证（57 项存在性当场验）。
  if ($rel -eq '_paths.ps1') { continue }
  $lines = [IO.File]::ReadAllLines($f.FullName)
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ($line -match '^\s*#') { continue }
    foreach ($mm in $leafRx.Matches($line)) {
      $leaf = $mm.Groups[1].Value
      if ($leaf -eq '_paths.ps1') { continue }    # 引导那三行必须写死这个名字
      if ($map.ContainsKey($leaf)) { $stragglers += ("$rel`:$($i + 1)  " + $mm.Value) }
    }
    # ② 基准目录是「仓库根的别名」+ 第二个参数不是字面量。
    #    ⚠️ 这里**故意只认 $dir / $d，不认 $root**：
    #    tools\_serve.ps1 里的 `$root = $ROOT` 是**网页服务的 doc root**，
    #    它拼的是 URL 路径（`/dist/parridge-3d.html`），不是仓库里的文件路径，
    #    判它等于把判据变成噪音。而 `$root` 作**变量**在全仓库只出现在
    #    _serve.ps1 那三行，别处全是 `$ROOT`（那个规范变量）或字符串里的探针文本。
    foreach ($jm in [regex]::Matches($line, 'Join-Path\s+\$(dir|d)\s+([^\s''")]+)')) {
      $joins += ("$rel`:$($i + 1)  Join-Path `$$($jm.Groups[1].Value) " + $jm.Groups[2].Value)
    }
  }
}

$bad = 0
if ($stragglers.Count -gt 0) {
  $bad++
  Write-Output ("  ! {0} 处硬写的已知文件名（_paths.ps1 里已经有对应变量了）:" -f $stragglers.Count)
  $stragglers | ForEach-Object { Write-Output ("      " + $_) }
}
if ($joins.Count -gt 0) {
  $bad++
  Write-Output ("  ! {0} 处 'Join-Path <根目录别名> <非字面量>' —— 基准是仓库根，那个文件一搬走就断:" -f $joins.Count)
  $joins | ForEach-Object { Write-Output ("      " + $_) }
}

# ── ③ 源有没有被 .gitignore 悄悄踢出版本库 ──────────────────
# 这是**搬文件 / 改整目录 ignore** 之后唯一的兜底。
# 光看 git status 看不出来 —— 被忽略的文件根本没进索引，也就没什么「要删的」，
# 你只会觉得「怎么少了几十个文件」却查不出少了什么。
if (Test-Path -LiteralPath (Join-Path $ROOT '.git')) {
  $tracked = @(git -C $ROOT ls-files 2>$null)
  $hidden = @()
  foreach ($t in $tracked) {
    if (-not $t) { continue }
    git -C $ROOT check-ignore -q -- $t 2>$null
    if ($LASTEXITCODE -eq 0) { $hidden += $t }
  }
  if ($hidden.Count -gt 0) {
    $bad++
    Write-Output ("  ! {0} 个**已跟踪**的文件被 .gitignore 忽略了 —— 它们会被踢出版本库:" -f $hidden.Count)
    $hidden | ForEach-Object { Write-Output ("      " + $_) }
  } else {
    Write-Output ("  已跟踪文件里被 .gitignore 忽略的: 0 个（{0} 个已跟踪文件全部安全）" -f $tracked.Count)
  }
}

Write-Output ''
if ($bad -eq 0) {
  Write-Output '路径收口成立：_paths.ps1 认得的文件名，代码里一处硬写的都没有；源也没有被 ignore 踢掉。'
  exit 0
}
Write-Output ("pathcheck 失败 {0} 类" -f $bad)
exit 1
