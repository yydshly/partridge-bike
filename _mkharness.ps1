$ErrorActionPreference = 'Stop'
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
$dir = $ROOT
$app   = [IO.File]::ReadAllText(($APP))
$built = [IO.File]::ReadAllText(($PRODUCT))

# ---- 1. base64 integrity: decode every blob back out of the built HTML and
#         compare byte-for-byte against the mp3 still sitting on disk ----
$rx = [regex]'\{title:''(?<t>[^'']+)'', vocal:(?<v>true|false), lyrics:\[(?<l>[^\]]*)\], b64:''(?<b>[A-Za-z0-9+/=]+)''\}'
$ms = $rx.Matches($built)
"built tracks matched: $($ms.Count)"
# 这八个名字**故意硬写**：这份脚本的职责就是拿「独立抄一遍的名单」去核对
# _bgm-meta.json 和成品里的 base64 —— 如果改成从 _bgm-meta.json 读，
# 就变成自己跟自己比，恒过。目录仍然走 $DIR_BGM（那个才是路径的出处）。
$names = @('bgm-1-sunset.mp3','bgm-2-wind.mp3','bgm-3-road.mp3','bgm-4-dusk.mp3',
           'bgm-5-slow.mp3','bgm-6-wind.mp3','bgm-7-quiet.mp3','bgm-8-onward.mp3')
$bad = 0
for ($i = 0; $i -lt $ms.Count; $i++){
  $bytes = [Convert]::FromBase64String($ms[$i].Groups['b'].Value)
  $disk  = [IO.File]::ReadAllBytes((Join-Path $DIR_BGM $names[$i]))
  $same  = ($bytes.Length -eq $disk.Length)
  if ($same){
    for ($k = 0; $k -lt $bytes.Length -and $same; $k++){ if ($bytes[$k] -ne $disk[$k]){ $same = $false } }
  }
  $nLyr = ([regex]::Matches($ms[$i].Groups['l'].Value, "'")).Count / 2
  $tag  = if ($same) { 'IDENTICAL' } else { 'MISMATCH' }
  "  {0,-18} {1,10:N0} bytes  {2,-9} lyrics:{3}" -f $names[$i], $bytes.Length, $tag, ([int]$nLyr)
  if (-not $same){ $bad++ }
}
"base64 integrity: " + $(if ($bad -eq 0) { "all $($ms.Count) tracks byte-for-byte OK" } else { "$bad MISMATCH" })

# ---- 2. build the harness: real player block, real track metadata, tiny fake b64 ----
# 按行号取，别用字符匹配 —— 标题里那一长串横线数错了很难查
$appLines = [IO.File]::ReadAllLines(($APP))
$sLine = -1; $eLine = -1
for ($i = 0; $i -lt $appLines.Count; $i++){
  if ($sLine -lt 0 -and $appLines[$i] -match '^/\* .* background music'){ $sLine = $i }
  if ($sLine -ge 0 -and $appLines[$i] -eq 'bgmBuild();' -and $appLines[$i+1] -eq 'paintBgm();'){ $eLine = $i+1; break }
}
if ($sLine -lt 0 -or $eLine -lt 0){ throw "bgm block bounds not found (s=$sLine e=$eLine)" }
"bgm block: app lines $($sLine+1)..$($eLine+1)"
$block = ($appLines[$sLine..$eLine] -join "`n")

# 用 IndexOf 算边界，别用正则的惰性 .*? 去扫 1100 万字符 —— 在脚本里会跑超时。
# 数组结尾固定是 "]\r\n;"（构建脚本用 AppendLine(']')，分号被推到下一行）；
# 数组内部只有 lyrics:['...']（后面跟逗号），所以第一个 "] 回车 换行 ;" 就是结尾。
$bt = $built.IndexOf('const BGM_TRACKS = [')
if ($bt -lt 0){ throw 'tracks array start not found' }
$btEnd = $built.IndexOf("]`r`n;", $bt)
if ($btEnd -lt 0){ throw 'tracks array end not found' }
$tracksLit = $built.Substring($bt, $btEnd + 5 - $bt)
"tracks literal (with audio): {0:N0} chars" -f $tracksLit.Length

# 把每条 b64 换成 8 个字节的假数据，页面才拉得动
$fakeB64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('12345678'))
$tracksLit = [regex]::Replace($tracksLit, "b64:'[A-Za-z0-9+/=]+'", "b64:'$fakeB64'")
"tracks literal (shrunk)   : {0:N0} chars" -f $tracksLit.Length
if ($tracksLit.Length -gt 100000){ throw 'shrunk tracks literal still too big — b64 replace missed' }
$block = $block.Replace('const BGM_TRACKS = /*__BGM_TRACKS__*/;', $tracksLit)
if ($block -notmatch [regex]::Escape("b64:'$fakeB64'")){ throw 'splice failed' }

$exp = @(); foreach ($n in $names){ $exp += 8 }
$expJs = '[' + ($exp -join ',') + ']'

$tpl     = [IO.File]::ReadAllText(($TPL_BGM2))
$harness = $tpl.Replace('/*__BGM__*/', $block).Replace('__EXPECT__', $expJs)
[IO.File]::WriteAllText((Join-Path $dir '_bgmharness2.html'), $harness, (New-Object Text.UTF8Encoding($false)))
"harness bytes: {0:N0}" -f (Get-Item (Join-Path $dir '_bgmharness2.html')).Length