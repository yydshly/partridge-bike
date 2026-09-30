param(
  [string]$Dir
)

$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
if (-not $Dir) { $Dir = $ROOT }
# 清点 harness 页面：该在的页在不在、里面还有没有断言。
#
# 为什么单独拆出来：这一段一旦写在 _checkall.ps1 里，就**验不到它自己** ——
# 想测「缺页会不会红」，得先把一页挪走，可第 9 步 _mkroute.ps1 会立刻把它
# 重新生成出来，挪了等于没挪。所以它必须能对着一个任意的 $Dir 跑。
#
# 只报能从文件本身验出来的东西，不报「条数」：
#   静态调用点数 ≠ 运行时条数（_moodharness 调用点 137、运行时 448，循环会展开）。
# 真条数的唯一权威是页面跑起来以后 document.title 上的 `PASS n/m`。
$ErrorActionPreference = 'Stop'
# 页名不再在本文件里抄一遍 —— 唯一出处是 _paths.ps1 的 $OUT_NAMES。
# 原来这里硬写七行，加一页忘了加就等于那一页**永远不被清点**，
# 而输出看着完全正常（少一行而已，看不出来）。
$bad = 0
$pages = @()
foreach ($n in $OUT_NAMES) {
  $pages += @{ f = $n; c = $(if ($OUT_TOKENS.ContainsKey($n)) { $OUT_TOKENS[$n] } else { 'ok' }) }
}
# 记号表里有 $OUT_NAMES 里没有的页 = 页被改名/删除过但记号表没清
$orphan = @($OUT_TOKENS.Keys | Where-Object { $OUT_NAMES -notcontains $_ })
if ($orphan.Count -gt 0) { throw ("记号表和 `$OUT_NAMES 对不上：" + [string]::Join(' ', $orphan)) }
foreach ($pg in $pages) {
  $fp = Join-Path $Dir $pg.f
  if (-not (Test-Path $fp)) {
    Write-Output ("  MISSING  {0}  ← 生成器没跑，或跑失败了" -f $pg.f)
    $bad++
    continue
  }
  $txt = [IO.File]::ReadAllText($fp)
  # 行首匹配：注释里出现的 `ok(` 不会算进来（注释不占行首的调用形态）
  $n = ([regex]::Matches($txt, ('(?m)^\s*' + [regex]::Escape($pg.c) + '\('))).Count
  # 反查按**不同的圈号**去重：`反查 ①b` 和 `反查 ①` 是同一条的变体，
  # 直接数匹配会把 7 条数成 10 条 —— 又是一个「看着像那么回事」的数。
  $marks = [regex]::Matches($txt, '反查\s*([①-⑳])') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
  $rev = @($marks).Count
  if ($n -eq 0) {
    # 页在，但一条断言都没有 —— 比缺页更阴：页面照样打开、标题照样变 PASS 0/0
    Write-Output ("  EMPTY    {0}  ← 文件在，但没有任何 {1}( 断言调用点" -f $pg.f, $pg.c)
    $bad++
    continue
  }
  # 页面必须把真条数写进标题。
  # 为什么这是硬要求：_checkall 收尾让人「打开 _*.html 看标题 PASS n/m」，
  # 而这是**唯一**能拿到真条数的地方（静态调用点数 ≠ 运行时条数，循环会展开）。
  # 2026-10-01 实测：七套里有三套（drive/traffic/route）压根没写这一行，
  # 那条指令对它们是**假的**，而没有任何检查发现。已补上，这里钉住。
  if ($txt -notmatch 'document\.title\s*=') {
    Write-Output ("  NOTITLE  {0}  ← 页面没有把真条数写进标题，「看标题 PASS n/m」这条指令对它是假的" -f $pg.f)
    $bad++
    continue
  }
  Write-Output ("  {0,-18} {1,4} 个断言调用点{2}" -f $pg.f, $n, $(if ($rev -gt 0) { "（含 $rev 条反查）" } else { '' }))
}
if ($bad -gt 0) {
  Write-Output ("  → {0} 个页面不合格" -f $bad)
  exit 1
}
Write-Output '  ↑ 调用点个数，不是条数（循环会展开）。真条数看页面标题 PASS n/m。'
exit 0