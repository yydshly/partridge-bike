param()
# CI 配置自身的判据：查 .github\workflows\verify.yml 写得对不对，
# 并且**当场证明**它自己抓得住。
#
# 为什么值得为一份 yaml 写判据：这份文件本机跑不了（GitHub runner 才执行它），
# 而「跑不了」正是它会静默腐烂的原因 —— 改坏了没人知道，直到某次 CI 变红，
# 而那次的红往往和真正的原因无关（垫片坏了、PATH 没接上、退出码没传出去）。
# 能验的部分全部在这里验掉，验不掉的部分写清楚。
#
# 分两半：
#   A  静态：yaml 的形状（缩进、ASCII、关键调用、run 块数）
#   B  反查：把垫片源码**从 yaml 里抽出来**在本地真跑一遍。
#      故意不复制粘贴一份到本文件 —— 复制的那份会自己过期，
#      于是「验的和跑的」变成两个东西，而 B 段全绿。
#      YAML 块标量的缩进规则是「按首个**非空**行」，
#      所以抽取时必须自己减掉那一层，否则本文件验的是一个 runner 不会执行的文本。
#
# ⚠️ A 段和 B 段**故意放在同一个文件**，而没有拆成判据 + 反查两个：
#    B 段要用 A 段解析出来的结果（块缩进、垫片正文），
#    拆开就得把中间产物通过临时文件传来传去，那是第二个会过期的地方。
$ErrorActionPreference = 'Stop'
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')

$WF = Join-Path $ROOT '.github\workflows\verify.yml'
$fail = 0
function Chk($name, $cond, $detail) {
  if ($cond) { Write-Output ("  {0}  {1}" -f $(if ($cond) { 'PASS' } else { 'FAIL' }), $name) }
  else { $script:fail++; Write-Output ("  FAIL  {0}  {1}" -f $name, $detail) }
}

Write-Output '=== A) workflow 文件的形状 ==='
if (-not (Test-Path -LiteralPath $WF)) {
  Write-Output ("  ! CI 配置文件不存在：" + $WF)
  Write-Output 'pathcheck 通过不代表 CI 存在 —— 没有 CI 的仓库，所有验证都只在本机跑过。'
  exit 1
}
$yml = [IO.File]::ReadAllText($WF)

# 设计约束针对的是**交给解释器执行的那部分文本**，也就是 `run: |` 的块体。
# 步骤名和 yaml 顶层注释根本不进解释器（那部分反而是给人读的，放中文没问题）。
# 断言精确的那条主张，而不是一个更宽的 —— 宽了会误报，误报的守卫最后会被关掉。
# 按**缩进**抽 `run: |` 的块体，不用「往后找下一个 key」那种前瞻。
#
# 前瞻式的第一版是坏的：块体的结束条件写成了「下一行是 `- name:` / `jobs:` /
# 空行」，而两个 step 之间夹着一大段 YAML 注释（`# ── 2. ...`），
# 于是注释被算进了**上一个** step 的块体。后果很具体：第 01 步用 'Stop'、
# 第 02 步上方的注释里出现「mavis-trash」字样，判据把两者拼在一起，
# 报出一条根本不存在的「Stop 和 mavis-trash 同时出现」。
# 判据读到了**它本来不该读到的文本** —— 和「判据咬死实现写法」是同一类病。
# 正确规则：块体的缩进由**首个非空行**决定，块体到第一个缩进**不大于**它的行为止。
$runBodies = @()
$ylines = @($yml -split "`r?`n")
for ($i = 0; $i -lt $ylines.Count; $i++) {
  if ($ylines[$i] -notmatch '^([ ]*)run:\s*\|') { continue }
  $keyIndent = $Matches[1].Length
  $j = $i + 1
  $blockIndent = -1
  while ($j -lt $ylines.Count) {
    if ($ylines[$j].Trim().Length -gt 0) {
      $blockIndent = $ylines[$j].Length - $ylines[$j].TrimStart().Length
      break
    }
    $j++
  }
  if ($blockIndent -le $keyIndent) { continue }
  $body = @()
  $j++
  while ($j -lt $ylines.Count) {
    $l = $ylines[$j]
    if ($l.Trim().Length -eq 0) { $body += ''; $j++; continue }
    if (($l.Length - $l.TrimStart().Length) -le $blockIndent) { break }
    $body += $l
    $j++
  }
  $runBodies += ,($body -join "`n")
  $i = $j - 1
}
$nonAscii = 0
foreach ($b in $runBodies) { $nonAscii += @(($b.ToCharArray() | Where-Object { [int]$_ -gt 127 })).Count }

Chk 'CI 文件存在且非空' ($yml.Length -gt 1000) ("len=" + $yml.Length)
Chk '没有 TAB（YAML 不许用 TAB 缩进）' (-not $yml.Contains("`t")) '发现 TAB'
Chk '找得到 3 个 run: 块' ($runBodies.Count -eq 3) ("找到 " + $runBodies.Count + " 个")
# 抽取引擎自己的反查：step 之间的分隔注释（`# ── 2. ...`）绝不能落进任何一个块体。
# 第一版的抽取会把它们吞掉，于是下一条判据读到了一句它不该读到的字样。
# 这是「判据的输入边界」必须有人验 —— 判据读到了不该读的东西，
# 和判据本身写错是同一种病，而且更难发现（输出看着完全合理）。
$leaked = 0
foreach ($b in $runBodies) { $leaked += @($b -split "`n" | Where-Object { $_ -match '^\s*#\s*[─-]{2,}' }).Count }
Chk 'run: 块体里没有混进 step 之间的 YAML 分隔注释' ($leaked -eq 0) ("混进 " + $leaked + " 行")
Chk 'run: 块体全是 ASCII（这条约束就是本文件存在的理由之一）' ($nonAscii -eq 0) ("块体里的非 ASCII 字符数：" + $nonAscii)
Chk '用 windows-latest' ($yml -match 'runs-on:\s*windows-latest') '缺 runs-on'
Chk 'checkout 了仓库' ($yml -match 'actions/checkout@v4') '缺 checkout'
Chk '跑的是 _checkall.ps1' ($yml -match '-File\s+\.\\checks\\_checkall\.ps1') '没找到 checkall 的调用'
Chk '末尾显式 exit $LASTEXITCODE' ($yml -match 'exit\s+\$code') '拿子检查器当最后一句却不传退出码'

# 守卫一个真的炸过的问题：第 02 步对着一个**不存在**的路径调垫片，
# 而垫片的错误路径就是要写 stderr；那时候 ErrorActionPreference 是 'Stop'，
# PowerShell 5.1 把原生命令写 stderr 变成**终止错误**，2>$null 压不住，
# 于是这一步会死在它自己的错误路径上 —— 而本机那次是通过的。
# 「本机通过」和「runner 上通过」结论相反，说明这行代码依赖了一个没写出来的前提。
#
# 判据的范围是「同时出现 Stop 和 mavis-trash 的块」：
# 只调 cmdlet 的第 01 步用 'Stop' 是安全的（New-Item / WriteAllText / Add-Content
# 不写 stderr）。第一版把 'Stop' 全禁了，于是对第 01 步报假红。
$risky = @($runBodies | Where-Object {
  $_ -match "\`$ErrorActionPreference\s*=\s*'Stop'" -and $_ -match 'mavis-trash'
}).Count
Chk '没有 run: 块同时用 ErrorActionPreference=Stop 和 mavis-trash' ($risky -eq 0) ("有 " + $risky + " 个")

Write-Output ''
Write-Output '=== B) 把垫片从 yaml 里抽出来，在本地真跑一遍（反查）==='
$m = [regex]::Match($yml, "(?s)@'\r?\n(.*?)\r?\n[ ]*'@")
Chk '能在 yaml 里找到垫片的 here-string' $m.Success '没找到 @' + "'" + ' 块'
if (-not $m.Success) { Write-Output 'cicheck 失败：没法从 CI 配置里取出垫片源码'; exit 1 }
$body = $m.Groups[1].Value

$lines = @($body -split "`r?`n")
$first = $lines | Where-Object { $_.Trim().Length -gt 0 } | Select-Object -First 1
$indent = ($first -replace '[^ ].*$', '').Length
$dedented = @($lines | ForEach-Object { if ($_.Length -ge $indent -and $_.Trim().Length -gt 0) { $_.Substring($indent) } else { '' } })
Chk '减掉块缩进后首行是注释（说明缩进真的减掉了）' ($dedented[0] -match '^#') ("首行：[" + $dedented[0] + "]")

$shimDir = Join-Path $DIR_OUT '_cicheck'
$pathBefore = $env:PATH
if (Test-Path $shimDir) { mavis-trash $shimDir }
$null = New-Item -ItemType Directory -Path $shimDir -Force
$shimPs1 = Join-Path $shimDir 'mavis-trash-shim.ps1'
[IO.File]::WriteAllText($shimPs1, (($dedented -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($true)))
$cmdLine = "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0mavis-trash-shim.ps1`" %*`r`nexit /b %ERRORLEVEL%"
[IO.File]::WriteAllText((Join-Path $shimDir 'mavis-trash.cmd'), $cmdLine, (New-Object Text.ASCIIEncoding))
$env:PATH = $shimDir + ';' + $env:PATH
$resolved = (Get-Command mavis-trash -ErrorAction SilentlyContinue)
Chk 'PATH 里的 mavis-trash 指向刚装的垫片' ($null -ne $resolved -and $resolved.Source -like "$shimDir*") `
    ("解析到：" + $(if ($resolved) { $resolved.Source } else { '(没找到)' }))

# ⚠️ 从这里开始 ErrorActionPreference 必须降成 'Continue'，理由同上：
#    垫片的错误路径**就是要**写 stderr，而 5.1 在 'Stop' 下会把它变成终止错误。
#    真正该看的判据是 $LASTEXITCODE。
$ErrorActionPreference = 'Continue'
$probe = Join-Path $shimDir 'probe'
$null = New-Item -ItemType Directory -Path $probe -Force
$f = Join-Path $probe 'one.txt'
$d = Join-Path $probe 'sub'
[IO.File]::WriteAllText($f, 'x')
$null = New-Item -ItemType Directory -Path $d -Force
[IO.File]::WriteAllText((Join-Path $d 'two.txt'), 'y')

& mavis-trash $f 2>$null | Out-Null
Chk 'a) 垫片真的删掉了一个文件' (-not (Test-Path -LiteralPath $f)) $f
Chk 'a2) ...并且报告成功' ($LASTEXITCODE -eq 0) ('退出码=' + $LASTEXITCODE)

& mavis-trash $d 2>$null | Out-Null
Chk 'b) 垫片真的删掉了一个带内容的目录' (-not (Test-Path -LiteralPath $d)) $d

& mavis-trash (Join-Path $probe 'nope.txt') 2>$null | Out-Null
Chk 'c) 目标不存在时报错（不是静默成功）' ($LASTEXITCODE -ne 0) ('退出码=' + $LASTEXITCODE)

$g = Join-Path $probe 'three.txt'
[IO.File]::WriteAllText($g, 'z')
& mavis-trash -rf $g 2>$null | Out-Null
$rc = $LASTEXITCODE
Chk 'd1) rm 风格参数被剥掉，不是当成文件名' ($rc -eq 0) ('退出码=' + $rc)
Chk 'd2) ...参数后面那个真文件确实被删了' (-not (Test-Path -LiteralPath $g)) $g

& mavis-trash 2>$null | Out-Null
Chk 'e) 一个目标都不给 -> 退出码非 0' ($LASTEXITCODE -ne 0) ('退出码=' + $LASTEXITCODE)

[IO.File]::WriteAllText((Join-Path $probe 'four.txt'), 'w')
& mavis-trash (Join-Path $probe 'four.txt') (Join-Path $probe 'gone.txt') 2>$null | Out-Null
Chk 'f) 多个目标里缺一个 -> 退出码非 0（部分成功仍算失败）' ($LASTEXITCODE -ne 0) ('退出码=' + $LASTEXITCODE)

Write-Output ''
Write-Output '=== C) 第 03 步的退出码包装（防「永远绿」）==='
$probeExit = Join-Path $shimDir 'exitprobe.ps1'
[IO.File]::WriteAllText($probeExit, "exit 1", (New-Object Text.UTF8Encoding($true)))
& powershell -NoProfile -ExecutionPolicy Bypass -File $probeExit | Out-Null
Chk '失败的子进程经 `exit $LASTEXITCODE` 传出来' ($LASTEXITCODE -eq 1) ('传出来的是 ' + $LASTEXITCODE)
[IO.File]::WriteAllText($probeExit, "exit 0", (New-Object Text.UTF8Encoding($true)))
& powershell -NoProfile -ExecutionPolicy Bypass -File $probeExit | Out-Null
Chk '成功的子进程也传 0（不是永远非 0）' ($LASTEXITCODE -eq 0) ('传出来的是 ' + $LASTEXITCODE)

# 把真的 mavis-trash 放回 PATH 再清理：垫片是那个 .cmd **自己所在的目录**里的文件，
# 叫它去删自己的家，cmd.exe 会丢掉正在执行的那个文件，然后报
# 「The system cannot find the path specified」(9009)。那句话出现在真正的结论**之后**，
# 读起来像崩了 —— 而「让人学会忽略测试输出尾巴」的噪音，正是这个项目反复交的学费。
$env:PATH = $pathBefore
if (Test-Path $shimDir) { mavis-trash $shimDir }

Write-Output ''
if ($fail -eq 0) {
  Write-Output '  CI 配置成立：形状对、run 块是 ASCII、垫片真的删得掉且错误路径响、退出码传得出去。'
  Write-Output '  ⚠️ 验不到的：runner 到底怎么解释这个 yaml（本地没有 Actions）。'
  exit 0
}
Write-Output ("  cicheck 失败 " + $fail + " 条")
exit 1
