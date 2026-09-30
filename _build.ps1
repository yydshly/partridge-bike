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
  $src = Join-Path $dir $t.f
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
$lib = [IO.File]::ReadAllText((Join-Path $dir '_vendor\three149.min.js')) -replace '(?i)</script','<\/script'

# ---- 3. splice both into the template ----
$tpl = [IO.File]::ReadAllText(($APP))
$html = $tpl.Replace('/*__BGM_TRACKS__*/', $bgm).Replace('/*__THREE__*/', $lib)
[IO.File]::WriteAllText(($PRODUCT), $html, $enc)

$size = (Get-Item ($PRODUCT)).Length
"built partridge-3d.html  {0:N0} bytes  ({1:N1} MB)" -f $size, ($size/1MB)
"tracks inlined: $($tracks.Count)"
$withLyrics = ($tracks | Where-Object { $_.lyrics }).Count
"tracks with lyric subtitles: $withLyrics"