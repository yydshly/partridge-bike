# ═══════════════════════════════════════════════════════════════
#  全仓库路径的唯一出处
# ═══════════════════════════════════════════════════════════════
#
#  为什么要有这个文件：28 个脚本里散落着 156 处硬编码文件名。
#  早期后果是「改文件名 → 漏改一处 → 那个 harness 静默跑空 →
#  所有检查照样全绿」。所以路径必须**只有一个出处**。
#
#  每个脚本在开头这样引用（3 行，**搬目录时永远不用改**）：
#
#      $p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
#      if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
#      . (Join-Path $p '_paths.ps1')
#
#  往上走而不是写死相对路径：脚本在根目录时是 '_paths.ps1'，
#  搬到 tools\gen\ 下就变成 '..\..\_paths.ps1' —— 写死的写法每次分层都要改 28 处。
#
#  ⚠️ 本文件自己的规则：
#     - 必须带 UTF-8 BOM（.ps1 通例，PowerShell 5.1 靠 BOM 认中文）
#     - 只定义变量 + 末尾自检，不做别的
#
#  📌 分层改造进度（2026-10-01 全部完成）：
#     A —— 路径唯一出处，脚本零处硬编码
#     C —— 产物落到 dist/
#     B —— 物理分层：src / assets / docs / tools / gen / templates / checks
#     无论后面怎么搬，都只改下面「目录」那一段。
$ErrorActionPreference = 'Stop'

# ── 目录：这一段是整个仓库的**布局开关** ──────────────────────
#  搬目录、改目录名、加目录，都只改这十几行。
#  28 个脚本的头部引导是「从 $PSScriptRoot 往上找 _paths.ps1」，
#  所以无论脚本自己在哪一层，都不用改。
$ROOT       = $PSScriptRoot
$DIR_SRC    = "$ROOT\src"             # _app3d.html（唯一可编辑源）+ _bgm-meta.json
$DIR_ASSETS = "$ROOT\assets"          # 构建输入与素材
$DIR_BGM    = "$DIR_ASSETS\bgm"       # bgm-*.mp3（8.2 MB，不可再生，唯一的副本）
$DIR_VENDOR = "$DIR_ASSETS\vendor"    # three149.min.js
$DIR_DOCS   = "$ROOT\docs"            # 截图等文档配图
$DIR_TOOLS  = "$ROOT\tools"           # _build / _deploy / _serve / _swap / _refactor
$DIR_GEN    = "$ROOT\gen"             # _mk*.ps1 生成器
$DIR_TPL    = "$ROOT\templates"       # _*.tpl.html 回归页模板
$DIR_CHECKS = "$ROOT\checks"          # 静态体检 + 编排器
$DIR_SELF   = "$DIR_CHECKS\self"      # 检查器自己的反查
$DIR_OUT    = "$ROOT\dist"            # 生成页（回归 harness、诊断页、实拍页）
$DIR_DIST   = "$ROOT\dist"            # 构建产物 partridge-3d.html

# dist/ 里**全部是生成的**，所以整目录进 .gitignore。
# 在这里建（而不是让每个生成器各自建）的好处是：搬目录时它跟着走，
# 而且任何一个脚本单独跑都不会因为「dist 不存在」而炸。
if (-not (Test-Path -LiteralPath $DIR_OUT)) {
  $null = New-Item -ItemType Directory -Path $DIR_OUT -Force
}

# ── 关键文件 ──────────────────────────────────────────────────
$APP       = "$DIR_SRC\_app3d.html"                         # 唯一可编辑源
$PRODUCT   = "$DIR_DIST\partridge-3d.html"                  # 构建产物
$BGM_META  = "$DIR_SRC\_bgm-meta.json"                      # 曲目表 + 歌词
$THREE_LIB = "$DIR_VENDOR\three149.min.js"                 # 构建输入
$README    = "$ROOT\README.md"
$AGENTS    = "$ROOT\AGENTS.md"
$SCREENSHOT= "$DIR_DOCS\screenshot.jpg"
$GITIGNORE = "$ROOT\.gitignore"
$GITATTRS  = "$ROOT\.gitattributes"

# ── tools/：一条命令跑完一件事的那些 ──────────────────────────
$S_BUILD     = "$DIR_TOOLS\_build.ps1"
$S_DEPLOY    = "$DIR_TOOLS\_deploy.ps1"
$S_SERVE     = "$DIR_TOOLS\_serve.ps1"
$S_SWAP      = "$DIR_TOOLS\_swap.ps1"

# ── checks/：判「代码对不对」的那些 ──────────────────────────
$S_CHECKALL  = "$DIR_CHECKS\_checkall.ps1"
$S_SYNTAX    = "$DIR_CHECKS\_syntaxcheck.ps1"
$S_FREEVAR   = "$DIR_CHECKS\_freevar.ps1"
$S_SCOPE     = "$DIR_CHECKS\_scopecheck.ps1"
$S_LINT      = "$DIR_CHECKS\_harnesslint.ps1"
$S_PAGES     = "$DIR_CHECKS\_pages.ps1"
$S_PATHCHECK = "$DIR_CHECKS\_pathcheck.ps1"

# ── checks/self/：判「上面这些判据自己靠不靠谱」的那些 ─────────
$S_SCOPETEST   = "$DIR_SELF\_scopetest.ps1"
$S_SYNTEST     = "$DIR_SELF\_syntest.ps1"
$S_FREEVARTEST = "$DIR_SELF\_freevartest.ps1"
$S_LINTTEST    = "$DIR_SELF\_linttest.ps1"
$S_PAGESTEST   = "$DIR_SELF\_pagestest.ps1"
$S_DRIVEWIRES  = "$DIR_SELF\_drivewires.ps1"
$S_PATHTEST    = "$DIR_SELF\_pathtest.ps1"

# ── gen/：生成器 ─────────────────────────────────────────────
$S_MKDRIVE     = "$DIR_GEN\_mkdrive.ps1"
$S_MKTRAFFIC   = "$DIR_GEN\_mktraffic.ps1"
$S_MKROUTE     = "$DIR_GEN\_mkroute.ps1"
$S_MKMOOD      = "$DIR_GEN\_mkmood.ps1"
$S_MKCRUISE    = "$DIR_GEN\_mkcruise.ps1"
$S_MKMOODSTATE = "$DIR_GEN\_mkmoodstate.ps1"
$S_MKUISTATE   = "$DIR_GEN\_mkuistate.ps1"
$S_MKDIAG      = "$DIR_GEN\_mkdiag.ps1"
$S_MKHARNESS   = "$DIR_GEN\_mkharness.ps1"
$S_MKPAUSE     = "$DIR_GEN\_mkpause.ps1"
$S_MKREC       = "$DIR_GEN\_mkrec.ps1"
# _mkdbg.ps1 是**实拍探针**，不是回归页生成器，所以单列（它只出临时页）
$S_MKDBG       = "$DIR_GEN\_mkdbg.ps1"

# ── templates/：九个回归页模板 ────────────────────────────────
$TPL_DRIVE     = "$DIR_TPL\_driveharness.tpl.html"
$TPL_TRAFFIC   = "$DIR_TPL\_trafficharness.tpl.html"
$TPL_ROUTE     = "$DIR_TPL\_routeharness.tpl.html"
$TPL_MOOD      = "$DIR_TPL\_moodharness.tpl.html"
$TPL_CRUISE    = "$DIR_TPL\_cruiseharness.tpl.html"
$TPL_MOODSTATE = "$DIR_TPL\_moodstate.tpl.html"
$TPL_CRUISEDIAG= "$DIR_TPL\_cruisediag.tpl.html"
$TPL_MUSIC     = "$DIR_TPL\_musicharness.tpl.html"
$TPL_BGM2      = "$DIR_TPL\_bgmharness2.tpl.html"

# ── 生成页（产物；不在 mustExist 里 —— 它们本来就可能还没生成）──
# 单独列出来而不是只给一个名字数组：名字数组没法被迁移工具认出来，
# 那一堆 `Join-Path $dir '_driveharness.html'` 就永远留在各个生成器里。
$OUT_DRIVE     = "$DIR_OUT\_driveharness.html"
$OUT_TRAFFIC   = "$DIR_OUT\_trafficharness.html"
$OUT_ROUTE     = "$DIR_OUT\_routeharness.html"
$OUT_MOOD      = "$DIR_OUT\_moodharness.html"
$OUT_CRUISE    = "$DIR_OUT\_cruiseharness.html"
$OUT_MOODSTATE = "$DIR_OUT\_moodstate.html"
$OUT_UISTATE   = "$DIR_OUT\_uistate.html"
$OUT_DIAG      = "$DIR_OUT\_cruisediag.html"      # _mkdiag 专用
$OUT_DBG       = "$DIR_OUT\partridge-dbg.html"    # _mkdbg/_mkpause/_mkrec 专用

# 页名（不含目录）—— _pages.ps1 清点、_pagestest.ps1 反查都用这个
$OUT_NAMES = @(
  '_driveharness.html','_trafficharness.html','_routeharness.html',
  '_moodharness.html','_cruiseharness.html','_moodstate.html','_uistate.html'
)

# 每页的断言记号：常规 harness 记 ok()，_uistate 记 uok()。
# 不在表里的一律按 ok 处理 —— 新页默认就被清点，是安全的那一侧。
$OUT_TOKENS = @{ '_uistate.html' = 'uok' }

# 反查（_pagestest.ps1）要动的三页。写在这儿而不是测试脚本里，是因为
# 「哪几页适合当反查靶子」是关于**这套页**的知识 ——
# 抄到测试脚本里就多一个会过期的地方，而过期的后果特别阴：
# 页被改名后反查去测一个不存在的文件，_pages.ps1 对着不存在的文件当然 exit 0，
# 四条反查于是全绿 —— 测的是一个已经不存在的东西。
$OUT_PROBE_MISSING = '_uistate.html'   # 当「缺页」靶子（也是唯一用 uok 的那页）
$OUT_PROBE_EMPTY   = '_moodharness.html' # 当「页在但零断言」靶子
$OUT_PROBE_COMMENT = '_routeharness.html' # 当「注释里的 ok( 不算断言」靶子（必须用 ok 页）

$outProbe = @($OUT_PROBE_MISSING, $OUT_PROBE_EMPTY, $OUT_PROBE_COMMENT)
$outProbeGone = @($outProbe | Where-Object { $OUT_NAMES -notcontains $_ })
if ($outProbeGone.Count -gt 0) {
  throw ("_paths.ps1 自检失败：反查用的页名不在 `$OUT_NAMES 里 -> " +
         [string]::Join(' ', $outProbeGone) +
         "`n页被改名/删除过，但 _pagestest.ps1 的反查还指着它 —— 那四条反查现在测的是一个不存在的文件。")
}

# ── 自检：所有**必须存在**的路径，缺一个就当场炸 ──────────────
#  这条是整个收口的地基：搬目录时路径写错，错误会在第一秒暴露，
#  而不是等到某个 harness 静默跑空、然后所有检查照样全绿。
#  「产物」和「生成页」不在检查范围 —— 它们本来就可能还没存在。
#
#  ⚠️ 这一份清单是**手工维护**的，所以它自己也会过期：加了新脚本却忘了
#  往里加一行，它就不会被这条自检覆盖。所以清单里每一项都必须同时
#  出现在上面的赋值里（_pathcheck.ps1 会反过来验这两份对不对得上）。
$mustExist = @(
  $APP, $BGM_META, $THREE_LIB, $README, $AGENTS, $SCREENSHOT, $GITIGNORE, $GITATTRS,
  $S_BUILD, $S_DEPLOY, $S_SERVE, $S_SWAP,
  $S_CHECKALL, $S_SYNTAX, $S_FREEVAR, $S_SCOPE, $S_LINT, $S_PAGES, $S_PATHCHECK,
  $S_SCOPETEST, $S_SYNTEST, $S_FREEVARTEST, $S_LINTTEST, $S_PAGESTEST, $S_DRIVEWIRES, $S_PATHTEST,
  $S_MKDRIVE, $S_MKTRAFFIC, $S_MKROUTE, $S_MKMOOD, $S_MKCRUISE, $S_MKMOODSTATE,
  $S_MKUISTATE, $S_MKDIAG, $S_MKHARNESS, $S_MKPAUSE, $S_MKREC, $S_MKDBG,
  $TPL_DRIVE, $TPL_TRAFFIC, $TPL_ROUTE, $TPL_MOOD, $TPL_CRUISE, $TPL_MOODSTATE,
  $TPL_CRUISEDIAG, $TPL_MUSIC, $TPL_BGM2
)
$missing = @()
foreach ($q in $mustExist) { if (-not (Test-Path -LiteralPath $q)) { $missing += $q } }
if ($missing.Count -gt 0) {
  throw ("_paths.ps1 自检失败：有 " + $missing.Count + " 个路径不存在`n  - " +
         ($missing -join "`n  - ") + "`n搬目录时最常见的原因：文件真被移走了但忘了更新本文件。")
}
