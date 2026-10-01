param(
  [switch]$Update,
  [string]$Dir,
  [string]$Baseline
)
# assets\bgm\ 里那 8 个 mp3 的**内容基线**。
#
# 为什么第 19 步不够：它把成品 HTML 里的 base64 解码回来，和盘上的 mp3
# 逐字节比 —— 它防的是「构建时用错文件 / base64 传输中损坏」。
# 但它**防不住 mp3 本身被换掉**：换掉之后重新构建，产物和盘上文件会**一起变**，
# 那一步仍然全绿。而这个目录的注释写着「8.2 MB，不可再生，唯一的副本」——
# 没有第二份可以对照，所以「换成别的歌了」这件事本仓库里没有任何东西会响。
#
# 这道判据钉的是「**这些 mp3 就是当初那批**」：sha256 + 字节数。
# 字节数也记，因为「大小一样、内容变了」才是最隐蔽的那种
# （重新压制同长度极难，但换首同长度的歌完全可能）。
#
# 三个方向都要查，缺一个就等于给了一种悄悄腐烂的路：
#   盘上有、基线里没有  → 偷偷加了一首（谁加的？歌词表里根本没有它）
#   基线里有、盘上没有  → 文件被删了/改名了
#   两边都有但值不对      → 被换掉了
#
# ⚠️ -Update 是**有意换素材**时用的（换歌、重新压制），不是「让判据变绿」的开关：
#   CI 里不带这个参数。而且它和「造坏样本的反查」共用同一段计算代码 ——
#   复制粘贴一份「怎么生成基线」到别处，那份就会自己过期。
$ErrorActionPreference = 'Stop'
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')

if (-not $Dir)      { $Dir = $DIR_BGM }
if (-not $Baseline) { $Baseline = $BGM_SHA }

# 曲目顺序按文件名排 —— 基线是给人审的，顺序必须稳定，
# 不然每次重新生成 diff 都一屏噪声，真正的改动就淹在里面了。
$files = @(Get-ChildItem -LiteralPath $Dir -Filter '*.mp3' -ErrorAction Stop | Sort-Object Name)

if ($Update) {
  $tracks = @()
  foreach ($f in $files) {
    $tracks += [ordered]@{
      file   = $f.Name
      bytes  = [int]$f.Length
      sha256 = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower()
    }
  }
  $doc = [ordered]@{
    why   = 'assets/bgm 里 8 个 mp3 的内容基线。判据见 checks/_bgmhash.ps1：第 19 步只验「产物里的 base64 == 盘上的 mp3」，换掉 mp3 之后重新构建它照样全绿；这个文件钉的是「这些就是当初那批」。'
    algo  = 'SHA256'
    note  = '字节数也记下来：大小一样而内容变了，才是最难被发现的那种替换。有意更换素材后重新生成：powershell -NoProfile -ExecutionPolicy Bypass -File .\checks\_bgmhash.ps1 -Update'
    count = $tracks.Count
    tracks = $tracks
  }
  $json = ($doc | ConvertTo-Json -Depth 5) + "`n"
  [IO.File]::WriteAllText($Baseline, $json, (New-Object Text.UTF8Encoding($false)))
  Write-Output ('  基线已重写：' + $Baseline)
  Write-Output ('  记录了 ' + $tracks.Count + ' 个文件：')
  foreach ($t in $tracks) { Write-Output ('    {0,-18} {1,10}  {2}' -f $t.file, $t.bytes, $t.sha256) }
  Write-Output '  ⚠️ 这一步等于宣布「现在这批就是基线」。确认你是有意换的。'
  exit 0
}

# ── 严格比对 ──────────────────────────────────────────────
if (-not (Test-Path -LiteralPath $Baseline)) {
  Write-Output ('  ! 没有基线文件：' + $Baseline)
  Write-Output '    第一次用：powershell -NoProfile -ExecutionPolicy Bypass -File .\checks\_bgmhash.ps1 -Update'
  exit 1
}
$base = ConvertFrom-Json ([IO.File]::ReadAllText($Baseline))
$bad = 0

# 基线里那几条（用属性名取，`tracks` 是 PSCustomObject 数组）
$baseMap = @{}
foreach ($t in @($base.tracks)) { $baseMap[$t.file] = $t }

foreach ($f in $files) {
  $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower()
  if (-not $baseMap.ContainsKey($f.Name)) {
    Write-Output ('  FAIL  {0,-18} 盘上有、基线里没有（谁放进来的？歌词表里未必有它）' -f $f.Name)
    Write-Output ('          实际 {0} bytes  {1}' -f $f.Length, $h)
    $bad++
    continue
  }
  $t = $baseMap[$f.Name]
  $sameLen = ([int]$t.bytes -eq [int]$f.Length)
  $sameHash = ([string]$t.sha256).ToLower() -eq $h
  if ($sameLen -and $sameHash) {
    Write-Output ('  PASS  {0,-18} {1,10:N0} bytes  {2}' -f $f.Name, $f.Length, $h.Substring(0, 16))
  } else {
    $why = @()
    if (-not $sameLen) { $why += ('字节数 基线 ' + $t.bytes + ' ≠ 实际 ' + $f.Length) }
    if (-not $sameHash) { $why += ('sha256 基线 ' + $t.sha256 + ' ≠ 实际 ' + $h) }
    Write-Output ('  FAIL  {0,-18} 内容被换过：{1}' -f $f.Name, ($why -join '；'))
    $bad++
  }
}
foreach ($name in ($baseMap.Keys | Sort-Object)) {
  if (-not ($files | Where-Object { $_.Name -eq $name })) {
    Write-Output ('  FAIL  {0,-18} 基线里有、盘上没了（被删或被改名）' -f $name)
    $bad++
  }
}

Write-Output ''
if ($bad -eq 0) {
  Write-Output ('  mp3 内容基线成立：' + $files.Count + ' 个文件和基线逐字节一致。')
  exit 0
}
Write-Output ('  bgmhash 失败 ' + $bad + ' 条')
Write-Output '  换素材是有意的吗？是的话重新生成基线（这会同时更新字节数和 sha256）：'
Write-Output '    powershell -NoProfile -ExecutionPolicy Bypass -File .\checks\_bgmhash.ps1 -Update'
exit 1
