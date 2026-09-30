# _syntaxcheck 的反查：恒过的检查等于没有检查。
# 两头都要验：① 拿**真源码**的坏副本（把自动巡航那段说明的 */ 加回去）
#            —— 就是 2026-09-30 实际发生的那次 —— 要求它 FAIL；
#          ② 拿修好的真源码，要求它 PASS。
# 只验 ② 的话，一把永远说「没事」的尺子也能过。
$ErrorActionPreference = 'Stop'
$dir  = 'E:\minimax_code_project\0929_project\partridge-bike'
$tool = Join-Path $dir '_syntaxcheck.ps1'
$src  = Join-Path $dir '_app3d.html'
$bad  = Join-Path $dir '_synbad.html'
$fail = 0

function Run-Syn($p) {
  # lint 那次踩过：ErrorActionPreference='Stop' + 原生命令 stderr 会直接
  # 把脚本打死，反查自己先崩。这里必须先降下来再看退出码。
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $tool -Path $p 2>&1
  $code = $LASTEXITCODE
  $ErrorActionPreference = $old
  return @{ code = $code; out = ($o -join "`n") }
}

# ---- 1) 真源码的坏副本：把 ① 小节末尾的注释闭合符塞回去 ----
$t = [IO.File]::ReadAllText($src)
$anchor = '      两个都正比会一直绕圈；两个都反比会直接飞出去。'
if ($t.IndexOf($anchor) -lt 0) { throw 'anchor not found — 注释结构变了，反查样本构造不了了' }
# 只改第一次出现（① 小节那处），② 小节末尾那个 */ 保持原样 ⇒ 多出来一个 */
$t = $t.Replace($anchor, $anchor + ' */')
[IO.File]::WriteAllText($bad, $t, (New-Object Text.UTF8Encoding($false)))
$r1 = Run-Syn $bad
$ok1 = ($r1.code -eq 1)
Write-Output ("  {0}  坏副本（就是真源码 + 提前闭合的 */）必须 FAIL" -f $(if($ok1){'PASS'}else{'FAIL'}))
if (-not $ok1) { Write-Output ("        实际退出码 {0}：{1}" -f $r1.code, $r1.out) }

# ---- 2) 修好的真源码 ----
$r2 = Run-Syn $src
$ok2 = ($r2.code -eq 0)
Write-Output ("  {0}  修好的真源码必须 PASS" -f $(if($ok2){'PASS'}else{'FAIL'}))
if (-not $ok2) { Write-Output ("        " + ($r2.out -replace "`r?`n", ' | ')) }

# ---- 3) 另外两种坏法：字符串没闭合、块注释拖到文件尾 ----
$mini = @'
<!DOCTYPE html><html><body><script>
const s = 'abc
/* 开了没关
</script></body></html>
'@
[IO.File]::WriteAllText($bad, $mini, (New-Object Text.UTF8Encoding($false)))
$r3 = Run-Syn $bad
$ok3 = ($r3.code -eq 1)
Write-Output ("  {0}  字符串没闭合也要 FAIL" -f $(if($ok3){'PASS'}else{'FAIL'}))
if (-not $ok3) { Write-Output ("        " + ($r3.out -replace "`r?`n", ' | ')) }

if (Test-Path $bad) { Remove-Item $bad -Force }
if ($ok1 -and $ok2 -and $ok3) {
  Write-Output 'syntax 检查成立：坏样本抓得住，好源码不误伤'
  exit 0
}
$fail = 1
Write-Output 'syntax 反查失败'
exit 1
