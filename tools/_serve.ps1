$ErrorActionPreference = 'Stop'
$port = 8931
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
$root = $ROOT

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()
Write-Output "serving $root on http://localhost:$port/"

while ($listener.IsListening) {
    try {
        $ctx  = $listener.GetContext()
        $path = $ctx.Request.Url.AbsolutePath.TrimStart('/')
        # 默认伺服**当前成品**。原来这里写死 'index.html'，而仓库根目录下
        # 那个 index.html 是早期 app 快照（40 KB，2026-09-29 的版本）——
        # 于是「本地预览」打开的其实是旧版，**而且它照样正常打开、照样有画面**，
        # 看起来完全没问题。2026-10-01 连同那个文件一起删掉了。
        if (-not $path) { $path = $PRODUCT.Substring($ROOT.Length + 1) }
        $file = Join-Path $root $path
        $isHead = ($ctx.Request.HttpMethod -eq 'HEAD')

        if (Test-Path -LiteralPath $file -PathType Leaf) {
            $ext = [IO.Path]::GetExtension($file).ToLowerInvariant()
            $mime = switch ($ext) {
                '.html' { 'text/html; charset=utf-8' }
                '.js'   { 'text/javascript; charset=utf-8' }
                '.css'  { 'text/css; charset=utf-8' }
                '.png'  { 'image/png' }
                default { 'application/octet-stream' }
            }
            $bytes = [IO.File]::ReadAllBytes($file)
            $ctx.Response.ContentType     = $mime
            $ctx.Response.ContentLength64 = $bytes.Length
            if (-not $isHead) { $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length) }
        } else {
            $ctx.Response.StatusCode = 404
            $b = [Text.Encoding]::UTF8.GetBytes('not found')
            $ctx.Response.ContentType     = 'text/plain'
            $ctx.Response.ContentLength64 = $b.Length
            if (-not $isHead) { $ctx.Response.OutputStream.Write($b, 0, $b.Length) }
        }
        $ctx.Response.Close()
    } catch {
        Write-Output "request error: $($_.Exception.Message)"
        try { $ctx.Response.Abort() } catch { }
    }
}