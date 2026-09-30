# 检查器的反查：恒过的检查等于没有检查。
# 造一份**已知坏**的 harness（引用一个没定义的东西），要求 lint 抓到它；
# 再造一份正常的，要求 lint 放过。两边都对了才说明这把尺子准。
$ErrorActionPreference = 'Stop'
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
$dir = $ROOT
$tmp = Join-Path $dir '_linttest.html'
$lint = $S_LINT
$fail = 0

function Run-Lint($p) {
  # ⚠️ 必须临时把 ErrorActionPreference 降下来：lint 报告失败时会往 stderr
  # 写 throw 的正文，而 `$ErrorActionPreference='Stop'` + 原生命令 stderr
  # 在 PowerShell 里会直接变成 terminating error，脚本当场停住 ——
  # 根本走不到「看退出码」那一步。反查自己先崩了。
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $lint -Path $p 2>&1
  $code = $LASTEXITCODE
  $ErrorActionPreference = $old
  return @{ code = $code; out = ($o -join "`n") }
}

$cases = @(
  @{ name = '坏样本：调用了没定义的 cruiseTick（就是驾驶 harness 那个真 bug）'
     js   = 'const S={};function drive(dt){ S.steerIn = S.cruise ? cruiseTick(dt) : 0; } drive(1);'
     want = 1 }
  @{ name = '坏样本：漏了 layoutRider（车流 harness 切错对象那类）'
     js   = 'const L=[];function t(){ RIDERS.forEach(r => layoutRider(r, false)); } t();'
     want = 1 }
  @{ name = '好样本：定义齐全，不该报'
     js   = 'const RIDERS=[];function layoutRider(r,f){ return r; } RIDERS.forEach(r => layoutRider(r,false));'
     want = 0 }
  @{ name = '好样本：对象字面量方法简写不算悬空调用'
     js   = 'const cap={ set innerHTML(v){ this.v=v; }, get text(){ return this.v; } }; cap.innerHTML=1; cap.text;'
     want = 0 }
  @{ name = '好样本：箭头函数裸参数 + 模板字面量 + 三方内置'
     js   = 'const a=[1,2]; const s=`rgba(1,2,3,${a.length})`; const b=new Float32Array(3); b.set(a); s+b.length;'
     want = 0 }
)

foreach ($c in $cases) {
  $html = "<!DOCTYPE html><html><head><meta charset=`"utf-8`"></head><body><script>`r`n" + $c.js + "`r`n</script></body></html>"
  [IO.File]::WriteAllText($tmp, $html, (New-Object Text.UTF8Encoding($false)))
  $r = Run-Lint $tmp
  $ok = ($r.code -eq $c.want)
  if (-not $ok) { $fail++ }
  Write-Output ("  {0}  {1}" -f $(if($ok){'PASS'}else{'FAIL'}), $c.name)
  if (-not $ok) {
    Write-Output ("        期望退出码 {0}，实际 {1}" -f $c.want, $r.code)
    Write-Output ("        " + ($r.out -replace "`r?`n", ' | '))
  }
}

# ═══ 第二组反查：**退出码有没有传出去** ═══
#
# 2026-09-30 真正漏掉的就是这一层，lint 本身判对了、也确实返回了 1，
# 但六个 _mk*.ps1 都把 lint 当最后一句、跑完正常结束就返回 0，
# 于是 _checkall 看到的一律是「通过」。真实后果：_moodharness 整页抛
# `ReferenceError: paintBirdBtn is not defined`，448 条断言一条没跑，
# 页面停在「running…」，而全量检查是绿的。
#
# 这组用「把 lint 换成一个必失败的替身」来验传播：生成器跑完必须非 0。
# 只验「lint 判得对」是不够的 —— 判对了但没人听见，等于没判。
$ErrorActionPreference = 'Continue'
$realLint = [IO.File]::ReadAllText($lint)
$propResults = @()
# 六个生成器的真实路径。**只在这里定义一次** ——
# 原来下面两个循环各抄一遍文件名，抄漏一个就会让「退出码传播」只验到 5 个，
# 而输出那一栏看着照样是一排 PASS。
$gens = @($S_MKMOODSTATE, $S_MKROUTE, $S_MKCRUISE, $S_MKTRAFFIC, $S_MKDRIVE, $S_MKMOOD)
try {
  # 替身：无条件退出 1，什么都不检查
  [IO.File]::WriteAllText($lint, "exit 1`r`n", (New-Object Text.UTF8Encoding($true)))
  foreach ($gen in $gens) {
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $gen 2>&1
    $code = $LASTEXITCODE
    $propResults += @{ gen = $gen; code = $code; out = ($o -join "`n") }
  }
} finally {
  [IO.File]::WriteAllText($lint, $realLint, (New-Object Text.UTF8Encoding($true)))
}
# 替身期间生成出来的 harness 可能是坏的（lint 被换掉了）→ 全部重新生成一遍
foreach ($gen in $gens) {
  $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $gen 2>&1
}
Write-Output '=== 退出码传播：lint 必失败时，生成器必须非 0 ==='
foreach ($p in $propResults) {
  $ok = ($p.code -ne 0)
  if (-not $ok) { $fail++ }
  Write-Output ("  {0}  {1,-18} 退出码 {2}（必须 ≠0）" -f $(if($ok){'PASS'}else{'FAIL'}), (Split-Path $p.gen -Leaf), $p.code)
  if (-not $ok) { Write-Output ('        ' + ($p.out -replace "`r?`n", ' | ')) }
}

# 反查的反查：造一份**故意不传退出码**的生成器（就是修之前的写法），
# 上面的判据必须判它 FAIL。否则这一整组就是恒过的假绿 ——
# 「六个都返回 1」也可能只是因为无论写什么都返回 1。
$ErrorActionPreference = 'Continue'
$noProp = Join-Path $dir '_mknoprop.ps1'
$srcG = [IO.File]::ReadAllText(($S_MKROUTE))
$srcG = [regex]::Replace($srcG, '(?m)^exit \$LASTEXITCODE\s*$', '')
if ($srcG -eq [IO.File]::ReadAllText(($S_MKROUTE))) {
  Write-Output '  FAIL  没能在 _mkroute.ps1 里找到 exit $LASTEXITCODE 这一行（写法变了？反查失效）'
  $fail++
}
[IO.File]::WriteAllText($noProp, $srcG, (New-Object Text.UTF8Encoding($true)))
try {
  [IO.File]::WriteAllText($lint, "exit 1`r`n", (New-Object Text.UTF8Encoding($true)))
  $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $noProp 2>&1
  $npCode = $LASTEXITCODE
} finally {
  [IO.File]::WriteAllText($lint, $realLint, (New-Object Text.UTF8Encoding($true)))
  if (Test-Path $noProp) { mavis-trash $noProp }
  $null = & powershell -NoProfile -ExecutionPolicy Bypass -File ($S_MKROUTE) 2>&1
}
$npOk = ($npCode -eq 0)   # 期望它**就是 0**（不传播），这样判据才会判 FAIL
if (-not $npOk) { $fail++ }
Write-Output (("  {0}  反查的反查：删掉 exit 的生成器退出码 {1}（期望 0，即「不传播」）——" +
               "只有它真的是 0，上面那组判据才不是恒过的") -f $(if($npOk){'PASS'}else{'FAIL'}), $npCode)

if (Test-Path $tmp) { Remove-Item $tmp -Force }
if ($fail -gt 0) { Write-Output ("lint 反查 {0} 项不对" -f $fail); exit 1 }
Write-Output 'lint 反查成立：坏样本抓得住，好样本不误伤'