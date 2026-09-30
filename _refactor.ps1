param()
# 一次性迁移工具：把 28 个脚本里散落的硬编码路径，收口到 _paths.ps1。
#
# 它只做两件机械的事，剩下的散落写法留给人工：
#   ① 在每个脚本开头插入「往上找 _paths.ps1」的三行引导（+ 保留原来的 $dir/$d/$root 变量名）
#   ② 把 Join-Path $dir '文件名' 换成 _paths.ps1 里的对应变量
#
# ⚠️ 它**故意不碰**注释行、here-string 内部、以及 `& $ps '_build.ps1'` 这类
#    非 Join-Path 写法 —— 那几处要人工看，机器改容易改出恒过的假绿。
#    跑完会把「改了多少、哪些没动」打印出来，没动的部分就是待办清单。
$ErrorActionPreference = 'Stop'
$dir = 'E:\minimax_code_project\0929_project\partridge-bike'
$pathsFile = Join-Path $dir '_paths.ps1'

# ── 从 _paths.ps1 自动推出「文件名 → 变量」映射 ──────────────
$map = @{}
foreach ($line in [IO.File]::ReadAllLines($pathsFile)) {
  if ($line -match '^\$(\w+)\s*=\s*"\$(?:ROOT|DIR_\w+)(.*)"\s*$') {
    $var = $Matches[1]
    $leaf = Split-Path $Matches[2] -Leaf
    if ($leaf -and -not $map.ContainsKey($leaf)) { $map[$leaf] = "`$$var" }
  }
}
Write-Output ("从 _paths.ps1 推出 {0} 条映射" -f $map.Count)

# ── 三行引导：往上找，搬目录时永远不用改 ─────────────────────
$BOOT = @(
  '$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p ''_paths.ps1''))) { $p = Split-Path $p -Parent }',
  'if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }',
  '. (Join-Path $p ''_paths.ps1'')'
)

$enc = New-Object Text.UTF8Encoding($true)   # 带 BOM：.ps1 通例
$report = @()
foreach ($f in (Get-ChildItem $dir -Filter *.ps1 | Where-Object { $_.Name -ne '_paths.ps1' })) {
  $lines = [IO.File]::ReadAllLines($f.FullName)
  $orig  = [string]::Join("`n", $lines)
  $isComment = { param($s) $s -match '^\s*#' }

  # ① 头部：把绝对路径定义换成引导
  $didBoot = $false
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if (& $isComment $lines[$i]) { continue }
    # 形态 A/B：$dir = '...'   /  $dir  = '...'
    if ($lines[$i] -match '^\$(dir|d|root)\s*=\s*''E:\\') {
      $name = $Matches[1]
      $lines[$i] = (@($BOOT) + "`$" + $name + ' = $ROOT') -join "`r`n"
      $didBoot = $true
      break
    }
    # 形态 C：param([string]$Dir = 'E:\...')  →  去掉默认值，改为引导里给
    if ($lines[$i] -match '^\s*\[string\]\$(Dir|Dir)\s*=\s*''E:\\') {
      $lines[$i] = $lines[$i] -replace '\s*=\s*''E:\\[^'']*''',''
      $after = @('') + $BOOT + @("`$Dir = `$ROOT")
      $lines = @($lines[0..$i]) + $after + @($lines[($i+1)..($lines.Count-1)])
      $didBoot = $true
      break
    }
  }
  # 形态 D：完全没写绝对路径，但仍在仓库里 → 在 $ErrorActionPreference 之后插引导
  if (-not $didBoot) {
    $idx = 0..($lines.Count-1) | Where-Object { $lines[$_] -match '^\$ErrorActionPreference' } | Select-Object -First 1
    if ($null -ne $idx) {
      $lines = @($lines[0..$idx]) + @($BOOT) + @($lines[($idx+1)..($lines.Count-1)])
      $didBoot = $true
    }
  }
  if (-not $didBoot) { $report += [pscustomobject]@{ File=$f.Name; Boot='未插入'; Repl=0; Left='（需人工看头几行）' }; continue }

  # ② Join-Path $dir 'X'  →  $VAR
  $repl = 0
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if (& $isComment $lines[$i]) { continue }
    $lines[$i] = [regex]::Replace($lines[$i], "Join-Path \`$(dir|d|root) '([^']+)'", {
      param($m)
      $leaf = $m.Groups[2].Value
      if ($map.ContainsKey($leaf)) { $script:repl++; return $map[$leaf] }
      return $m.Value
    })
  }

  [IO.File]::WriteAllText($f.FullName, ([string]::Join("`r`n", $lines)), $enc)

  # ③ 报告：还剩哪些硬编码路径字面量（人工待办）
  $left = @()
  $now = [IO.File]::ReadAllText($f.FullName)
  foreach ($mm in [regex]::Matches($now, "'([A-Za-z0-9_\-\.]+\.(?:ps1|html|json|mp3))'")) {
    $leaf = $mm.Groups[1].Value
    if ($map.ContainsKey($leaf)) {
      $ln = ($now.Substring(0,$mm.Index) -split "`n").Count
      $src = (Get-Content $f.FullName)[$ln-1]
      if ($src -notmatch '^\s*#' -and $src -notmatch '^\s*(//|\*)') { $left += $leaf }
    }
  }
  $report += [pscustomobject]@{ File=$f.Name; Boot='已插入'; Repl=$repl; Left=($left | Sort-Object -Unique) -join ' ' }
}

Write-Output ''
$report | Sort-Object File | ForEach-Object {
  "  {0,-20} 引导 {1}  替换 {2,2} 处  仍残留: {3}" -f $_.File, $_.Boot, $_.Repl, $(if($_.Left){$_.Left}else{'无'})
}
$total = ($report | Measure-Object -Property Repl -Sum).Sum
Write-Output ''
Write-Output ("共替换 {0} 处。上面「仍残留」那一列就是人工待办。" -f $total)
