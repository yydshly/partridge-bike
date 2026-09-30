$ErrorActionPreference = 'Stop'
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
$dir = $ROOT
$enc = New-Object Text.UTF8Encoding($false)

# ---- 1. the track table: base64-inlined so the HTML stays a single file ----
# 曲目定义在 _bgm-meta.json —— 加歌 = 改那个文件 + 放 mp3 进来，不用动这个脚本
$meta  = [IO.File]::ReadAllText(($BGM_META)) | ConvertFrom-Json
$tracks = $meta.tracks

# 歌词要转成 JS 字符串数组。中文直接进 JS 字面量没问题（成品是 UTF-8），
# 但单引号、反斜杠、换行必须转义 —— 歌词里出现过空格和「，」但没引号，
# 这里照做以防以后改词时踩到。
function JsStr([string]$s){
  $s.Replace('\','\\').Replace("'","\'").Replace("`r",'').Replace("`n",'\n')
}

$sb = [Text.StringBuilder]::new()
[void]$sb.AppendLine('[')
for ($i = 0; $i -lt $tracks.Count; $i++){
  $t = $tracks[$i]
  # ⚠️ 这里原来写的是 `Join-Path $dir $t.f`（$dir = $ROOT）。
  #    `$t.f` 来自 _bgm-meta.json，所以它**不是脚本里的字符串字面量** ——
  #    A 阶段那道覆盖率闸门是静态的，只认字面量，这类从**数据**里来的
  #    路径它看不见。加 mp3 时它也永远查不到，因为那行代码一个字都不改。
  #    所以凡是「Join-Path + 运行时才有的第二个参数」，都要单独手工核一遍。
  $src = Join-Path $DIR_BGM $t.f
  if (-not (Test-Path $src)) { throw "missing audio: $($t.f)" }
  $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($src))
  $lyr = @()
  if ($t.lyrics) { $lyr = ($t.lyrics -split "`n" | Where-Object { $_.Trim() -ne '' } | ForEach-Object { JsStr $_.Trim() }) }
  $lyrJs = ($lyr | ForEach-Object { "'" + $_ + "'" }) -join ','
  [void]$sb.AppendLine("  {title:'" + $t.title + "', vocal:" + ($(if($t.vocal){'true'}else{'false'})) + ", lyrics:[" + $lyrJs + "], b64:'$b64'}" + $(if ($i -lt $tracks.Count-1) { ',' } else { '' }))
}
[void]$sb.AppendLine(']')
$bgm = $sb.ToString()

# ---- 2. inline three.js ----
# ⚠️ 这里原来写的是 `Join-Path $dir '_vendor\three149.min.js'`。
#    那是路径的**第二个出处**：A 阶段的覆盖率闸门当时只认 `'名字.ext'`
#    这种光秃秃的叶子名，带目录前缀的字面量从它眼皮底下过去了 ——
#    所以「零处硬编码」这个结论是不完整的，是后来把闸门改成
#    「任意前缀 + 叶子名」才把它翻出来的。B 阶段要把 _vendor 搬进
#    assets\vendor，这一行不改就会当场断掉。
$lib = [IO.File]::ReadAllText(($THREE_LIB)) -replace '(?i)</script','<\/script'

# ---- 3. splice both into the template ----
$tpl = [IO.File]::ReadAllText(($APP))
$html = $tpl.Replace('/*__BGM_TRACKS__*/', $bgm).Replace('/*__THREE__*/', $lib)
[IO.File]::WriteAllText(($PRODUCT), $html, $enc)

$size = (Get-Item ($PRODUCT)).Length
"built partridge-3d.html  {0:N0} bytes  ({1:N1} MB)" -f $size, ($size/1MB)
"tracks inlined: $($tracks.Count)"
$withLyrics = ($tracks | Where-Object { $_.lyrics }).Count
"tracks with lyric subtitles: $withLyrics"