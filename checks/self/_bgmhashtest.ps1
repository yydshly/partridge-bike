param()
# _bgmhash.ps1 自己的反查。
#
# 「一个从没红过的判据」和「一个恒过的判据」在终端上长得一模一样。
# 这道判据读的是 sha256 —— 它的恒过形态特别隐蔽：只要**拿不到文件**、
# 或者**没真去比**，它就一路 PASS。所以下面每一件事都做成「先把判据调起来、
# 亲眼看它红 / 看它绿」。
#
# 坏样怎么造：对**副本**动手，绝不碰 assets\bgm 里那 8 个 mp3。
# 改「最终生效的那个值」（mp3 的实际字节、基线里的实际哈希），
# 而不是在旁边留一行错字 —— 判据与被测共享同一条语义时，
# 就会被同一条语义一起骗过。
#
# 另外必须验**好样本不误伤**：判据对没动过的副本也得绿。
# 只会红的判据和不会红的判据一样有害。
$ErrorActionPreference = 'Continue'   # 判据的失败路径会 exit 1；退出码才是要看的东西
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')

# 计数用 hashtable（引用类型）：「函数里自增、文件末尾读回来」的那种散装整数
# 在本项目栽过跟头（逐行都对、汇总是 0），这里不重复那个错。
$st = @{ fail = 0 }
function Chk($name, $cond, $detail) {
  if ($cond) { Write-Output ('  PASS  ' + $name) }
  else { $st.fail++; Write-Output ('  FAIL  ' + $name); Write-Output ('        ' + $detail) }
}

# 把判据当子进程跑，拿到它的退出码和它的**原话**。
# 「点名到具体文件」这件事只能靠读它自己的输出来验。
function RunCheck($dir, $baseline) {
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $S_BGMHASH -Dir $dir -Baseline $baseline 2>&1 | Out-String
  return @{ code = $LASTEXITCODE; out = $out }
}

Write-Output '=== A) 前提：真的基线 + 真的 mp3 ==='
Chk '基线文件存在' (Test-Path -LiteralPath $BGM_SHA) $BGM_SHA
Chk 'mp3 目录里有 8 个文件' (@(Get-ChildItem -LiteralPath $DIR_BGM -Filter '*.mp3').Count -eq 8) '数量不对'
if ($st.fail -gt 0) { exit 1 }
$doc = ConvertFrom-Json ([IO.File]::ReadAllText($BGM_SHA))
Chk '基线里有 8 条' (@($doc.tracks).Count -eq 8) ('基线里 ' + @($doc.tracks).Count + ' 条')
# 基线的哈希必须是**合法的 64 位十六进制**。不是的话「比对」比的是格式而不是内容 ——
# 那正是这道判据最可能的恒过形态。
$badHex = @(@($doc.tracks) | Where-Object { ([string]$_.sha256) -notmatch '^[0-9a-f]{64}$' })
# ⚠️ 这里必须用 -f 而不是 `$badHex.Count + ' 条格式不对'`：
#    PowerShell 的 `+` 会按**左操作数**的类型选运算，int + string 走的是数值加法，
#    于是它去把 ' 条格式不对' 转成 int 并抛类型转换错误。
#    ('文本' + int) 才是拼接。凡是要把数字接进句子，都用 -f，别靠左边是什么。
Chk '基线里每条 sha256 都是 64 位十六进制' ($badHex.Count -eq 0) ('{0} 条格式不对' -f $badHex.Count)
# 记下真基线和真 mp3 的指纹 —— 收尾要证明反查没碰过它们。
$baseBefore = (Get-FileHash -LiteralPath $BGM_SHA -Algorithm SHA256).Hash

Write-Output ''
Write-Output '=== B) 好样本不误伤 ==='
$copy = Join-Path $DIR_OUT '_bgmhash'
$tmpBase = Join-Path $copy '_tmp-base.json'
if (Test-Path $copy) { mavis-trash $copy }
$null = New-Item -ItemType Directory -Path $copy -Force
foreach ($f in Get-ChildItem -LiteralPath $DIR_BGM -Filter '*.mp3') {
  Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $copy $f.Name)
}
Chk '副本和真目录一样是 8 个' (@(Get-ChildItem -LiteralPath $copy -Filter '*.mp3').Count -eq 8) '复制没成功'

$r0 = RunCheck $DIR_BGM $BGM_SHA
Chk '判据对**真目录**就是绿的（这就是 CI 里跑的那一次）' ($r0.code -eq 0) ('退出码=' + $r0.code + "`n" + $r0.out)
$r1 = RunCheck $copy $BGM_SHA
Chk '判据对**没动过的副本**也绿（好样本不误伤）' ($r1.code -eq 0) ('退出码=' + $r1.code + "`n" + $r1.out)
Chk '好样本的输出里点名了每一个文件' (@([regex]::Matches($r1.out, 'PASS\s+bgm-')).Count -eq 8) `
    ('只点到 ' + [regex]::Matches($r1.out, 'PASS\s+bgm-').Count + ' 个')

Write-Output ''
Write-Output '=== C) 坏样一：改 1 个字节（大小一样，内容变了）==='
$victim = Join-Path $copy 'bgm-5-slow.mp3'
$orig = [IO.File]::ReadAllBytes($victim)
# 只翻一个字节，长度不动 —— 这正是「最难被发现的那种替换」
$orig[1000] = $orig[1000] -bxor 0xFF
[IO.File]::WriteAllBytes($victim, $orig)
$r2 = RunCheck $copy $BGM_SHA
Chk '改 1 个字节 → 判据必须 exit 1' ($r2.code -ne 0) ('退出码=' + $r2.code)
Chk '...并且**点名 bgm-5-slow.mp3**' ($r2.out -match 'bgm-5-slow\.mp3') '输出里没有那个文件名'
Chk '...并且说清是 sha256 不符（长度没变，所以只能是内容变了）' ($r2.out -match 'sha256') '输出里没提 sha256'
# 还原
[IO.File]::WriteAllBytes($victim, [IO.File]::ReadAllBytes((Join-Path $DIR_BGM 'bgm-5-slow.mp3')))
Chk '还原之后判据重新变绿' ((RunCheck $copy $BGM_SHA).code -eq 0) '还原没成功 —— 这条红了说明别再看后面的'

Write-Output ''
Write-Output '=== D) 坏样二：删一个文件 ==='
$gone = Join-Path $copy 'bgm-7-quiet.mp3'
$kept = [IO.File]::ReadAllBytes($gone)
mavis-trash $gone
$r3 = RunCheck $copy $BGM_SHA
Chk '删一个文件 → 判据必须 exit 1' ($r3.code -ne 0) ('退出码=' + $r3.code)
Chk '...并且点名 bgm-7-quiet.mp3 是「基线里有、盘上没了」' (($r3.out -match 'bgm-7-quiet\.mp3') -and ($r3.out -match '盘上没了')) $r3.out
[IO.File]::WriteAllBytes($gone, $kept)
Chk '放回去之后判据重新变绿' ((RunCheck $copy $BGM_SHA).code -eq 0) '没放回去'

Write-Output ''
Write-Output '=== E) 坏样三：多一个基线里没有的文件 ==='
$extra = Join-Path $copy 'bgm-9-秘密.mp3'
[IO.File]::WriteAllBytes($extra, $kept)          # 内容无关：文件名不在基线里就该报
$r4 = RunCheck $copy $BGM_SHA
Chk '多一个文件 → 判据必须 exit 1' ($r4.code -ne 0) ('退出码=' + $r4.code)
Chk '...并且点名它「基线里没有」' (($r4.out -match 'bgm-9') -and ($r4.out -match '基线里没有')) $r4.out
mavis-trash $extra

Write-Output ''
Write-Output '=== F) 坏样四：基线自己被改坏（验证它比的是内容不是格式）==='
# ⚠️ 这里踩过一次很典型的坑，值得留着：坏样是**对 JSON 文本做 -replace** 造的，
#    而 PowerShell 5.1 的 ConvertTo-Json 输出的是 `"sha256":  "…"`（冒号后**两个**空格），
#    正则按一个空格写 → 匹配数 0 → -replace 静默返回原串 → **坏样其实是个好样**。
#    于是判据全绿，看起来像「验过了」。而如果只写「必须 exit 1」，
#    下一步就会去改一个**完全正确**的判据 —— 那才是真事故。
# 现在改成**改对象再序列化**，一个文本格式假设都不依赖；
# 并且在验判据之前，先断言「坏样真的和原基线不同」。
$bj2 = ConvertFrom-Json ([IO.File]::ReadAllText($BGM_SHA))
$bj2.tracks[0].sha256 = ('f' + ([string]$bj2.tracks[0].sha256).Substring(1))
[IO.File]::WriteAllText($tmpBase, (($bj2 | ConvertTo-Json -Depth 5) + "`n"), (New-Object Text.UTF8Encoding($false)))

# 造完坏样，**先证明它是坏的** —— 这一条正是上面那次事故的防线。
$tmpHash = (Get-FileHash -LiteralPath $tmpBase -Algorithm SHA256).Hash
Chk '坏样本身和原基线不是同一个文件（没替换成功就是好样，不是坏样）' ($tmpHash -ne $baseBefore) `
    '两个文件哈希一样 —— 说明这次「造坏样」压根没改成'
Chk '坏样仍然是合法 JSON，且哈希仍是 64 位十六进制（红的原因要精确）' `
    (([string]((ConvertFrom-Json ([IO.File]::ReadAllText($tmpBase))).tracks[0].sha256)) -match '^[0-9a-f]{64}$') `
    '坏样坏在了格式上 —— 那样判据红的原因和「哈希不符」无关'
$r5 = RunCheck $copy $tmpBase
Chk '基线里改 1 位哈希 → 判据必须 exit 1' ($r5.code -ne 0) ('退出码=' + $r5.code)
Chk '...并且报的是哈希不符，不是格式错' ($r5.out -match 'sha256') $r5.out
Chk '...并且点名那个被改过的文件' ($r5.out -match ([regex]::Escape($bj2.tracks[0].file))) $r5.out

Write-Output ''
Write-Output '=== G) -Update 闭环：基线是代码生成的，不是人手抄的 ==='
# 「怎么重新生成基线」如果只写在文档里，那份文档会自己过期。
# 这里真跑一次 -Update，验证它能产出判据自己认的基线。
$null = & powershell -NoProfile -ExecutionPolicy Bypass -File $S_BGMHASH -Dir $copy -Baseline $tmpBase -Update 2>&1 | Out-Null
Chk '-Update 跑完退出码是 0' ($LASTEXITCODE -eq 0) ('退出码=' + $LASTEXITCODE)
Chk '-Update 真的写出了基线文件' (Test-Path -LiteralPath $tmpBase) $tmpBase
$r6 = RunCheck $copy $tmpBase
Chk '它刚生成的基线，自己的判据读得进（格式自洽）' ($r6.code -eq 0) ('退出码=' + $r6.code + "`n" + $r6.out)
$r7 = RunCheck $DIR_BGM $tmpBase
Chk '新基线对**真目录**也成立（不是只对副本自洽）' ($r7.code -eq 0) ('退出码=' + $r7.code + "`n" + $r7.out)

Write-Output ''
Write-Output '=== H) 收尾：反查没碰过被测对象 ==='
$baseAfter = (Get-FileHash -LiteralPath $BGM_SHA -Algorithm SHA256).Hash
Chk '真基线文件一个字节都没被反查改动' ($baseBefore -eq $baseAfter) '基线被改了 —— 反查不该写它'
$r8 = RunCheck $DIR_BGM $BGM_SHA
Chk '真 mp3 目录仍然全绿（反查没碰过那 8 个文件）' ($r8.code -eq 0) ('退出码=' + $r8.code + "`n" + $r8.out)

if (Test-Path $copy) { mavis-trash $copy }

Write-Output ''
if ($st.fail -eq 0) {
  Write-Output '  bgmhash 判据成立：好样本绿、四种坏样各自红并点名到文件、-Update 闭环自洽、没碰被测对象。'
  exit 0
}
Write-Output ('  bgmhashtest 失败 ' + $st.fail + ' 条')
exit 1
