# 鹧鸪骑单车 3D · Partridge on Wheels

![鹧鸪骑单车](docs/screenshot.jpg)

一只鹧鸪骑车。Three.js 单文件动画，**11.7 MB，一个 HTML 文件就是全部**——
不需要联网、不需要装任何东西、不需要起服务器。

## ▶ 在线玩

**https://yydshly.github.io/partridge-bike/**

手机上也能开。**要点一下画面才会动**——浏览器要求先有真实手势，
否则不放声音也不起步。手机上面板会自动改成窄屏排版，24 个按钮每个都 ≥42px 高；
手势是**拖**（环绕）、**捏合**（缩放）、**双指拖**（平移）。

> ⚠️ 键盘快捷键在手机上不存在：`A`/`D`/`W`/`S`/`N`/`B`/`空格`/`F` 都要有物理键盘。
> 手机上除了 `F`，用面板上的「⛶ 电影模式」按钮。

### 电影模式（`F` 或面板上的 ⛶）

点一下进、点一下出。**全屏 + 把面板和 HUD 藏起来，只留画面**；
动一下鼠标 / 手指 / 滚轮，界面 2.6 秒后自动淡回来。

**面板虽然藏了，但功能没跟着丢** —— 画面里会浮出一条极简控制条
（`▶ 播放/暂停 · ◀ 上一首 · 下一首 · 自动 · ⤢`），不碰鼠标就自己藏起来；
**右下角**还有一个**侧边小框**，写着现在放的是哪首和这一句歌词
（曲名原来只写在面板上，面板一藏就看不见了）。

再按 **`H`**（或点浮条上的 `⤢`）进入**纯画面**：连浮条和侧边框一起藏掉，
只剩鹧鸪和它的台词。手机上没键盘就用 `⤢`。

五处值得说明：

- **两个盒子都不许待在「正中」。** 第一版把侧边框竖着摆在右侧正中，
  一眼看过去就是横穿画面、一直挡着鹧鸪骑行的视线 —— 这是试出来的，不是设计出来的。
  所以底部让成三块：**左浮条 / 中台词 / 右侧边框**，谁也不压谁；
  竖屏（390px 装不下 256 + 210 并排）时侧边框回**右上角**。
  判据钉的是「不许待在竖向中间那条带子里」，不写死上下左右，
  竖屏在右上、桌面在右下都算过，只有正中不行。
- **「全屏」和「藏界面」是两件独立的事。** 浏览器要求 `requestFullscreen()`
  必须在用户手势那一拍**同步**调用，所以它有概率被拒（iframe 没放行、
  iOS 对非元素的全屏限制、没真实交互）。**全屏失败也要照样藏界面**，
  否则一进 iframe 整个功能就废了。实测：手机上「电影模式」照样生效，只是没全屏。
- **Esc 退全屏后，电影模式会跟着退。** 否则界面还藏着、而人已经以为回到普通模式，
  看着像「按钮全不见了」。
- **面板和浮条是同一组操作的两个入口**，处理器只有一份、刷新也只有一份
  （`paintBgm()`）。写两遍就会出现「浮条亮着、面板灭着」，而状态其实只有一个值。
- 浮条**默认是藏着的**，而且只有淡回来的时候才接管鼠标事件 ——
  否则一条看不见的浮条会躺在画面正中下方，把「拖镜头」的手势全吃掉。

台词（`.cap`）和歌词（`.lyric`）**故意留着**——它们是内容不是界面。
想连它们一起藏，改 `src\_app3d.html` 里 `.cin` 那段 CSS 的注释写明的地方即可。

> ⚠️ 网页里点 `F` 之前**必须先点一下画面**：浏览器没拿到真实手势之前不放声音也不起步。
> `F` 键在 `file://` 直开和手机上都能用；全屏本身受浏览器策略限制，不保证一定进得去。

> 线上这份是从 `gh-pages` 分支发布的，它就是 `tools\_build.ps1` 的产物，一个字节都没改。
> `main` 分支里**没有**这个 11.7 MB 的文件，原因见下。

## 或者本地跑

克隆下来**直接双击是打不开的**。这个仓库只存源，11.7 MB 的
`partridge-3d.html` 是构建产物，不在版本库里。

```powershell
git clone https://github.com/yydshly/partridge-bike.git
cd partridge-bike
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\_build.ps1
```

看到 `built partridge-3d.html  … bytes`（11.7 MB 上下）就成了，
之后**双击 `dist\partridge-3d.html`** 即可运行（`file://` 直开，不需要起服务）。

**为什么不把成品提交进 `main`**：它是 252 KB 的 `src\_app3d.html` 拼出来的，
改一行源码就产生一个 11.7 MB 的新 blob。几轮改动后 `.git` 就会膨胀到
几百 MB，而换不回任何信息——那些内容都能重建。要部署就用 `gh-pages` 分支。
`tools\_build.ps1` 需要三样东西，全都在仓库里：`src\_app3d.html`、`assets\bgm\*.mp3`、
`assets\vendor\three149.min.js`。

### 目录长什么样

```
partridge-bike\
  _paths.ps1        ← 全仓库路径的唯一出处
  README.md  AGENTS.md
  src\              唯一可编辑源 _app3d.html + 曲目表 _bgm-meta.json
  assets\
    bgm\            8 首 MP3（8.2 MB，**不可再生**）
    vendor\         three149.min.js
  docs\             截图
  templates\        9 个回归页模板
  gen\              13 个生成器（_mk*.ps1），从 _app3d.html 切代码段造回归页
  tools\            _build / _deploy / _serve / _swap / _refactor / _runpages
  checks\           编排器 _checkall.ps1 + 10 个判据
    self\           10 个「判据自己靠不靠谱」的反查
  dist\             **全部产物**，整目录在 .gitignore 里
  .github\workflows\  verify.yml（CI：Windows + PowerShell 5.1，跑全 20 步）
```

根目录只剩 5 个文件 —— 「哪个是源、哪个是产物」不用再靠记。

`dist\` 由 `_paths.ps1` 自动创建，跑任何脚本都不用先手动建它。

## 怎么玩

| 操作 | 效果 |
|---|---|
| **拖拽** / **滚轮** / **右键** | 环绕 / 缩放 / 平移镜头 |
| **空格** | 播放 / 暂停 |
| **拖速度滑杆** | 加速（按住不放 = 持续给油） |
| **A** / **D** | 打方向 |
| **W** / **S** | 加速 / 刹车 |
| **N** / **B** | 上一首 / 下一首 |

面板里还有：重置、**自动巡航**、6 个机位预设、3 个时段（白天/黄昏/夜晚）、
4 种天气（晴/雨/雪/雾）、音乐控制、声音开关、鹧鸪叫声开关、
录 10 秒 WebM、保存当前帧 PNG。

**开自动巡航**，它会自己循线、遇对向车按余量选边让开、遇障碍收油，
还会冒几句「我从左边过去」。

## 里面有什么

- **5 km 一圈**，六段路：村口 → 河堤 → 林荫 → 长坡 → 镇子 → 长桥。
  换段会换风景、换曲子、喊一句报站。
- **时段 × 天气**是两张正交的表（3 × 4），改配色只改表、不改逻辑。
  雨会把路面打湿——反光变亮、胎噪也跟着变响；雪在地面盖一层白；
  雾缩短能见度。
- **鹧鸪是有状态的**：会累（骑久了说「腿有点酸」）、会被车吓到、
  雨天会抖水、侧方来车会扭头看、眼睛会眨——而且疲劳越高眨得越勤。
  它不掷骰子，每一次反应都由确定的输入决定。
- **车流**是对向车道 + 同向车道，右侧通行，会撞。
- **8 首配乐**（AI 生成），其中 6 首带歌词字幕。音乐走 `<audio>` 通道，
  录出来的 WebM **没有声音**。

## 仓库结构

| | |
|---|---|
| `src/_app3d.html` | **唯一可编辑源**（252 KB，带两个占位符） |
| `assets/bgm/*.mp3` | 配乐源文件（8.2 MB，AI 生成，不可再生） |
| `src/_bgm-sha256.json` | 上面那 8 个 mp3 的**内容基线**（sha256 + 字节数），见下面「素材不可再生」 |
| `assets/vendor/three149.min.js` | three.js r149，构建时内联 |
| `_paths.ps1` | **全仓库路径的唯一出处**（下面每一个路径都从它来） |
| `tools/_build.ps1` | 把上面三样拼成 `dist\partridge-3d.html` |
| `checks/_checkall.ps1` | **一条命令跑完全部验证**（20 步） |
| `templates/_*.tpl.html`（9 个） | 回归页模板，套桩用 |
| `gen/_mk*.ps1`（13 个） | 生成器：从源文件**切代码段**造回归页 |
| `checks/`（11 个判据） | `_syntaxcheck` `_freevar` `_scopecheck` `_harnesslint` + `_pages` 清点 + `_pathcheck` 路径收口 + `_doccheck` 文档防漂移 + `_cicheck` CI 配置 + `_bgmhash` 配乐内容基线 + `_eventtarget` 事件监听目标 + `_stepfail` 失败传播 |
| `checks/self/`（10 个） | 「判据自己靠不靠谱」的反查 |
| `tools/` | `_build` `_deploy` `_serve` `_swap` `_refactor` `_runpages` |
| `.github/workflows/verify.yml` | CI：Windows runner + PowerShell 5.1，跑全 20 步 |
| `dist/` | 全部产物：成品 + 8 个回归页 + 1 诊断页 + 3 个探针页（整目录 gitignore） |
| `AGENTS.md` | 项目记忆与方法论（踩过的坑都在里面） |
| `.gitignore` | 排除 `dist\`（= 14 个产物：1 成品 + 3 探针 + 9 回归页 + 1 诊断页） |

**路径只有一处出处。** 32 个脚本开头都是这三行，从 `$PSScriptRoot` 往上找 `_paths.ps1`——

```powershell
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
```

所以**搬目录、改文件名、挪产物位置，只改 `_paths.ps1` 里的目录定义**，
其余文件一个字都不用动。`_paths.ps1` 末尾会自查 52 个必须存在的路径，
搬错了在第一秒就炸，而不是等到某个 harness 静默跑空、而所有检查照样全绿。

**`.ps1` 必须是 UTF-8 with BOM。** 少了 BOM，PowerShell 5.1 会按 ANSI
解码中文，报出来的是莫名其妙的 `Unexpected token`，看起来像语法写错、
实际是编码被动了。所以仓库里放了 `.gitattributes` 关掉换行/编码转换。

## 验证

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\checks\_checkall.ps1
```

20 步：构建 → 语法（源码 + 成品）→ 自由变量/作用域 ×2 → 面板状态探针
→ 窄屏 + 触屏手势 → 重新生成八个回归页 → 静态语义体检（作用域 + 事件监听目标）→ 交付自检
→ 十套检查器的自检 → 路径收口 → 音频完整性 → 页面清点 → **文档防漂移**。

## 素材不可再生，所以给它上了内容基线

`assets/bgm/` 里那 8 个 mp3 是 8.2 MB、**仓库里只有这一份**的素材。
第 19 步会把成品里的 base64 解码回来跟它们逐字节比——但它防的是
「构建时用错文件 / base64 在传输中坏掉」，**防不住 mp3 本身被换掉**：
换掉之后重新构建，产物和盘上文件会一起变，那一步仍然全绿。

所以 `src/_bgm-sha256.json` 钉的是「这些 mp3 就是当初那批」（sha256 + 字节数，
字节数也记是因为「大小一样而内容变了」才是最隐蔽的那种替换）。
`checks\_bgmhash.ps1` 从**三个方向**查：盘上有而基线里没有、基线里有而盘上没了、
两边都有但值不对——每一条都点名到具体文件。

有意换素材（换歌、重新压制）就重新生成基线，别手改：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\checks\_bgmhash.ps1 -Update
```

基线是**代码生成的**，不是人手抄的字段——`-Update` 和
`checks\self\_bgmhashtest.ps1` 造坏样共用同一段计算，否则那份「怎么更新」
会自己过期而没人发现。

## 「事件绑在谁身上」也是一道常驻判据

`syncFs` 当初写成了顶层裸 `addEventListener('fullscreenchange', …)`——
那个 `this` 是 window，而 `fullscreenchange` 只在 document 上派发且不冒泡，
于是它**一次都没跑过**：Esc 退全屏后界面还藏着。

能防住这一处的检查**必须在真浏览器里跑**（得真的进全屏、真按 Esc），
而 GitHub 的 CI 跑不了浏览器页面。动态反查能抓住它测过的那一处，
但以后再写第二处、第三处，没人会记得去扩那条反查。

所以 `checks\_eventtarget.ps1` 把它提成**纯静态**判据：源码里凡是监听
「只在 document 上派发且不冒泡」的事件，对象必须是 `document.`，
裸写或写成 `window.` 都判红，并**点名到行号**（行号剥注释时保住行结构，
否则会前移，人跳过去根本找不到）。

⚠️ 那张事件表**只收本项目实测过的事件**，不凭记忆扩充——会误报的守卫最后会被关掉。
一个刻意不收的例子是 `visibilitychange`：它的「冒不冒泡」各来源自相矛盾
（caniuse 的兼容性注记说 Safari 14 之前不冒泡，MDN 新页面却标 `Bubbles: Yes`），
本机也实测不了（只在真实切标签时触发）。那一行改成绑 `document.`
绕开了这个问题——**绑到事件的 target 上，在所有浏览器所有版本上都成立**。

**它只证明「能生成、能通过静态检查」，证明不了画面。** 画面只能靠真机打开
`dist\partridge-3d.html` 看一眼——2026-09-30 就交过一版**所有检查全绿、画面全黑**
的成品（`frame()` 里用了没声明的 `dt`，每帧抛 `ReferenceError`）。
所以**冒烟测试是交付流程的一部分，不是可选项**。

**文档也会漂，而且没有任何脚本会读它**——B 阶段把 47 个文件搬进 8 个目录之后，
`AGENTS.md` 最顶上那节「构建」一个字都没跟着搬，里面两条命令照抄就报错。
第 20 步的 `_doccheck.ps1` 就是为这件事存在的：它查文档里每条 `-File` 命令的
路径是否真实存在、声明的总步数是否等于 `_checkall` 实际步数、点名的产物名
`_paths.ps1` 是否认得。它自己第一版有个**永远不会红的判据**（正则漏了捕获组），
所以配了 `checks\self\_doctest.ps1` 四条反查。

九套回归页在 `dist\`，是浏览器页面，脚本生成不了结论，要人眼各开一次
（标题会变成 `PASS n/m`，那个才是这次的真实条数）。

**打开它们、并把条数写回本文档，用这个脚本**：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\_runpages.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\_runpages.ps1 -Set 58/58,34/34,39/39,450/450,85/85,41/41,71/71,119/119,63/63
```

第一条打开九页并打印本文档现在写的数字，第二条（**逗号分隔**）把实跑结果
写回去——顺序就是 `$OUT_NAMES` 的顺序，格式由脚本保证不会写错行。
它写完会**读回来核对**：九个数字对得上、且长度只变了该变的那么多，才算成功。

⚠️ **它只做得了这一半。** 「读标题」那一步它做不到：无头 Chrome 渲染不了
这些页面（11 MB 单文件 + 持续 rAF + 软件 WebGL，实测 150 秒被看门狗杀掉、
dump 出 0 字节）。所以那九个数字**只能人看或 agent 用浏览器逐个开**，
脚本不假装能算出来——那样造出来的是一个「看着全自动、实际只会打 0 条」的脚本，
比没有更糟。

`dist\_driveharness.html` · `dist\_trafficharness.html` · `dist\_routeharness.html` ·
`dist\_moodharness.html` · `dist\_cruiseharness.html` · `dist\_moodstate.html` ·
`dist\_uistate.html` · `dist\_touchharness.html` · `dist\_bgmharness2.html`

它们不是手抄的，是 `gen\_mk*.ps1` 从 `src\_app3d.html` **按标记切原文**再套一层桩，
所以测的就是产品真正在跑的那段代码。`_touchharness` 特殊一点：它量的是
**布局**，办法是把成品里那一段 `<style>` 和 `#wrap` 的真实 DOM 搬进
390 / 360 / 320 / 852 四个视口的 iframe 里量真实矩形——不靠看图；
电影模式那部分另加 390 / 852 / 1280 三个视口，量「面板藏起来之后舞台是不是真的满屏」。

**「看标题」这条指令本身也是被检查的。** 页名清单在 `_paths.ps1` 的 `$OUT_NAMES` 里，
而 `checks\_pages.ps1` 要求清单内每一页都**有断言**且**把真条数写进 `document.title`**——
清单外的页一条断言都不会有人看。音乐回归页原先既不在清单里、标题还是个写死的
`<title>bgm harness v2</title>`，于是它有条断言烂到和产品真实行为相反
（还在断言修复前的「初始曲名 = 第一首曲名」，而产品早就改成播放前显示
「点一下画面开始」），**一直没人发现**，因为没人跑过它。补进清单后第一次跑就红了 62/63。

九套实测（2026-10-02，实跑见 tools\_runpages.ps1）：`58/58` · `34/34` · `52/52` · `454/454` · `85/85` · `41/41` · `163/163` · `119/119` · `63/63`。

## CI

`.github\workflows\verify.yml` 在 **Windows runner + Windows PowerShell 5.1**
（和本机完全一致）上跑 `checks\_checkall.ps1` 的**全部 20 步**，
push 到 `main` 和每个 PR 都跑。本机脚本**一行都没改**。

仓库里有 10 处脚本调用本机的 `mavis-trash`（可恢复删除）来清理临时目录，
CI runner 上没有这个工具，所以 workflow 会在 `$env:RUNNER_TEMP` 下
生成一个同名垫片并加进 `PATH`。

**垫片必须真的删**。一个空转的垫片（打一行成功、什么都没删）会让那 8 处
`mavis-trash` 全部「成功」，而紧跟其后的 `New-Item -Force` 会把旧目录原样留着 ——
于是「清理 → 重建」这段代码在 CI 上等于一次都没跑过，CI 恰恰是唯一该跑它的地方。
所以 workflow 里紧跟着垫片还有一步**当场证明它删得掉**：建一个临时文件、
交给垫片删、断言它确实没了。垫片哪天退化成空转，这一步会先红。

## 许可与来源

**本仓库没有 LICENSE 文件，默认保留所有权利。**

这是一次写明的决定，不是忘了加：2026-10-01 明确选择不给开源许可，
所以不要假定它可以随意使用、复制或再分发。

之所以要专门写下来：「没加 LICENSE」和「决定不加」在访客眼里**长得一模一样** ——
两种情况下仓库根目录都是空的。于是 `checks\_doccheck.ps1` 的第 ⑤ 条判据
盯着「README 的声明 ↔ LICENSE 文件在不在」必须一致：将来真要开源、
补上 `LICENSE` 却忘了改这行字，判据会当场指出两边自相矛盾。

- 渲染：[three.js](https://threejs.org/) r149，**已 vendored** 在 `assets\vendor\`，不联网拉取。
- 配乐：8 首 AI 生成的曲子，音频文件保留在仓库里。生成条款若有要求，请按实际情况补充本节。
- 画面、模型、代码：全部程序生成，无外部素材。
