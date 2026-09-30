param()
# _pages.ps1 的反查：喂它三种目录，它必须给出三种不同的答案。
#
# 为什么要专门做这一份：清点脚本天生容易**恒过** ——
#   ① 页名写错 / 路径拼错 → 一页都没找到，可循环压根没跑，照样 exit 0；
#   ② `if` 写反了 → 什么都不算失败；
#   ③ 只判存在不判内容 → 生成器切空了（PASS 0/0）也算合格。
# 三条都不是「读源码看不出来」的，必须真喂坏样本。
$ErrorActionPreference = 'Continue'
$dir = 'E:\minimax_code_project\0929_project\partridge-bike'
$ps  = Join-Path $dir '_pages.ps1'
$tmp = Join-Path $dir '_pagestest'

# 假的「好页面」内容：只保留清点脚本真正会看的两样东西 —— 断言调用点、反查标记
$good = "<html><body><script>`nconst ok=(c,n)=>R.push([c,n]);`nok(1,'a');`nok(0,'反查 ①:x','d');`n</script></body></html>"

function Reset-Tmp { param($mode, $which)
  if (Test-Path $tmp) { mavis-trash $tmp }
  $null = New-Item -ItemType Directory -Path $tmp -Force
  $map = @{ '_driveharness.html'='ok'; '_trafficharness.html'='ok'; '_routeharness.html'='ok';
            '_moodharness.html'='ok'; '_cruiseharness.html'='ok'; '_moodstate.html'='ok';
            '_uistate.html'='uok' }
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
Case '七页齐全、每页都有断言' 'ok' $null 0 ''

Write-Output '=== 2) 缺一页：必须 exit 1（这就是「恒过」的反查）==='
Case '缺 _uistate.html' 'missing' '_uistate.html' 1 'MISSING'

Write-Output '=== 3) 页在但内容被切空：必须 exit 1（PASS 0/0 那种阴坏）==='
Case '_moodharness.html 存在但零断言' 'empty' '_moodharness.html' 1 'EMPTY'

Write-Output '=== 4) 注释里的 ok( 不该被当成断言（不误伤）==='
Reset-Tmp -mode 'ok' -which $null
[IO.File]::WriteAllText((Join-Path $tmp '_routeharness.html'),
  "<html><body><script>`n// ok( 这行是注释，不算断言`n/* ok( 这行也是 */`nok(1,'只有这条是真的');`n</script></body></html>",
  (New-Object Text.UTF8Encoding($false)))
$out4 = & powershell -NoProfile -ExecutionPolicy Bypass -File $ps -Dir $tmp 2>&1 | Out-String
$code4 = $LASTEXITCODE
$ok4 = ($code4 -eq 0) -and ($out4 -match '1 个断言调用点')
if (-not $ok4) { $fail++ }
Write-Output ("  {0}  两行注释 + 一行真断言 = 1 个调用点（退出码 {1}，期望 0）" -f $(if($ok4){'PASS'}else{'FAIL'}), $code4)
if (-not $ok4) { Write-Output (($out4.TrimEnd() -split "`n" | ForEach-Object { '        ' + $_ }) -join "`n") }

Write-Output ''
if ($fail -eq 0) {
  Write-Output 'pages 反查成立：好目录放行，缺页/空页都拦得住，注释不误伤（不是恒过）'
  mavis-trash $tmp
  exit 0
} else {
  Write-Output "pages 反查失败 $fail 条"
  mavis-trash $tmp
  exit 1
}
