$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding($false)

# 原始 MiniMax 构建是唯一出处，不改写其中的模型、动画或音乐。
& powershell -NoProfile -ExecutionPolicy Bypass -File $S_BUILD
if ($LASTEXITCODE -ne 0) { throw "MiniMax 构建失败：$LASTEXITCODE" }

# 只回收本仓库的生成目录，防止过期文件混入下一次发布。
if (Test-Path -LiteralPath $DIR_SITEBUILD) {
  $resolvedSite = [IO.Path]::GetFullPath($DIR_SITEBUILD)
  $expectedSite = [IO.Path]::GetFullPath((Join-Path $DIR_DIST 'site'))
  if ($resolvedSite -ne $expectedSite -or -not $resolvedSite.StartsWith([IO.Path]::GetFullPath($ROOT) + '\', [StringComparison]::OrdinalIgnoreCase)) { throw '生成目录越界' }
  mavis-trash $resolvedSite
  if (Test-Path -LiteralPath $resolvedSite) { throw '旧生成目录未成功回收' }
}
$null = New-Item -ItemType Directory -Path $DIR_SITEBUILD -Force
Copy-Item (Join-Path $DIR_SHOWCASE '*') $DIR_SITEBUILD -Recurse -Force
$experiment = [IO.File]::ReadAllText((Join-Path $DIR_CASE_LATEST 'experiment.json')) | ConvertFrom-Json
$runRecords = @()
foreach ($entry in $experiment.runs) {
  $runRoot = Join-Path (Join-Path $DIR_CASE_LATEST 'runs') $entry.directory
  $record = [IO.File]::ReadAllText((Join-Path $runRoot 'record.json')) | ConvertFrom-Json
  $demoRoot = Join-Path (Join-Path $DIR_SITEBUILD 'demos') $record.id
  $null = New-Item -ItemType Directory -Path $demoRoot -Force
  $originalArtifact = Join-Path $runRoot 'artifact\index.html'
  $deployedArtifact = Join-Path $demoRoot 'index.html'
  if ((Get-FileHash -LiteralPath $originalArtifact).Hash.ToLowerInvariant() -ne $record.artifactSha256 -or (Get-Item -LiteralPath $originalArtifact).Length -ne $record.artifactBytes) { throw "原始成品与记录不符：$($record.id)" }
  Copy-Item -LiteralPath $originalArtifact -Destination $deployedArtifact -Force
  if ((Get-FileHash -LiteralPath $originalArtifact).Hash -ne (Get-FileHash -LiteralPath $deployedArtifact).Hash) { throw "成品副本校验失败：$($record.id)" }
  $runRecords += $record
}
$experiment.runs = $runRecords
[IO.File]::WriteAllText((Join-Path $DIR_SITEBUILD 'data.json'), ($experiment | ConvertTo-Json -Depth 20), $utf8)
$csvRows = foreach ($record in $runRecords) {
  [pscustomobject][ordered]@{
    model = $record.name; setting = $record.setting; harness = $record.harness
    time_seconds = $record.timeSeconds; cost_cny = $record.costCny
    tokens = $record.tokens; api_requests = $record.requests
    cost_basis = $(if ($record.costBasis) { $record.costBasis } elseif ($null -eq $record.costCny) { 'not_provided' } else { 'user_bill' })
    cost_label = $(if ($record.costLabel) { $record.costLabel } elseif ($null -eq $record.costCny) { '未提供' } else { '账单支出' })
    interface_tokens_label = $record.interfaceStats.tokensLabel
    interface_tokens_per_second = $record.interfaceStats.tokensPerSecond
    cache_hit_rate_percent = $record.interfaceStats.cacheHitRatePercent
    interface_rounds = $record.interfaceStats.rounds
    interface_steps = $record.interfaceStats.steps
    interface_stats_source = $record.interfaceStats.source
    usage_source = $record.usageSource
  }
}
$csvRows | Export-Csv -LiteralPath (Join-Path $DIR_SITEBUILD 'data.csv') -Encoding UTF8 -NoTypeInformation
foreach ($folder in @('evidence','previews')) { Copy-Item (Join-Path $DIR_CASE_LATEST $folder) $DIR_SITEBUILD -Recurse -Force }
Copy-Item (Join-Path $DIR_CASE_LATEST 'prompt.txt') $DIR_SITEBUILD -Force
Copy-Item (Join-Path $DIR_DOCS 'demo-cover.jpg') (Join-Path $DIR_SITEBUILD 'previews\minimax.jpg') -Force
$minimaxRoot = Join-Path $DIR_SITEBUILD 'minimax'
$null = New-Item -ItemType Directory -Path $minimaxRoot -Force
Copy-Item -LiteralPath $PRODUCT -Destination (Join-Path $minimaxRoot 'index.html') -Force
Copy-Item -LiteralPath $PRODUCT -Destination (Join-Path $DIR_SITEBUILD (Split-Path $PRODUCT -Leaf)) -Force
if ((Get-FileHash -LiteralPath $PRODUCT).Hash -ne (Get-FileHash -LiteralPath (Join-Path $minimaxRoot 'index.html')).Hash) { throw 'MiniMax 发布副本校验失败' }
$downloadsRoot = Join-Path $DIR_SITEBUILD 'downloads'
$null = New-Item -ItemType Directory -Path $downloadsRoot -Force
Compress-Archive -LiteralPath $DIR_CASE_LATEST -DestinationPath (Join-Path $downloadsRoot 'partridge-bike-archive.zip') -CompressionLevel Optimal -Force
[IO.File]::WriteAllText((Join-Path $DIR_SITEBUILD '.nojekyll'), '', $utf8)
Write-Output "统一站点已构建：$DIR_SITEBUILD"
Write-Output '已验证：三份同题成品与 MiniMax 发布副本均保持原始字节。'
