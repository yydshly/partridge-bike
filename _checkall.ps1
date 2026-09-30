$ErrorActionPreference = 'Stop'
# 一条命令跑完全部验证。
# 顺序有讲究：先重建（后面的 harness 从 _app3d.html 切代码，源改了就得重新生成），
# 再跑三套回归，最后交付自检。作用域检查夹在中间，因为它只读源、不依赖 harness。
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
$dir = $ROOT
Set-Location $dir
$fail = 0
function Step($name, $block){
  Write-Output ''
  Write-Output ("========== {0} ==========" -f $name)
  & $block
  if ($LASTEXITCODE -ne 0) { $script:fail++; Write-Output ("  >>> {0} 退出码 {1}" -f $name, $LASTEXITCODE) }
}
# ⚠️ 第二个参数**必须叫 $Path**：调用处写的是 `& $ps $S_SYNTAX -Path $APP`，
#    命名参数按名字绑定。之前写成 $p，`-Path` 匹配不上就被丢进 $args，
#    $p 一直是 null，于是 _syntaxcheck.ps1 每次都因为「缺必填参数」退出 1 ——
#    两步语法检查一路假红，而错误信息被 Step 的输出吞掉，只剩一个退出码。
# ⚠️ $f / $Path 现在都是**绝对路径**（来自 _paths.ps1），这里不再拼 $dir。
#    再拼一次，路径就又有了第二个出处 —— 那正是 A 阶段要消掉的东西。
$ps = { param($f, $Path) if ($Path) { powershell -NoProfile -ExecutionPolicy Bypass -File $f -Path $Path } else { powershell -NoProfile -ExecutionPolicy Bypass -File $f } }

Step '1/16 构建'            { & $ps $S_BUILD }
Step '2/16 源码语法（注释/字符串配平）' { & $ps $S_SYNTAX -Path $APP }
Step '3/16 成品语法（注释/字符串配平）' { & $ps $S_SYNTAX -Path $PRODUCT }
# ⚠️ 这两步不是「保险」，是 2026-09-30 真抓到一个把整个 app 打死的东西：
#    frame() 里 `S.tSec += dt` 的 dt 全文件没声明过，每帧抛 ReferenceError、
#    画面全黑，而当时语法检查、作用域体检、六套 harness、交付自检**全绿**。
Step '4/16 源码自由变量（作用域链）'  { & $ps $S_FREEVAR -Path $APP }
Step '5/16 成品自由变量（作用域链）'  { & $ps $S_FREEVAR -Path $PRODUCT }
Step '6/16 面板初始状态（生成注入探针）' { & $ps $S_MKUISTATE }
Step '7/16 驾驶回归（生成）'  { & $ps $S_MKDRIVE }
Step '8/16 车流+碰撞（生成）' { & $ps $S_MKTRAFFIC }
Step '9/16 路段结构（生成）'   { & $ps $S_MKROUTE }
Step '10/16 时段×天气（生成）'  { & $ps $S_MKMOOD }
Step '11/16 自动巡航（生成）'   { & $ps $S_MKCRUISE }
Step '12/16 鹧鸪状态机（生成）' { & $ps $S_MKMOODSTATE }
Step '13/16 作用域体检'       { & $ps $S_SCOPE }
Step '14/16 交付自检' {
  $t = [IO.File]::ReadAllText(($PRODUCT))
  $src = Get-Item ($APP)
  $out = Get-Item ($PRODUCT)
  # ⚠️ 别写成 @( @('名字', $值), ... )：PowerShell 的数组子表达式会把嵌套
  #    数组**展平**，结果 $c[0] 拿到的是上一个判据的值而不是名字。两条平行数组。
  $names = @('尾标记 </html>', 'requestAnimationFrame ×2', '无调试残留', '8 首音轨内嵌',
             '对向公式 -(vr + v)*dt', '旧的漏 -v 公式已无', '成品不比源旧',
             '巡航接线在成品里', '避让参照系不跟着车跑',
             '以 <!DOCTYPE html> 开头', 'DOCTYPE 后没有游离文字',
             '有录一段按钮', '录像有隐藏切走保护', '录像声明了没有声音',
             'moodTick 接线在成品里', '回头看区间不是空的',
             '疲劳速度项范围拉得开', 'moodTick 排在碰撞之后',
             'frame 自己声明了 dt',
             '重置是函数不是内联语句', '重置键调它', '声音键在引擎没起来时不点亮',
             '播放键看 want && started', '镜头拖动会灭预设灯')
  $vals = @(
    $t.TrimEnd().EndsWith('</html>'),
    (([regex]::Matches($t,'requestAnimationFrame\(frame\);')).Count -eq 2),
    (([regex]::Matches($t,'\?dbr|slipProbe|dirProbe|speedProbe|TEMP dbg')).Count -eq 0),
    (([regex]::Matches($t,"b64:'")).Count -eq 8),
    (([regex]::Matches($t,[regex]::Escape('r.position.x -= (u.vr/3.6 + v) * dt;'))).Count -eq 1),
    (([regex]::Matches($t,[regex]::Escape('r.position.x -= (u.vr/3.6) * dt;'))).Count -eq 0),
    ($out.LastWriteTime -ge $src.LastWriteTime),
    (([regex]::Matches($t,[regex]::Escape('S.steerIn = S.cruise ? cruiseTick(dt)'))).Count -eq 1),
    # 参照系必须固定在「中线」上。用 S.lat 当参照会在边界上抖出极限环
    # （_cruiseharness 反查 d：8 秒 8 次切换 vs 固定参照 2 次）。
    (([regex]::Matches($t,[regex]::Escape('if (Math.abs(r.position.z) > AVOID_HIT &&'))).Count -eq 1),
    # ⚠️ DOCTYPE 曾经被截成「ctype html>」留在文件最前面：浏览器进 quirks 模式，
    #    而且那段垃圾文字直接渲染在页面左上角（截图里能看见）。
    #    两个判据都要：光看开头不够，得确认 doctype 和 <html> 之间没有别的文本。
    ($t.TrimStart().StartsWith('<!DOCTYPE html>')),
    ([regex]::IsMatch($t, '(?s)^\s*<!DOCTYPE html>\s*<html')),
    (([regex]::Matches($t,'id="bRec"')).Count -eq 1),
    # 切到后台标签页时 Chromium 冻结 rAF，画布不再提交，captureStream
    # 录出来是静止画面**而且不报错**。所以必须监听 visibilitychange 收尾。
    (([regex]::Matches($t,[regex]::Escape('if (document.hidden) recStop();'))).Count -eq 1),
    # 音乐走 <audio>、和 Web Audio 音效总线是两套，录不进画面。
    # 必须在界面上写明，别让人以为是坏了。
    (([regex]::Matches($t,[regex]::Escape('没有声音'))).Count -ge 2),
    # ── 鹧鸪状态机（_moodstate.html 41 项）──
    (([regex]::Matches($t,[regex]::Escape('    moodTick(dt);'))).Count -eq 1),
    # ⚠️ 回头看的边界曾经写成 `dx > -6.5 || dx < -0.5` —— 两端点反了，
    #    那个区间是**空的**，这个功能从头到尾一次都没触发过，是 _moodstate 抓出来的。
    #    交付自检钉住正确的写法，免得回归没跑的时候又改回去。
    (([regex]::Matches($t,[regex]::Escape('if (dx > -0.5 || dx < -6.5) continue;'))).Count -eq 1),
    # 速度次项的范围：慢速 0.35 封顶、满速 1.0。曾经写成 (0.55 + 0.45*fast)，
    # 慢速骑上限 0.55，永远够不到 0.55 的台词门槛。
    (([regex]::Matches($t,[regex]::Escape('(0.35 + 0.65*fast)'))).Count -eq 1),
    # moodTick 必须排在碰撞块**之后**：它判惊吓看的就是 S.hitT 刚被设成 0.70 的那一帧。
    # ⚠️ 这一项开头是 **两个** `(`（外面一层包住整个比较式），底下要闭两个。
    #    少闭一个的话，后面那行收 `@(` 的 `)` 就被吃掉了，报错还落在几十行之后的
    #    `}` 上（"子表达式中缺少右)"），查起来极其误导。
    (([regex]::Match($t, 'S\.hitT\s*=\s*0\.70;').Index -lt [regex]::Match($t, 'moodTick\(dt\);').Index)),
    # ⚠️ 这一行曾经**不存在**。frame() 里 `S.tSec += dt` 而 dt 全文件没声明过，
    #    每帧 ReferenceError、画面全黑，而当时所有检查全绿。
    #    自由变量体检（4/15、5/15）会抓到它；这里再钉一道字面写法，
    #    免得哪天只跑交付自检就把它放过去了。
    (([regex]::Matches($t,[regex]::Escape('const dt = Math.min(0.05, clock.getDelta());'))).Count -eq 1),
    # ── 面板：按钮灯必须和状态一致（_uistate.html 34 项在验这个）──
    # 重置曾经是内联的一条语句，只清了 9 个字段：鸟还是累的、saidTired
    # 还挂着、压草减速还在、巡航还在跑而灯没灭。改成函数 + S0 单一出处。
    (([regex]::Matches($t,[regex]::Escape('function resetRide(){'))).Count -eq 1),
    (([regex]::Matches($t,[regex]::Escape("addEventListener('click', () => resetRide());"))).Count -eq 1),
    # 声音灯在 AudioContext 建起来之前不许点亮 —— 亮着却没声音更像坏了
    (([regex]::Matches($t,[regex]::Escape("if (!AU.ready){"))).Count -ge 1),
    # 播放键字形必须看「真的在不在放」，want 从一开始就是 true 而一个音没响
    (([regex]::Matches($t,[regex]::Escape("(BGM.want && BGM.started) ? '⏸' : '▶'"))).Count -eq 1),
    # 手一动镜头，机位预设灯就得灭
    (([regex]::Matches($t,[regex]::Escape('camPresetOff();'))).Count -ge 2)
  )
  $bad = 0
  for ($i = 0; $i -lt $names.Count; $i++){
    Write-Output ("  {0}  {1}" -f $(if($vals[$i]){'PASS'}else{'FAIL'}), $names[$i])
    if (-not $vals[$i]) { $bad++ }
  }
  Write-Output ("  源 {0:N0} / 成品 {1:N0} bytes" -f $src.Length, $out.Length)
  $script:fail += $bad
}
Step '15/16 作用域检查器自检（喂它一份已知坏样本）' { & $ps $S_SCOPETEST }
Step '16/16 语法/自由变量/悬空调用 检查器自检' {
  & $ps $S_SYNTEST
  & $ps $S_FREEVARTEST
  & $ps $S_LINTTEST
  & $ps $S_PAGESTEST
  & $ps $S_DRIVEWIRES
}

Write-Output ''
# 页面清点放在最前面：缺页 / 一条断言都没有，本身就该算失败。
# 逻辑在 _pages.ps1 里，单独拆出来是因为写在 checkall 里就**验不到它自己** ——
# 想测「缺页会不会红」得先挪走一页，可第 9 步立刻会把它重新生成出来。
# 它本身有 4 条反查（_pagestest.ps1），第 16 步会验。
& $ps $S_PAGES
$pageBad = $LASTEXITCODE
if ($pageBad -ne 0) { $fail++ }

if ($fail -eq 0) {
  # 这里**不许写死任何条数**。原来那七行手打数字已经骗过人：
  #   _uistate 写着 34，实际当时已经 50（写完忘了改）。
  # 而且就算当场写对也不准 —— 静态调用点数 ≠ 运行时条数
  # （_moodharness 调用点 137、运行时 448，循环会展开），
  # 「从文件里数一遍」也只是一个看着像条数的数。真条数看页面标题 PASS n/m。
  Write-Output ''
  Write-Output '########## 全绿（harness 页面本身要人眼在浏览器里看一眼）##########'
  Write-Output '  上面那份就是页面清点。真条数：浏览器打开 _*.html 看标题 PASS n/m。'
  Write-Output '  （含 180 秒真实车流集成回归；每项浏览器里打开 _*.html 自查）'
  Write-Output '  ⚠️ 以上是脚本能判的。画面本身只能靠真机打开 partridge-3d.html 看：'
  Write-Output '     2026-09-30 就是「全绿 + 画面全黑」交出去的（frame() 缺 dt 声明）。'
} else {
  Write-Output ("########## {0} 项失败 ##########" -f $fail)
  exit 1
}