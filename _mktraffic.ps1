$ErrorActionPreference = 'Stop'
$dir = 'E:\minimax_code_project\0929_project\partridge-bike'
$lines = [IO.File]::ReadAllLines((Join-Path $dir '_app3d.html'))

function Find-Idx([string]$pat, [int]$from = 0) {
  for ($i = $from; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pat) { return $i } }
  return -1
}
# 找到「深度 0 的 }」——用来切出一个函数/语句块的结尾
function Block-End([int]$open) {
  $d = 0
  for ($i = $open; $i -lt $lines.Count; $i++) {
    $d += ([regex]::Matches($lines[$i],'\{')).Count - ([regex]::Matches($lines[$i],'\}')).Count
    if ($d -eq 0 -and $i -gt $open) { return $i }
    if ($d -eq 0 -and $i -eq $open -and $lines[$i] -match '\{\s*\}') { return $i }
  }
  return -1
}
function Dedent($block) {
  $block | ForEach-Object { if ($_.Length -ge 4) { $_.Substring(4) } else { '' } }
}

# ---- 1. 车道定义 ----
$i = Find-Idx '^const LANE_R = '
if ($i -lt 0) { throw "LANE_R not found" }
$lanes = $lines[$i]
"lanes : line $($i+1)  $lanes"

# ---- 2. layoutRider ----
$i = Find-Idx '^function layoutRider\(r, first\)\{'
if ($i -lt 0) { throw "layoutRider not found" }
$e = Block-End $i
if ($e -lt 0) { throw "layoutRider end not found" }
$layout = ($lines[$i..$e] -join "`n")
# 改名，好在外面套一层计数的壳 —— 切出来的真函数自己不会数调用次数
$layout = [regex]::Replace($layout, '(?m)^function layoutRider\(', 'function layoutRiderImpl(')
"layout: lines $($i+1)..$($e+1)"

# ---- 3. 车流 + 碰撞 ----
# ⚠️ 不能只找「第一处 路上的其他骑行者」。这个字符串在 2171 行的
#    layoutRider 注释里也出现过（讲朝向约定的那段），
#    而 cruiseTick 里也有一个 `for (const r of RIDERS){` ——
#    于是 Find 从 2172 往后一扫，**第一个**命中的是 cruiseTick 的循环，
#    真正的车流+碰撞段根本没被切进去。harness 照样生成、照样能跑、
#    照样可能全绿，测的却是另一个函数。
#    所以改成：遍历所有同名注释，逐个验证「它后面那个 RIDERS 循环
#    到碰撞夹取之间没有别的函数声明」，取第一个成立的。
$found = $false
for ($h = 0; $h -lt $lines.Count -and -not $found; $h++) {
  if ($lines[$h] -notmatch '路上的其他骑行者') { continue }
  $o = Find-Idx '^\s*for \(const r of RIDERS\)\{' ($h + 1)
  if ($o -lt 0) { continue }
  $l = Find-Idx 'S\.lat = Math\.max\(T_MIN - 0\.55' $o
  if ($l -lt 0) { continue }
  # 中间夹了别的函数声明 ⇒ 这个循环不是车流段
  $mid = Find-Idx '^\s*function \w+\(' ($o + 1)
  if ($mid -ge 0 -and $mid -lt $l) {
    "  (跳过第 $($h+1) 行的同名注释：后面那个循环在第 $($o+1) 行，但第 $($mid+1) 行就换了函数)"
    continue
  }
  $hdr = $h; $open = $o; $last = $l; $found = $true
}
if (-not $found) { throw "traffic block not found (header + RIDERS loop + collision clamp, no function in between)" }
$body = Dedent $lines[$open..$last]
"traffic: lines $($open+1)..$($last+1)  ($($body.Count) lines after dedent)"

# ---- 切对了没有：光看括号配平不够（切进别的函数照样可能配平）----
# 这段必须带得上碰撞冷却 S.hitT，而且**不能**带进 cruiseTick ——
# 后者自己也遍历 RIDERS，混进来会让 harness 测成一个混合体。
$bj = $body -join "`n"
if ($bj -notmatch 'S\.hitT') { throw "extracted block has no collision cooldown (S.hitT) — cut the wrong thing" }
if ($bj -match 'function cruiseTick') { throw "extracted block swallowed cruiseTick — the RIDERS loop match is ambiguous" }

$tpl = [IO.File]::ReadAllText((Join-Path $dir '_trafficharness.tpl.html'))
$tpl = $tpl.Replace('/*__LANES__*/',   $lanes)
$tpl = $tpl.Replace('/*__LAYOUT__*/',  "`n" + $layout + "`n")
$tpl = $tpl.Replace('/*__TRAFFIC__*/', "`n" + ($body -join "`n") + "`n")
[IO.File]::WriteAllText((Join-Path $dir '_trafficharness.html'), $tpl, (New-Object Text.UTF8Encoding($false)))
"harness bytes: {0:N0}" -f (Get-Item (Join-Path $dir '_trafficharness.html')).Length

# ---- 语法体检：括号配平 + 查有没有漏掉的大写标识符 ----
$t = [IO.File]::ReadAllText((Join-Path $dir '_trafficharness.html'))
$js = [regex]::Match($t, '(?s)<script>(.*)</script>').Groups[1].Value
$noStr = [regex]::Replace($js, "'(\\.|[^'\\])*'", "''")
$noStr = [regex]::Replace($noStr, '"(\\.|[^"\\])*"', '""')
$noStr = [regex]::Replace($noStr, '//.*$', '')
$noStr = [regex]::Replace($noStr, '/\*.*?\*/', '')
"paren balance : {0}" -f (([regex]::Matches($noStr,'\(')).Count - ([regex]::Matches($noStr,'\)')).Count)
"brace balance : {0}" -f (([regex]::Matches($noStr,'\{')).Count - ([regex]::Matches($noStr,'\}')).Count)
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir '_harnesslint.ps1') -Path (Join-Path $dir '_trafficharness.html')
# ⚠️ 这句 `exit` 千万不能少 —— 见 _mkdrive.ps1 末尾的说明：
#    子检查器失败了，但生成器不把退出码传出去，_checkall 就会判成「通过」。
exit $LASTEXITCODE
