param()
# _pages.ps1 的反查：喂它三种目录，它必须给出三种不同的答案。
#
# 为什么要专门做这一份：清点脚本天生容易**恒过** ——
#   ① 页名写错 / 路径拼错 → 一页都没找到，可循环压根没跑，照样 exit 0；
#   ② `if` 写反了 → 什么都不算失败；
#   ③ 只判存在不判内容 → 生成器切空了（PASS 0/0）也算合格。
# 三条都不是「读源码看不出来」的，必须真喂坏样本。
$ErrorActionPreference = 'Continue'
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
$dir = $ROOT
$ps  = $S_PAGES
$tmp = Join-Path $dir '_pagestest'

# 假的「好页面」内容：只保留清点脚本真正会看的两样东西 —— 断言调用点、反查标记
$good = "<html><body><script>`nconst ok=(c,n)=>R.push([c,n]);`nok(1,'a');`nok(0,'反查 ①:x','d');`ndocument.title='PASS 2/3';`n</script></body></html>"

function Reset-Tmp { param($mode, $which)
  if (Test-Path $tmp) { mavis-trash $tmp }
  $null = New-Item -ItemType Directory -Path $tmp -Force
  # 页名和记号都跟 _paths.ps1 走，不再在这儿抄一份七行 ——
  # 抄的那份和 _pages.ps1 里的那份**同时**过期的话，反查会拿着旧页名去测，
  # 测出来的 PASS 一点意义都没有（而它是绿的）。
  $map = @{}
  foreach ($n in $OUT_NAMES) { $map[$n] = $(if ($OUT_TOKENS.ContainsKey($n)) { $OUT_TOKENS[$n] } else { 'ok' }) }
  if ($map.Count -ne $OUT_NAMES.Count) { throw "假页面表和 `$OUT_NAMES 对不上（$($map.Count) vs $($OUT_NAMES.Count)）" }
  foreach ($k in $map.Keys) {
    $fn = Join-Path $tmp $k
    if ($mode -eq 'missing' -and $k -eq $which) { continue }   # 故意不生成 → 走 MISSING 分支
    $call = $map[$k]
    if ($mode -eq 'empty' -and $k -eq $which) {
      # 页在、打开也不报错、但一条断言都没有 → 页面标题会变成 PASS 0/0。
      # 这是比缺页更阴的一种：脚本自己看不出来，只能靠这里拦住。
      [IO.File]::WriteAllText($fn, "<html><body><script>const R=[];</script></body></html>", (New-Object Text.UTF8Encoding($false)))
      continue
    }
    [IO.File]::WriteAllText($fn, ($good -replace 'ok\(', ($call + '(')), (New-Object Text.UTF8Encoding($false)))
  }
}

$fail = 0
function Case { param($name, $mode, $which, $wantExit, $wantText)
  Reset-Tmp -mode $mode -which $which
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $ps -Dir $tmp 2>&1 | Out-String
  $code = $LASTEXITCODE
  $okExit = ($code -eq $wantExit)
  $okText = if ($wantText) { $out -match [regex]::Escape($wantText) } else { $true }
  $ok = $okExit -and $okText
  if (-not $ok) { $script:fail++ }
  Write-Output ("  {0}  {1}  (退出码 {2}，期望 {3}{4})" -f $(if($ok){'PASS'}else{'FAIL'}), $name, $code, $wantExit,
                $(if ($wantText) { "，输出里要有「$wantText」" } else { '' }))
  if (-not $ok) { Write-Output (($out.TrimEnd() -split "`n" | ForEach-Object { '        ' + $_ }) -join "`n") }
}

Write-Output '=== 1) 全都正常：必须 exit 0（好样本不误伤）==='
Case ("$($OUT_NAMES.Count) 页齐全、每页都有断言") 'ok' $null 0 ''

Write-Output '=== 2) 缺一页：必须 exit 1（这就是「恒过」的反查）==='
Case ("缺 $OUT_PROBE_MISSING") 'missing' $OUT_PROBE_MISSING 1 'MISSING'

Write-Output '=== 3) 页在但内容被切空：必须 exit 1（PASS 0/0 那种阴坏）==='
Case ("$OUT_PROBE_EMPTY 存在但零断言") 'empty' $OUT_PROBE_EMPTY 1 'EMPTY'

Write-Output '=== 4) 注释里的 ok( 不该被当成断言（不误伤）==='
Reset-Tmp -mode 'ok' -which $null
[IO.File]::WriteAllText((Join-Path $tmp $OUT_PROBE_COMMENT),
  "<html><body><script>`n// ok( 这行是注释，不算断言`n/* ok( 这行也是 */`nok(1,'只有这条是真的');`ndocument.title='PASS 1/1';`n</script></body></html>",
  (New-Object Text.UTF8Encoding($false)))
$out4 = & powershell -NoProfile -ExecutionPolicy Bypass -File $ps -Dir $tmp 2>&1 | Out-String
$code4 = $LASTEXITCODE
$ok4 = ($code4 -eq 0) -and ($out4 -match '1 个断言调用点')
if (-not $ok4) { $fail++ }
Write-Output ("  {0}  两行注释 + 一行真断言 = 1 个调用点（退出码 {1}，期望 0）" -f $(if($ok4){'PASS'}else{'FAIL'}), $code4)
if (-not $ok4) { Write-Output (($out4.TrimEnd() -split "`n" | ForEach-Object { '        ' + $_ }) -join "`n") }

# 反查 ⑤ 是 2026-10-01 加的：页面**有断言但不写标题**，必须 exit 1。
# 起因是 _checkall 收尾那句「打开 _*.html 看标题 PASS n/m」——
# 七套里有三套（drive/traffic/route）压根没写 document.title，
# 于是那条指令对它们是假的，而**没有任何检查发现**。
# 这条反查存在的意义就是让那句指令以后永远是真的。
Write-Output '=== 5) 页有断言但没把真条数写进标题：必须 exit 1（否则「看标题」是假指令）==='
Reset-Tmp -mode 'ok' -which $null
[IO.File]::WriteAllText((Join-Path $tmp $OUT_PROBE_EMPTY),
  "<html><body><script>`nok(1,'有断言');`nok(1,'也有断言');`n</script></body></html>",
  (New-Object Text.UTF8Encoding($false)))
$out5 = & powershell -NoProfile -ExecutionPolicy Bypass -File $ps -Dir $tmp 2>&1 | Out-String
$code5 = $LASTEXITCODE
$ok5 = ($code5 -eq 1) -and ($out5 -match 'NOTITLE')
if (-not $ok5) { $fail++ }
Write-Output ("  {0}  {1} 两条断言、无 document.title → 退出码 {2}，期望 1 且输出含 NOTITLE" -f $(if($ok5){'PASS'}else{'FAIL'}), $OUT_PROBE_EMPTY, $code5)
if (-not $ok5) { Write-Output (($out5.TrimEnd() -split "`n" | ForEach-Object { '        ' + $_ }) -join "`n") }

Write-Output ''
if ($fail -eq 0) {
  Write-Output 'pages 反查成立：好目录放行，缺页/空页/没写标题都拦得住，注释不误伤（不是恒过）'
  mavis-trash $tmp
  exit 0
} else {
  Write-Output "pages 反查失败 $fail 条"
  mavis-trash $tmp
  exit 1
}