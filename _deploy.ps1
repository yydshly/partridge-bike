param(
  [string]$Dir    = 'E:\minimax_code_project\0929_project\partridge-bike',
  [string]$Repo   = 'yydshly/partridge-bike',
  [switch]$NoPush
)
# 把成品发布到 GitHub Pages。
#
# 为什么用**独立的 gh-pages 分支**，而不是把 11.7 MB 的产物提交进 main：
# 产物是从 252 KB 的 _app3d.html 拼出来的，改一行源码就产生一个 11.7 MB 的
# 新 blob。几轮改动后 .git 就会膨胀到几百 MB，而换不回任何信息。
# main 保持只存源，gh-pages 只存一个 index.html —— 各自都干净。
#
# 用**独立的临时仓库**推那个分支，而不是在主仓库里 checkout --orphan：
# 后者会把工作区里的 55 个源文件变成未跟踪，稍不注意就误提交或误删。
# 临时仓库完全碰不到主工作区。
$ErrorActionPreference = 'Stop'
$stage = Join-Path $env:TEMP ('pkb-ghp-' + $Repo.Replace('/','-'))

Write-Output '=== 1/5 构建 ==='
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Dir '_build.ps1')
if ($LASTEXITCODE -ne 0) { throw "构建失败（退出码 $LASTEXITCODE）" }
$product = Join-Path $Dir 'partridge-3d.html'
$size = (Get-Item $product).Length
Write-Output ("    产物 {0:N0} bytes" -f $size)
if ($size -lt 5MB) { throw "产物只有 $size 字节，八成没构建对，先别推" }

Write-Output '=== 2/5 准备暂存目录 ==='
# 用 mavis-trash 而不是 Remove-Item -Recurse -Force —— 和本项目其他脚本一致，
# 万一路径变量写错，那是可恢复的删除而不是永久丢失。
if (Test-Path $stage) { mavis-trash $stage }
$null = New-Item -ItemType Directory -Path $stage -Force
Copy-Item $product (Join-Path $stage 'index.html') -Force

# ⚠️ 必须**不带 BOM**。PowerShell 5.1 的 `Set-Content -Encoding UTF8` 会写 BOM，
#    而 git 不一定认得出来，写进去的规则可能悄悄失效。
#    这条和 .ps1 必须带 BOM 正好相反 —— 区别在于「谁来读这个文件」：
#    .ps1 是 PowerShell 自己读（要 BOM），.gitattributes 是 git 读（不要 BOM）。
[IO.File]::WriteAllText((Join-Path $stage '.gitattributes'), "*.html -text`n", (New-Object Text.UTF8Encoding($false)))

Write-Output '=== 3/5 建 gh-pages 提交 ==='
Push-Location $stage
try {
  git init -q -b gh-pages
  git config core.autocrlf false      # 别做换行转换，Pages 要原样吐出构建产物
  git add -A
  # ⚠️ 改了 .gitattributes 之后，已经暂存的 blob **不会**自动更新 ——
  #    git 的 stat 缓存认为文件没变。必须 --renormalize 重新规整一遍。
  #    不这么做，入库的是换行转换过的版本，和磁盘字节不一致（2026-09-30 踩过）。
  git add --renormalize .
  git -c user.name='yydshly' -c user.email='288515785+yydshly@users.noreply.github.com' `
      commit -q -m "部署：鹧鸪骑单车 3D 成品（单文件 $([math]::Round($size/1MB,1)) MB）`n`n由 _build.ps1 的产物原样复制。完全自包含：three.js 与 8 首配乐都已内联，`n运行时零外部请求。字节与构建产物保持一致。"

  # 验：入库的 blob 必须等于磁盘上的字节
  $disk = git hash-object --no-filters -- index.html
  $blob = git rev-parse ':index.html'
  if ($disk -ne $blob) { throw "入库字节与磁盘不一致（$disk vs $blob）—— 换行规则没生效，别推" }
  Write-Output '    ✓ 入库字节 == 磁盘字节'

  if (-not $NoPush) {
    Write-Output '=== 4/5 推送 gh-pages ==='
    $remote = "https://github.com/$Repo.git"
    if ((git remote) -contains 'origin') { git remote set-url origin $remote } else { git remote add origin $remote }
    git push --force origin gh-pages 2>&1 | Select-Object -Last 2
    if ($LASTEXITCODE -ne 0) { throw "推送失败（退出码 $LASTEXITCODE）" }
  } else {
    Write-Output '=== 4/5 -NoPush：跳过推送 ==='
  }
} finally { Pop-Location }

Write-Output '=== 5/5 核对线上 ==='
if (-not $NoPush) {
  $u = "https://$($Repo.Split('/')[0]).github.io/$($Repo.Split('/')[1])/"
  $ok = $false
  for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 6
    try {
      $r = curl.exe -sSL --ssl-no-revoke -I --max-time 30 $u 2>$null | Out-String
      if ($r -match 'HTTP/[\d.]+ 200') {
        $len = if ($r -match '(?im)^content-length:\s*(\d+)') { [int64]$matches[1] } else { 0 }
        if ($len -eq $size) { $ok = $true; break }
        Write-Output ("    Pages 还没更新（Content-Length={0}，期望 {1}），再等" -f $len, $size)
      }
    } catch { }
  }
  if ($ok) {
    Write-Output ("    ✓ 线上 $u")
    Write-Output ("      HTTP 200，Content-Length = {0:N0}，与构建产物一致" -f $size)
  } else {
    Write-Output "    ⚠️ 没等到线上更新。去 https://github.com/$Repo/settings/pages 看构建状态"
  }
}
Write-Output ''
Write-Output "（暂存目录留在 $stage，可随时删）"
