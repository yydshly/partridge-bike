param()
# _doccheck.ps1 的反查：把**真文档复制一份**，逐个注入五类漂移，
# 要求同一个判据每次都翻红；再要求原封不动的真文档一次都不红。
#
# 为什么要专门做这一份，而且为什么是「复制真文档」而不是「造一份假文档」：
#   造假文档的话，假文档里根本没有那些**总步数声明**和**产物点名**，
#   于是判据在假文档上恒过，反查是绿的，而它验的是个空壳。
#   用真文档做底，被破坏的只有我明确注入的那一处。
#
# ⚠️ 这份反查存在的直接原因：_doccheck.ps1 第一版的 ① 号判据
#    （`-File` 命令的路径存不存在）**正则漏了捕获组**，
#    $m.Groups[1].Value 恒为空串 → 路径算成仓库根目录 → Test-Path 永远为真
#    → 这条判据从写出来那一刻起就永远不会红。
#    而它跑出来的输出「9 处文档漂移」看着挺正常，**只有反查能发现这件事**。
$ErrorActionPreference = 'Continue'
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
$dir = $ROOT
$ps  = $S_DOCCHECK
$tmp = Join-Path $dir '_doctest'

$README_NAME = [IO.Path]::GetFileName($README)
$AGENTS_NAME = [IO.Path]::GetFileName($AGENTS)
$utf8 = New-Object Text.UTF8Encoding($false)

function Reset-Tmp {
  if (Test-Path $tmp) { mavis-trash $tmp }
  $null = New-Item -ItemType Directory -Path $tmp -Force
  Copy-Item -LiteralPath $README -Destination (Join-Path $tmp $README_NAME) -Force
  Copy-Item -LiteralPath $AGENTS -Destination (Join-Path $tmp $AGENTS_NAME) -Force
}
function Inject { param($text)
  Add-Content -LiteralPath (Join-Path $tmp $README_NAME) -Value $text -Encoding UTF8
}
# 把 README 里**所有**「保留所有权利 / 未选择许可证」的行删掉，再补一段新的话。
# 不用 Inject（它是追加）：留着那几行的话，判据照样能从原文里读到声明，
# 反查就成了「在好文档后面追加一段坏话」——而真实事故是**声明被删掉**。
function Rewrite-Readme { param($text)
  $fp = Join-Path $tmp $README_NAME
  $lines = [IO.File]::ReadAllLines($fp)
  $keep = @($lines | Where-Object { $_ -notmatch '保留所有权利' -and $_ -notmatch '未选择许可证' })
  $body = ($keep -join "`r`n").TrimEnd() + "`r`n`r`n" + $text + "`r`n"
  [IO.File]::WriteAllText($fp, $body, (New-Object Text.UTF8Encoding($false)))
}
function Set-License { param([switch]$On)
  $lic = Join-Path $tmp 'LICENSE'
  if ($On) { [IO.File]::WriteAllText($lic, 'All rights reserved.', (New-Object Text.UTF8Encoding($false))) }
  elseif (Test-Path $lic) { mavis-trash $lic }
}

$fail = 0
function Case { param($name, $wantExit, $wantText)
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

Write-Output '=== 1) 真文档原封不动：必须 exit 0（好样本不误伤）==='
Reset-Tmp
Case 'README/AGENTS 未被改动' 0 ''

Write-Output '=== 2) 注入一条指向不存在文件的 -File 命令：必须 exit 1 且输出含 CMDPATH ==='
Write-Output '    （B 阶段之后 AGENTS.md 里的 .\tools\_build.ps1 真的变成了 .\_build.ps1，'
Write-Output '      照抄就报错，而当时没有任何检查发现。这条反查就是为它留的。）'
Reset-Tmp
Inject '```powershell'
Inject 'powershell -NoProfile -ExecutionPolicy Bypass -File .\ZZnotreal.ps1'
Inject '```'
Case '命令路径不存在' 1 'CMDPATH'

Write-Output '=== 3) 注入一个错的总步数：必须 exit 1 且输出含 STEPS ==='
Write-Output '    （只查「总数声明」；「第 17 步」那种历史记录不查，否则报出来的全是假红。）'
Reset-Tmp
Inject '本仓库一共有 99 步验证。'
Case '总步数写错' 1 'STEPS'

Write-Output '=== 4) 注入一个 _paths.ps1 不认得的产物名：必须 exit 1 且输出含 PHANTOM ==='
Write-Output '    （它的真身是文档里把 partridge-3d.html 拼成 parridge-3d.html ——'
Write-Output '      收尾提示和 README 的「双击这个文件」都指着一个不存在的文件，判据当场抓住。）'
Reset-Tmp
Inject '打开 dist\ZZphantom.html 看看。'
Case '幻觉产物名' 1 'PHANTOM'

Write-Output '=== 5) 注入一个错的产品个数：必须 exit 1 且输出含 PRODNUM ==='
Reset-Tmp
Inject 'dist 里一共有 3 个产物。'
Case '产物个数写错' 1 'PRODNUM'

Write-Output '=== 6) 四处一起注入：必须 exit 1 且四个记号全在（判据不是只认一种坏法）==='
Reset-Tmp
Inject '```powershell'
Inject 'powershell -NoProfile -ExecutionPolicy Bypass -File .\ZZnotreal.ps1'
Inject '```'
Inject '本仓库一共有 99 步验证。'
Inject '打开 dist\ZZphantom.html 看看。'
Inject 'dist 里一共有 3 个产物。'
$out6 = & powershell -NoProfile -ExecutionPolicy Bypass -File $ps -Dir $tmp 2>&1 | Out-String
$code6 = $LASTEXITCODE
$miss = @()
foreach ($tag in @('CMDPATH','STEPS','PHANTOM','PRODNUM')) { if ($out6 -notmatch $tag) { $miss += $tag } }
$ok6 = ($code6 -eq 1) -and ($miss.Count -eq 0)
if (-not $ok6) { $fail++ }
Write-Output ("  {0}  四处坏同时报出来，退出码 {1}，期望 1{2}" -f $(if($ok6){'PASS'}else{'FAIL'}), $code6,
              $(if ($miss.Count -gt 0) { "，漏了：$($miss -join ',')" } else { '，四个记号都在' }))
if (-not $ok6) { Write-Output (($out6.TrimEnd() -split "`n" | ForEach-Object { '        ' + $_ }) -join "`n") }

Write-Output ''
Write-Output '=== 7) 删掉 README 里的许可声明、又没有 LICENSE 文件：必须 exit 1 且含 LICENSE ==='
Write-Output '    （这个仓库的决定是「不加 LICENSE，保留所有权利」。可「没加」和「决定不加」'
Write-Output '      在访客眼里一模一样 —— 都是根目录空的。只有把声明写进 README，'
Write-Output '      它才从疏漏变成决定。判据要能抓住「声明被删了」这个半途而废的状态。）'
Reset-Tmp
Rewrite-Readme '本项目的授权方式见仓库设置。'
Case '许可声明和文件都没有' 1 'LICENSE'

Write-Output ''
Write-Output '=== 8) 补上了 LICENSE 文件、README 却还写着保留所有权利：必须 exit 1 且含 LICENSE ==='
Write-Output '    （只查第 7 条那种状态的话，「将来开源时补了文件忘了改声明」就漏了。'
Write-Output '      两边自相矛盾时，总有一份是过期的，而访客没理由知道是哪一份。）'
Reset-Tmp
Set-License -On
Case '文件和声明互相矛盾' 1 'LICENSE'

Write-Output ''
Write-Output '=== 9) 有 LICENSE、README 也改成指名许可证：必须 exit 0（好样本不误伤）==='
Reset-Tmp
Set-License -On
Rewrite-Readme '本项目采用 MIT 许可证。'
Case '文件和声明一致（有许可证）' 0 'LICENSE 有文件'

Write-Output ''
if ($fail -eq 0) {
  Write-Output 'doc 反查成立：好文档放行，五类漂移都拦得住且各自点名（不是恒过）'
  mavis-trash $tmp
  exit 0
} else {
  Write-Output "doc 反查失败 $fail 条"
  mavis-trash $tmp
  exit 1
}
