param(
  [string]$Dir = 'E:\minimax_code_project\0929_project\partridge-bike'
)
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
$pages = @(
  @{ f='_driveharness.html';    c='ok'  },
  @{ f='_trafficharness.html';  c='ok'  },
  @{ f='_routeharness.html';    c='ok'  },
  @{ f='_moodharness.html';     c='ok'  },
  @{ f='_cruiseharness.html';   c='ok'  },
  @{ f='_moodstate.html';       c='ok'  },
  @{ f='_uistate.html';         c='uok' }
)
$bad = 0
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
  Write-Output ("  {0,-18} {1,4} 个断言调用点{2}" -f $pg.f, $n, $(if ($rev -gt 0) { "（含 $rev 条反查）" } else { '' }))
}
if ($bad -gt 0) {
  Write-Output ("  → {0} 个页面不合格" -f $bad)
  exit 1
}
Write-Output '  ↑ 调用点个数，不是条数（循环会展开）。真条数看页面标题 PASS n/m。'
exit 0
