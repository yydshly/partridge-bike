param()
# 编排器 `_checkall.ps1` 自己的失败传播判据。
#
# ⚠️ 这道判据是从一次**真的假绿**来的。
#    `_checkall.ps1` 的 `Step` 函数是 `& $block; if ($LASTEXITCODE -ne 0) {…}`，
#    而 `$LASTEXITCODE` **只反映最后一次外部命令**。第 17 步里调了十一个子检查，
#    中间任何一个红了都会被后面成功的调用**盖掉**：
#      实测 `_pathtest` 退出 1，第 17 步照样打「全绿」，整轮 exit 0。
#    和 AGENTS.md 里那条「逐项都对、汇总是 0」是同一族病，
#    只是这次藏在一个**看起来很标准**的 PowerShell 惯用法里。
#
# 所以光「读源码看它有没有检查」不够 —— 那只是形状。
# 这里验的是**行为**：把生产代码里的 `Run` 抠出来真跑一遍，
# 造出「先失败后成功」这个**当初会漏报的组合**，断言它真的记了账。
$ErrorActionPreference = 'Stop'
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')

$st = @{ fail = 0 }
function Chk($name, $cond, $detail) {
  if ($cond) { Write-Output ('  PASS  ' + $name) }
  else { $st.fail++; Write-Output ('  FAIL  ' + $name); Write-Output ('        ' + $detail) }
}

$src = [IO.File]::ReadAllText($S_CHECKALL)

Write-Output '=== A) 形状：一个 Step 里有多条子检查时，不许再出现裸的 `& $ps` ==='
# ⚠️ 第一版这里写的是「整个文件不许有裸调用」，当场报了 3 处**假红**：
#    单子检查的 Step（`{ & $ps $S_BUILD }`）是**安全**的 ——
#    Step 自己的 $LASTEXITCODE 就是它，没有东西能盖掉。
#    真正出事的只有「一个 block 里连着调了好几个」那一种。
#    → 判据要断言的是「**这条性质在什么地方成立**」，不是「在所有地方成立」。
# 形状检查抽成函数，好样和坏样**共用同一段代码** ——
# 复制一份到反查里，那份就会自己过期。
function Get-BareRisk([string]$text) {
  $rxStep = [regex]'Step\s+''[^'']*''\s*\{'
  $out = @()
  foreach ($m in $rxStep.Matches($text)) {
    $depth = 0; $started = $false; $endAt = -1
    for ($k = $m.Index; $k -lt $text.Length; $k++) {
      if ($text[$k] -eq '{') { $depth++; $started = $true }
      elseif ($text[$k] -eq '}') { $depth--; if ($started -and $depth -eq 0) { $endAt = $k; break } }
    }
    if ($endAt -lt 0) { continue }
    $blk = $text.Substring($m.Index, $endAt - $m.Index + 1)
    # 子检查数 = Run 的次数 + 裸调用的次数
    $runN    = [regex]::Matches($blk, '(?m)^\s*Run\s+\$S_').Count
    $bareN   = [regex]::Matches($blk, '(?m)^\s*&\s*\$ps\s+\$S_').Count
    $nSubs   = $runN + $bareN
    # ⚠️ 条件是「子检查数 > 1 且**存在**裸调用」，不是「裸调用 > 1」。
    #   Step 的实现是 `& $block; if ($LASTEXITCODE -ne 0)`，
    #   而 $LASTEXITCODE **只反映最后一个**外部命令 ——
    #   所以「前面的子检查从来就没被检查过」，不是「被盖掉了」。
    #   只要这个 block 里有第二个子检查还走裸调用，它就没人管。
    #   （第一版写成 $bareN -gt 1，于是「2 个子检查里 1 个是裸的」逃过了，
    #     自己的反查都抓不住 —— 判据的近似条件比它要抓的病更窄。）
    if ($nSubs -gt 1 -and $bareN -gt 0) {
      $out += ('Step 里有 ' + $nSubs + ' 个子检查、其中 ' + $bareN + ' 个走裸调用：' + ($blk -split "`n")[0].Trim())
    }
  }
  # ⚠️ 这里**不能**写 `return , $out` 那个逗号：它会把空数组包成
  #    「一个元素是空数组的数组」，于是调用处 `@(...)` 之后 Count 恒为 1 ——
  #    判据在**一条裸调用都没有**的时候也会红（我第一版就栽在这儿）。
  return $out
}
$risky = @(Get-BareRisk $src | Where-Object { $_ })
Chk '真源码里没有「一个 Step 调两条以上子检查」的裸写法' ($risky.Count -eq 0) ($risky -join ' | ')
$nRun = [regex]::Matches($src, '(?m)^\s*Run\s+\$S_').Count
Chk 'Run 至少被用了十一次（第 17 步那十一个子检查）' ($nRun -ge 11) ('只用了 ' + $nRun + ' 次')
# 判据自己的反查：在**内存里**造一份带裸调用的源码，同一段逻辑必须抓到它。
# （不另开一个反查文件 —— 那样就多了一份会各自过期的代码。）
$fake = $src -replace 'Run \$S_SCOPE', '& $ps $S_SCOPE'
$fakeRisk = @(Get-BareRisk $fake | Where-Object { $_ })
Chk '反查：注入一个裸调用之后，同一段逻辑必须报出来（不是恒过）' `
    ($risky.Count -ne $fakeRisk.Count -and $fakeRisk.Count -ge 1) `
    ('注入前 ' + $risky.Count + ' 处，注入后 ' + $fakeRisk.Count + ' 处 —— 没抓到')
# ⚠️ 不能只写 `$src -match 'failNames'` —— Run/Step 的**定义**里就有 failNames，
#    那样这条判据会在「收尾根本没打印」的时候照样绿，又是一条恒过的假绿。
#    必须确认它出现在**失败分支**里。
$elseAt = $src.IndexOf('} else {', $src.IndexOf('全绿（harness'))
$tail = if ($elseAt -ge 0) { $src.Substring($elseAt) } else { '' }
Chk '失败分支会把失败的名字逐条列出来（不只是「N 项失败」）' `
    ($tail -match 'failNames' -and $tail -match 'exit 1') '收尾没有打印失败清单'

Write-Output ''
Write-Output '=== B) 行为：把生产代码里的 Run 抠出来真跑 ==='
# 用花括号配平把 `function Run(…) { … }` 整段抠出来。
$at = $src.IndexOf('function Run(')
Chk '能在 _checkall.ps1 里找到 Run 的定义' ($at -ge 0) '抠不到了 —— 判据的输入边界变了'
if ($at -lt 0) { exit 1 }
$depth = 0; $opened = $false; $endAt = -1
for ($k = $at; $k -lt $src.Length; $k++) {
  if ($src[$k] -eq '{') { $depth++; $opened = $true }
  elseif ($src[$k] -eq '}') { $depth--; if ($opened -and $depth -eq 0) { $endAt = $k; break } }
}
$body = $src.Substring($at, $endAt - $at + 1)
Chk '抠出来的 Run 源码看起来完整（以 function 开头、以 } 结尾）' `
    ($body.StartsWith('function Run(') -and $body.TrimEnd().EndsWith('}')) `
    ('长度 ' + $body.Length + ' 字')

$tmp = Join-Path $DIR_OUT '_stepfail'
if (Test-Path $tmp) { mavis-trash $tmp }
$null = New-Item -ItemType Directory -Path $tmp -Force
$badScript  = Join-Path $tmp 'bad.ps1'
$goodScript = Join-Path $tmp 'good.ps1'
[IO.File]::WriteAllText($badScript,  "exit 1`r`n", (New-Object Text.UTF8Encoding($true)))
[IO.File]::WriteAllText($goodScript, "exit 0`r`n", (New-Object Text.UTF8Encoding($true)))

$script:fail = 0
$script:failNames = @()
Invoke-Expression $body
Chk 'Run 被成功定义（抠出来的源码能执行）' ($null -ne (Get-Command Run -ErrorAction SilentlyContinue)) 'Invoke-Expression 之后没有这个函数'

if ($null -ne (Get-Command Run -ErrorAction SilentlyContinue)) {
  # 场景 A：**当初会漏报的那个组合** —— 先失败、后成功。
  $null = Run $badScript  | Out-Null
  $null = Run $goodScript | Out-Null
  Chk '先跑一个失败的、再跑一个成功的 → 必须记下 1 条失败' ($script:fail -ge 1) `
      ('fail=' + $script:fail + '（这就是原来静默吞掉的那一次）')
  Chk '...并且失败清单里点名了那个脚本' (($script:failNames -join ' ') -match 'bad\.ps1') `
      ('清单：' + ($script:failNames -join ' | '))

  # 场景 B：全成功时不能平白记账（否则又是一种「恒红」）
  $before = $script:fail
  $null = Run $goodScript | Out-Null
  $null = Run $goodScript | Out-Null
  Chk '两个都成功时不会多记（不制造假红）' ($script:fail -eq $before) `
      ('fail 从 ' + $before + ' 变成了 ' + $script:fail)

  # 场景 C：只跑一个失败的，必须记 1
  $before = $script:fail
  $null = Run $badScript | Out-Null
  Chk '单个失败的子检查也记 1 条' ($script:fail -eq ($before + 1)) `
      ('fail 从 ' + $before + ' 变成了 ' + $script:fail)
}

if (Test-Path $tmp) { mavis-trash $tmp }

Write-Output ''
if ($st.fail -eq 0) {
  Write-Output '  失败传播成立：没有裸调用，Run 逐条记账，「先失败后成功」也记下来了。'
  exit 0
}
Write-Output ('  stepfail 失败 ' + $st.fail + ' 条')
exit 1
