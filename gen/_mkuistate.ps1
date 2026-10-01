# 面板初始状态体检：把探针注入**成品副本**，读 IIFE 内部的真实状态。
#
# 为什么不能用 harness 那一套：S / CAM / BGM / AU / MOOD 全在主 IIFE 里，
# 从页面外面读不到。而这件事要查的恰恰是「按钮亮着」和「内部状态」对不对，
# 外部只看 DOM 只能看一半 —— 比如拖完镜头之后「正面」还亮着，
# 到底该不该亮，得看 CAM.azT 跑偏了多少。
#
# 所以：把一段检查代码插到 `})();` **之前**，它在闭包里、什么都读得到。
# 产物是 _uistate.html（临时页），成品本身一个字都不动。
#
# 注入点：最后一个 `\n})();`。产物末尾就是这个，所以能精确定位。
$ErrorActionPreference = 'Stop'
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
$dir = $ROOT
$src = $PRODUCT
$out = $OUT_UISTATE
if (-not (Test-Path $src)) { throw "先跑 _build.ps1：找不到 $src" }

$t = [IO.File]::ReadAllText($src)
$anchor = "`n})();"
$i = $t.LastIndexOf($anchor)
if ($i -lt 0) { throw '找不到最后的 `n})();`，注入点定位失败' }
"注入点偏移 {0:N0} / 全文 {1:N0}" -f $i, $t.Length

$probe = @'
/* ═══ 面板初始状态体检（_mkuistate.ps1 注入，只存在于 _uistate.html）═══ */
(function(){
const R = [];
const uok  = (c,n,d) => R.push([!!c, n, d===undefined ? '' : String(d)]);
const el   = id => document.getElementById(id);
const on   = id => el(id).classList.contains('on');
const CAMIDS = ['bSpin','bFollow','bFront','bBack','bBird','bBike'];
const lit  = ids => ids.filter(on);
/* 在第一帧跑之前取样：这才是「初始状态」 */
const snap = () => ({
  S: { running:S.running, cruise:S.cruise, speed:+S.speed.toFixed(2), km:S.km, seg:S.seg,
       tSec:S.tSec, steer:S.steer, steerIn:S.steerIn, yaw:S.yaw, lat:S.lat, offRoad:S.offRoad, hitT:S.hitT,
       fatigue:S.fatigue, startle:S.startle, wet:S.wet, lookT:S.lookT, lookAmt:S.lookAmt,
       saidTired:S.saidTired, blink:S.blink, blinkT:S.blinkT, capT:S.capT, sweat:S.sweat,
       steerCmd:S.steerCmd, autoLat:S.autoLat, autoSide:S.autoSide, wheel:S.wheel, crank:S.crank },
  CAM:{ az:+CAM.az.toFixed(3), pol:+CAM.pol.toFixed(3), dist:+CAM.dist.toFixed(3),
       azT:+CAM.azT.toFixed(3), polT:+CAM.polT.toFixed(3), distT:+CAM.distT.toFixed(3),
       spin:CAM.spin, idle:CAM.idle },
  BGM:{ i:BGM.i, want:BGM.want, started:BGM.started, ready:BGM.ready, auto:BGM.auto, manual:BGM.manual, user:BGM.user },
  AU: { on:AU.on, birds:AU.birds, ready:AU.ready },
  MOOD:{ tk:MOOD.tk, wk:MOOD.wk, rain:MOOD.rain, snow:MOOD.snow }
});
const dom = () => ({
  play: el('bPlay').textContent.trim(),
  cruiseOn: on('bCruise'),
  camLit: lit(CAMIDS).length,
  camWhich: lit(CAMIDS),
  timeLit: ['t_day','t_dusk','t_night'].filter(on),
  wxLit:   ['w_clear','w_rain','w_snow','w_fog'].filter(on),
  autoOn: on('bAuto'), soundOn: on('bSound'), voiceOn: on('bVoice'),
  bgmGlyph: el('bBgm').textContent.trim(),
  bgmLabel: el('hBgm').textContent.trim(),
  speedSlider: el('rSpeed').value, speedLabel: el('vSpeed').textContent.trim(),
  hudSpeed: el('hSpeed').textContent.trim(), hudDist: el('hDist').textContent.trim(),
  hudCad: el('hCad').textContent.trim(), hintGone: el('hint').classList.contains('gone')
});

const D0 = snap(), U0 = dom();
R.push(['I', '—— 初始状态快照 ——', JSON.stringify(D0)]);
R.push(['I', '—— 初始 DOM ——', JSON.stringify(U0)]);

/* ── 1. 每个「亮着」的按钮，它代表的状态是不是真的那样 ── */
uok(U0.play === (D0.S.running ? '⏸' : '▶'), '播放键字形 = 正在跑？', U0.play + ' / running=' + D0.S.running);
uok(U0.cruiseOn === D0.S.cruise, '巡航键 = S.cruise？', U0.cruiseOn + ' / ' + D0.S.cruise);
uok(U0.camLit === 1, '六个镜头键里**恰好一个**亮着', '亮了 ' + U0.camLit + ' 个：' + U0.camWhich.join(','));
uok(U0.camWhich[0] === (D0.CAM.spin ? 'bSpin' : 'bFollow') || D0.CAM.spin,
   '镜头键和 CAM.spin 对得上', U0.camWhich.join(',') + ' / spin=' + D0.CAM.spin);
uok(U0.timeLit.length === 1 && U0.timeLit[0] === 't_' + D0.MOOD.tk, '时段键 = MOOD.tk？',
   U0.timeLit.join(',') + ' / ' + D0.MOOD.tk);
uok(U0.wxLit.length === 1 && U0.wxLit[0] === 'w_' + D0.MOOD.wk, '天气键 = MOOD.wk？',
   U0.wxLit.join(',') + ' / ' + D0.MOOD.wk);
uok(U0.autoOn === D0.BGM.auto, '自动键 = BGM.auto？', U0.autoOn + ' / ' + D0.BGM.auto);
/* 「声音」这盏灯的规则不是「= AU.on」，而是**跟着引擎走**：
   AudioContext 只能在真实手势里建，没建起来之前亮着就是骗人
   （一个字也听不见，却写着「🔊 声音」）。起来之后才 = AU.on。 */
uok(D0.AU.ready ? (U0.soundOn === D0.AU.on) : (U0.soundOn === false),
   '声音键：引擎没起来不亮，起来了才 = AU.on',
   'on=' + U0.soundOn + ' AU.on=' + D0.AU.on + ' ready=' + D0.AU.ready);
uok(!D0.AU.ready && U0.soundOn === false, '没点过画面时「声音」不许显示成已开',
   'on=' + U0.soundOn + ' ready=' + D0.AU.ready);
uok(U0.voiceOn === D0.AU.birds, '鸟鸣键 = AU.birds？', U0.voiceOn + ' / ' + D0.AU.birds);
uok(U0.bgmGlyph === ((D0.BGM.want && D0.BGM.started) ? '⏸' : '▶'),
   '音乐键字形 = **真的在不在放**（want && started）', U0.bgmGlyph + ' / want=' + D0.BGM.want + ' started=' + D0.BGM.started);
uok(D0.BGM.started === false && U0.bgmGlyph !== '⏸',
   '初始时一个音都还没放，键就不能显示成「正在播放」', 'started=' + D0.BGM.started + ' 字形=' + U0.bgmGlyph);
uok(U0.bgmLabel === '点一下画面开始' || D0.BGM.started,
   '还没开始时，「点一下画面开始」这句话得留在面板上（别被曲名盖掉）', U0.bgmLabel);
uok(parseFloat(U0.hudSpeed) === D0.S.speed && parseFloat(U0.hudDist) === 0,
   'HUD 和 S 对得上（第一帧之前都是初值）', U0.hudSpeed + ' / ' + U0.hudDist);
uok(U0.speedSlider === String(D0.S.speed) && U0.speedLabel === D0.S.speed.toFixed(1) + ' km/h',
   '速度滑杆和读数 = S.speed，且格式和每帧写的那行一致（第一帧不能换写法）',
   U0.speedSlider + ' / ' + U0.speedLabel + ' / ' + D0.S.speed);
uok(U0.hintGone === false, '初始提示（拖拽/滚轮/右键）没被提前关掉', 'gone=' + U0.hintGone);

/* ── 1b. 第一次手势：引擎起来 + 真的开始放 + 两盏灯重画 ── */
/* 播放键两个方向都要点：初始是「▶ 没在放」，点它必须**开始放**。
   旧处理器判的是 BGM.want（想放），而 want 从一开始就是 true ——
   于是点一下走进 bgmPause()，按钮点了没反应。 */
{
  BGM.want = true; BGM.started = false;
  if (BGM.el) BGM.el.pause();
  el('bBgm').click();
  uok(BGM.started === true, '初始状态（▶ 没在放）点播放键 → 真的开始放',
     'want=' + BGM.want + ' started=' + BGM.started);
  el('bBgm').click();
  uok(BGM.started === false && BGM.want === false, '再点一次 → 真的暂停（另一头也得成立）',
     'want=' + BGM.want + ' started=' + BGM.started);
  // 复原成初始态，让下面「点一下画面」那条路自己走一遍
  BGM.want = true; BGM.started = false;
  if (BGM.el) BGM.el.pause();
}
/* 音量总线：没在放的时候不该往上爬（爬到「正在播」的音量而播放器没在放，
   而且真开始放的时候已经是满音量，没有淡入）。两个方向都量。 */
{
  AU.on = true; BGM.want = true; BGM.started = false; BGM.cur = 0.5;
  for (let i = 0; i < 30; i++) bgmTick(0.1);
  const volIdle = BGM.el ? BGM.el.volume : -1;
  BGM.started = true; BGM.cur = 0;
  for (let i = 0; i < 40; i++) bgmTick(0.1);
  const volPlaying = BGM.el ? BGM.el.volume : -1;
  uok(volIdle < 0.05, '没在放 → 音量总线不爬（不给一个「正在播」的假音量）', 'volume=' + volIdle.toFixed(3));
  uok(volPlaying > 0.3, '开始放之后音量才上去（而且是渐上去的）', 'volume=' + volPlaying.toFixed(3));
  BGM.started = false; BGM.cur = 0;
}
let unlockErr = '';
try { document.body.dispatchEvent(new PointerEvent('pointerdown', {bubbles:true, clientX:5, clientY:5})); }
catch(e){ unlockErr = e.message; }
const Dg = snap(), Ug = dom();
uok(Dg.AU.ready === true, '点一下画面之后引擎真的建起来了（AU.ready）',
   'ready=' + Dg.AU.ready + (unlockErr ? ' / 抛错：' + unlockErr : ''));
uok(Ug.soundOn === Dg.AU.on && Ug.soundOn === true, '解锁之后「声音」这盏灯跟着亮',
   'on=' + Ug.soundOn + ' AU.on=' + Dg.AU.on);
uok(Dg.BGM.started === true && Dg.BGM.want === true, '点一下画面之后歌**真的开始放了**',
   'want=' + Dg.BGM.want + ' started=' + Dg.BGM.started);
uok(Ug.bgmGlyph === '⏸' && Ug.bgmLabel.indexOf('点一下') < 0, '歌放起来之后播放键才显示 ⏸、标签换成曲名',
   Ug.bgmGlyph + ' / ' + Ug.bgmLabel);

/* ── 1c. 鸟鸣：灯是开的，但雨雪天真的不叫 —— 得说清楚为什么 ── */
{
  AU.birds = true; applyMood('day', 'clear'); paintBirdBtn();
  const clearTitle = el('bVoice').title, clearOn = on('bVoice');
  applyMood('day', 'rain'); paintBirdBtn();
  const rainTitle = el('bVoice').title, rainOn = on('bVoice');
  uok(clearOn && rainOn, '鸟鸣开着时灯一直是亮的（设置确实开着，不该灭）',
     '晴 on=' + clearOn + ' / 雨 on=' + rainOn);
  uok(rainTitle !== clearTitle && /雨/.test(rainTitle),
     '切到雨天，按钮的说明变成「为什么不叫」', '「' + rainTitle + '」');
  applyMood('day', 'clear');
  uok(el('bVoice').title === clearTitle, '切回晴天说明跟着回去', '「' + el('bVoice').title + '」');
  AU.birds = false; paintBirdBtn();
}

/* ── 2. 重置到底重置了什么 ── */
S.km = 3.2; S.seg = 2; S.wheel = 900; S.crank = 1.4; S.tSec = 210; S.lat = 0.7; S.yaw = -0.3;
S.steer = 0.5; S.fatigue = 0.81; S.startle = 0.6; S.wet = 0.9; S.lookT = 0.8; S.lookAmt = 0.7;
S.saidTired = true; S.capT = 2; S.cruise = true; el('bCruise').classList.add('on');
S.hitT = 0.5; S.offRoad = 1; S.sweat = 0.7; S.blink = 0.12; S.blinkT = 0.4;
el('bReset').click();
const D1 = snap(), U1 = dom();
uok(D1.S.km === 0 && D1.S.seg === -1 && D1.S.tSec === 0 && D1.S.lat === 0 && D1.S.yaw === 0
   && D1.S.steer === 0, '重置：里程/路段/计时/横向/朝向/车把 全归零',
   'km=' + D1.S.km + ' seg=' + D1.S.seg + ' tSec=' + D1.S.tSec + ' lat=' + D1.S.lat
   + ' yaw=' + D1.S.yaw + ' steer=' + D1.S.steer);
uok(D1.S.fatigue === 0 && D1.S.startle === 0 && D1.S.wet === 0 && D1.S.lookT === 0
   && D1.S.lookAmt === 0 && D1.S.saidTired === false && D1.S.sweat === 0,
   '重置：鹧鸪状态（累/惊/湿/回头/用力/说过台词）全归零',
   'fatigue=' + D1.S.fatigue + ' startle=' + D1.S.startle + ' wet=' + D1.S.wet
   + ' lookAmt=' + D1.S.lookAmt + ' saidTired=' + D1.S.saidTired + ' sweat=' + D1.S.sweat);
uok(D1.S.hitT === 0 && D1.S.offRoad === 0 && D1.S.blink === 0 && D1.S.capT === 0,
   '重置：碰撞冷却/压草/眨眼/台词计时 全归零',
   'hitT=' + D1.S.hitT + ' offRoad=' + D1.S.offRoad + ' blink=' + D1.S.blink + ' capT=' + D1.S.capT);
uok(D1.S.cruise === false && U1.cruiseOn === false, '重置：巡航关掉，**按钮也跟着灭**',
   'cruise=' + D1.S.cruise + ' on=' + U1.cruiseOn);
/* 这条原来在 _mkcruise.ps1 里，是一条 grep 源码里 `S.autoLat=0; S.autoSide=0;`
   的判据。重置改成 `for (const k in S0) S[k] = S0[k]` 之后**行为一点没变**，
   那条 grep 反而红了。搬到这边来：有闭包作用域，能真的调 resetRide() 再读值。
   判据咬死实现写法，实现一改好它就误报 —— 这是判据写坏的又一种形态。 */
uok(D1.S.autoLat === 0 && D1.S.autoSide === 0 && D1.S.steerCmd === 0
   && D1.S.steerIn === 0 && D1.S.wheel === 0 && D1.S.crank === 0,
   '重置：巡航的舵（autoLat/autoSide/steerCmd/steerIn）和车轮/曲柄 全归零',
   'autoLat=' + D1.S.autoLat + ' autoSide=' + D1.S.autoSide + ' steerCmd=' + D1.S.steerCmd
   + ' steerIn=' + D1.S.steerIn + ' wheel=' + D1.S.wheel + ' crank=' + D1.S.crank);

/* ── 3. 镜头预设：拖完之后还亮着吗 ──
   ⚠️ 合成事件必须派到 **cv** 上。第一版派给了 window，而 pointermove 的
      监听器挂在 cv 上 —— 事件从 window 往下传不到 cv，azT 纹丝不动，
      后面那条「应该灭掉」就成了恒过的假绿。 */
el('bFront').click();
const afterFront = { azT: +CAM.azT.toFixed(3), lit: lit(CAMIDS) };
uok(afterFront.lit.length === 1 && afterFront.lit[0] === 'bFront', '点「正面」之后只有它亮',
   afterFront.lit.join(','));
uok(Math.abs(afterFront.azT) < 0.01, '点「正面」之后 azT 真的归 0', 'azT=' + afterFront.azT);
const mk = (t, x) => cv.dispatchEvent(new PointerEvent(t, {bubbles:true, clientX:x,
  clientY:300, button:0, buttons:1, pointerId:1, isPrimary:true}));
mk('pointerdown', 600);
CAM.dragging = true;                                   // setPointerCapture 在合成事件上会抛，
                                                       // try/catch 吞掉但 dragging 仍要置上
mk('pointermove', 760);
const afterDrag = { azT: +CAM.azT.toFixed(3), lit: lit(CAMIDS) };
uok(Math.abs(afterDrag.azT - afterFront.azT) > 0.2, '拖拽之后 azT 真的被拖偏了（这一步得先成立）',
   'azT ' + afterFront.azT + ' → ' + afterDrag.azT);
uok(afterDrag.lit.length === 0,
   '拖偏之后「正面」应该灭掉（它是个机位预设，不是开关）',
   afterDrag.lit.length ? '还亮着：' + afterDrag.lit.join(',') : '全灭');

/* ── 3b. 暂停期间：面板还能用，但画面必须一动不动 ──
   上一轮把「自动环绕」跟 S.running 绑死了，**镜头的平滑插值忘了**：
   暂停时点「背面」，setView 改了 azT，镜头当场滑过去。
   不用「跑 400 帧看它转多少」那种量法（探针里 dt≈0，转不出来），
   改用**逐位相等**：把机位挪开、暂停、掉几帧，az/pol/dist 必须一个比特都不动。
   dt 虽小但 k = 1 - 0.0008^dt 不是 0（dt=1e-5 时 k≈0.07），
   所以有 bug 的话差得出来。 */
{
  el('bPlay').click();                                  // 暂停
  uok(S.running === false && el('bPlay').textContent.trim() === '▶',
     '暂停后播放键自己也变 ▶', S.running + ' / ' + el('bPlay').textContent.trim());
  el('bBack').click();                                   // 暂停中换机位
  const q0 = { az: CAM.az, pol: CAM.pol, dist: CAM.dist, tSec: S.tSec };
  frame(); frame(); frame();                            // 掉三帧
  const q1 = { az: CAM.az, pol: CAM.pol, dist: CAM.dist, tSec: S.tSec };
  uok(q1.az === q0.az && q1.pol === q0.pol && q1.dist === q0.dist,
     '暂停中点机位预设：镜头**一个比特都没动**（平滑插值也必须停）',
     'az ' + q0.az.toFixed(6) + ' → ' + q1.az.toFixed(6)
     + '  pol ' + q0.pol.toFixed(6) + ' → ' + q1.pol.toFixed(6)
     + '  dist ' + q0.dist.toFixed(6) + ' → ' + q1.dist.toFixed(6));
  uok(q1.tSec === q0.tSec, '暂停中时钟也停', q0.tSec + ' → ' + q1.tSec);
  el('bPlay').click();                                  // 恢复
  frame();
  uok(CAM.az !== q1.az, '恢复之后镜头补滑到暂停时选的机位（那才是应该的）',
     'az ' + q1.az.toFixed(6) + ' → ' + CAM.az.toFixed(6));
  el('bSpin').click();
}

/* ═══ 电影模式：真点一次按钮 ═══
   这一段是被一次真事故逼出来的：按钮和 F 键都「进去 0.5 秒又出来」，
   而当时语法、自由变量、8 套 harness、CI 全绿 ——
   因为**没有任何一条判据真的点过那个按钮**。
   所以「点一下，看界面有没有变」本身就得是一条判据，不能靠人记得点。 */
{
  const root   = document.documentElement;
  const panelD = () => { const p = document.querySelector('.panel');
                         return p ? getComputedStyle(p).display : '(没有面板)'; };
  const inCin  = () => root.classList.contains('cin');
  uok(!inCin(), '电影模式：初始不在电影模式（好样本不误伤）', 'class=' + root.className);
  el('bCinema').click();
  uok(inCin(), '点「电影模式」→ 真的进了（点完界面必须变，否则按钮就是装饰）', 'class=' + root.className);
  uok(panelD() === 'none', '进电影模式后面板真的收起来了', 'panel display=' + panelD());
  el('bCinema').click();
  uok(!inCin(), '再点一次 → 退出，面板回来', 'class=' + root.className);

  /* 关键的一条。全屏请求被拒（没用户交互 / iframe 没放行 / iOS 的限制）之后，
     浏览器会回一个「当前不在全屏」的 fullscreenchange。
     旧实现把它当成「用户退了全屏」，于是把**刚藏好的界面又放出来** ——
     表现就是「点一下什么都没发生」，而控制台一个错都没有。
     修法是只认「确实进过全屏、现在不在了」（CIN.wasFs）。
     下面两条**一起**验：如果只有第一条，这个守卫也可能是恒过的。 */
  el('bCinema').click();
  document.dispatchEvent(new Event('fullscreenchange'));   // 模拟「请求被拒的回音」
  uok(inCin(), '全屏请求被拒（wasFs 仍 false）→ 电影模式留在原地，不被自己的回音撤销',
     'class=' + root.className);
  CIN.wasFs = true;                                        // 装回「确实进过全屏」这个前提
  document.dispatchEvent(new Event('fullscreenchange'));
  uok(!inCin(), '反查 ⑧：真的进过全屏、现在退出了 → 电影模式必须跟着退（证明上一条不是恒过）',
     'class=' + root.className);
}

/* ── 电影模式里的极简控制条 + 侧边小框 ──────────────────────
   面板藏起来之后，切歌/自动/播放不能跟着一起没 ——
   沉浸不是把功能丢了，是把它们挪到一个不挡画面的地方。
   ⚠️ 下面每一条都**真的点那个新按钮**，不靠读 CSS 猜：
   「按钮摆在那儿、点了没反应」是这一类最常见的交付事故，
   而它不抛任何异常、也没有任何静态检查会红。 */
{
  const root = document.documentElement;
  const barD = () => getComputedStyle(el('cinebar')).display;
  const boxD = () => getComputedStyle(el('sidebox')).display;
  el('bCinema').click();
  uok(root.classList.contains('cin') && barD() === 'flex',
     '电影模式里极简控制条真的出现了（不是摆设）', 'class=' + root.className + ' bar=' + barD());
  uok(boxD() === 'block', '侧边小框真的出现了（曲名 + 歌词）', 'sidebox=' + boxD());
  /* ⚠️ 前置条件必须先断言。下面「点了没反应」有**两种**可能的原因：
     按钮没接上，或者音轨压根没就绪（bgmStep 第一行就 return）。
     不先把 ready 钉死，测出来的红是没法归因的。 */
  uok(BGM.ready === true, '前置：音轨已就绪（否则「点了没反应」是 ready 的锅，不是按钮的锅）',
     'ready=' + BGM.ready);

  BGM.i = 0; paintBgm();
  el('cNext').click();
  uok(BGM.i === 1, '浮条「下一首」→ 曲号真的 +1', 'i=' + BGM.i);
  el('cPrev').click();
  uok(BGM.i === 0, '浮条「上一首」→ 曲号真的 -1', 'i=' + BGM.i);
  el('bNext').click();
  uok(BGM.i === 1, '面板的键也还管用（两个入口不是各走各的）', 'i=' + BGM.i);
  el('bPrev').click();

  /* 这一条是「单一刷新出口」的判据：点浮条的自动键，**面板上那盏灯
     也必须跟着亮**。两边各画各的就会出现「浮条亮着、面板灭着」，
     而 BGM.auto 其实只有一个值 —— 谁说了算，界面上不该有第二种答案。 */
  const a0 = BGM.auto;
  el('cAuto').click();
  uok(BGM.auto === !a0 && on('cAuto') === BGM.auto && on('bAuto') === BGM.auto,
     '浮条「自动」→ 面板那盏灯跟着一起翻（不是两个独立状态）',
     'auto=' + BGM.auto + ' 浮条=' + on('cAuto') + ' 面板=' + on('bAuto'));
  el('cAuto').click();

  uok(el('cPlay').textContent.trim() === el('bBgm').textContent.trim(),
     '浮条播放键字形 = 面板播放键字形（同一个出口算的）',
     el('cPlay').textContent.trim() + ' / ' + el('bBgm').textContent.trim());

  BGM.started = true; paintBgm();
  uok(el('sbTitle').textContent.trim() === el('hBgm').textContent.trim()
      && el('hBgm').textContent.trim().indexOf(BGM_TRACKS[BGM.i].title) === 0,
     '侧边小框那行曲名 = 面板的曲名（而且真的是当前这首）',
     el('sbTitle').textContent.trim() + ' / ' + el('hBgm').textContent.trim());

  /* 纯画面：浮条上那个 ⤢ 和 H 键是两条路（手机没键盘时只剩前者） */
  el('cBare').click();
  uok(root.classList.contains('bare') && barD() === 'none' && boxD() === 'none',
     '点「⤢」→ 浮条和侧边框都藏起来，只剩画面', 'class=' + root.className);
  el('cBare').click();
  uok(!root.classList.contains('bare') && barD() === 'flex' && boxD() === 'block',
     '再点一次 → 都回来', 'class=' + root.className);
  /* ⚠️ 这次派发**必须带 bubbles:true** —— 产品的 keydown 监听挂在 window 上，
     从 document 派发不冒泡的话事件根本到不了它。
     （这正是 fullscreenchange 那条教训的反面：那边**不**冒泡，所以只能绑 document。） */
  document.dispatchEvent(new KeyboardEvent('keydown', { code:'KeyH', bubbles:true }));
  uok(root.classList.contains('bare'), 'H 键 → 纯画面（手机上没 F 键时的第二条路）',
     'class=' + root.className);
  document.dispatchEvent(new KeyboardEvent('keydown', { code:'KeyH', bubbles:true }));
  uok(!root.classList.contains('bare'), '再按 H → 回来', 'class=' + root.className);

  /* 退出电影模式必须把 bare 复位，否则下一次进来是「什么都没有」，
     而界面上没有任何东西能解释为什么。 */
  el('cBare').click();
  el('bCinema').click();
  uok(!root.classList.contains('bare') && !root.classList.contains('cin'),
     '退出电影模式 → bare 跟着复位（下次进来不会是空的）', 'class=' + root.className);
  BGM.started = false; paintBgm();

  /* 反查 ⑨：装回「旧 painter 只画面板」—— 新出口最可能出的错就是忘了同步。
     必须破坏**这条判据对应的那个实现**，破坏周边不算数。 */
  const realPaint = paintBgm;
  paintBgm = () => { el('bBgm').textContent = (BGM.want && BGM.started) ? '⏸' : '▶';
                     el('bAuto').classList.toggle('on', BGM.auto); };
  const a1 = BGM.auto;
  el('cAuto').click();
  uok(!(on('bAuto') === on('cAuto') && on('bAuto') === BGM.auto),
     '反查 ⑨：旧 painter 只画面板 → 「两个出口一起翻」翻 false',
     'auto=' + BGM.auto + ' 面板=' + on('bAuto') + ' 浮条=' + on('cAuto'));
  paintBgm = realPaint;
  BGM.auto = a1; realPaint();
}

/* ═══ 反查：把**旧的坏代码原样装回去**，同一套判据必须翻 ═══
   ⚠️ 第一版这里写错了方向：只是把状态弄脏、然后仍然调用**修好的**处理器，
      谓词当然还是 true —— 脏状态被修好了，等于什么都没量。
   真正的反查是把旧实现装回去（跟 _scopetest 一个套路）：
   旧的重置只清 9 个字段 / 旧的拖拽不灭灯 / 旧的 paintSoundBtn 直接
   按 AU.on 点亮 / 旧的播放键只按 want 画字形。 */
{
  // ① 旧的重置：S.km=0; S.seg=-1; …（原文照抄）
  const oldReset = () => { S.km=0; S.seg=-1; S.wheel=0; S.crank=0; S.tSec=0; S.lat=0; S.yaw=0;
                           S.steer=0; S.autoLat=0; S.autoSide=0; };
  S.fatigue = 0.77; S.startle = 0.5; S.wet = 0.8; S.lookAmt = 0.6; S.saidTired = true;
  S.hitT = 0.5; S.offRoad = 1; S.blink = 0.12; S.capT = 2; S.sweat = 0.6;
  S.cruise = true; el('bCruise').classList.add('on');
  S.autoLat = 0.8; S.autoSide = 1; S.steerCmd = -0.6; S.steerIn = 1; S.wheel = 900; S.crank = 1.4;
  oldReset();
  const s1 = snap().S, c1 = dom();
  uok(!(s1.autoLat === 0 && s1.autoSide === 0 && s1.steerCmd === 0
        && s1.steerIn === 0 && s1.wheel === 0 && s1.crank === 0),
     '反查 ①d：旧处理器不清巡航的舵 → 谓词翻 false',
     'autoLat=' + s1.autoLat + ' autoSide=' + s1.autoSide + ' steerCmd=' + s1.steerCmd);
  uok(!(s1.fatigue === 0 && s1.startle === 0 && s1.wet === 0 && s1.lookAmt === 0
        && s1.saidTired === false && s1.sweat === 0),
     '反查 ①：装回旧的重置处理器 → 「鹧鸪状态全归零」翻 false',
     'fatigue=' + s1.fatigue + ' wet=' + s1.wet + ' saidTired=' + s1.saidTired);
  uok(!(s1.hitT === 0 && s1.offRoad === 0 && s1.blink === 0 && s1.capT === 0),
     '反查 ①b：旧处理器不清碰撞/压草/眨眼/台词计时 → 谓词翻 false',
     'hitT=' + s1.hitT + ' offRoad=' + s1.offRoad + ' blink=' + s1.blink + ' capT=' + s1.capT);
  uok(!(s1.cruise === false && c1.cruiseOn === false), '反查 ①c：旧处理器不碰巡航 → 谓词翻 false',
     'cruise=' + s1.cruise + ' on=' + c1.cruiseOn);

  // ② 旧的拖拽：只动 azT，不灭灯
  el('bFront').click();
  CAM.azT -= 160 * 0.0072; CAM.idle = 0;          // ← 没有 camPresetOff()
  uok(!(lit(CAMIDS).length === 0), '反查 ②：旧拖拽路径不灭灯 → 「全灭」翻 false',
     '亮着：' + lit(CAMIDS).join(',') + ' azT=' + CAM.azT.toFixed(3));

  // ③ 旧的 paintSoundBtn：直接按 AU.on 点亮
  const oldPaintSound = () => { el('bSound').textContent = AU.on ? '🔊 声音' : '🔇 静音';
                                el('bSound').classList.toggle('on', AU.on); };
  AU.ready = false; AU.on = true; oldPaintSound();
  uok(!(!on('bSound')), '反查 ③：旧的声音按钮在引擎没起来时也点亮 → 谓词翻 false',
     'on=' + on('bSound') + ' 文字=' + el('bSound').textContent.trim());

  // ④ 旧的 paintBgm：字形只看 want
  const oldPaintBgm = () => { el('bBgm').textContent = BGM.want ? '⏸' : '▶';
                              el('bBgm').classList.toggle('on', BGM.auto); };
  BGM.want = true; BGM.started = false; oldPaintBgm();
  uok(!(el('bBgm').textContent.trim() !== '⏸'), '反查 ④：旧播放键没在放也显示 ⏸ → 谓词翻 false',
     '字形=' + el('bBgm').textContent.trim());

  // ⑤ 旧的播放键处理器：判 want 而不是 started
  const oldBgmClick = () => { if (BGM.want && BGM.ready) bgmPause(); else bgmPlay(); };
  BGM.want = true; BGM.started = false; if (BGM.el) BGM.el.pause();
  oldBgmClick();
  uok(!(BGM.started === true), '反查 ⑤：旧处理器把「点一下播放」变成暂停 → 谓词翻 false',
     'want=' + BGM.want + ' started=' + BGM.started);

  // ⑥ 旧的鸟鸣按钮：没有那句「为什么不叫」
  const oldPaintBird = () => { el('bVoice').textContent = AU.birds ? '🔊 鸟鸣' : '🔇 鸟鸣';
                               el('bVoice').classList.toggle('on', AU.birds);
                               el('bVoice').title = '鹧鸪叫声，默认关闭'; };
  AU.birds = true; applyMood('day', 'rain'); oldPaintBird();
  uok(!(/雨/.test(el('bVoice').title)), '反查 ⑥：旧按钮不说明雨雪天为什么不叫 → 谓词翻 false',
     'title=「' + el('bVoice').title + '」');
  applyMood('day', 'clear'); AU.birds = false; paintBirdBtn();

  // ⑦ 旧的镜头平滑：没有 if (S.running) 包着
  const oldSmooth = () => { CAM.az += (CAM.azT - CAM.az) * (1 - Math.pow(0.0008, 1e-5)); };
  S.running = false; CAM.azT = CAM.az + 1.0;
  const r0 = CAM.az; oldSmooth();
  uok(!(CAM.az === r0), '反查 ⑦：旧的无条件平滑 → 「一个比特都没动」翻 false',
     'az ' + r0.toFixed(6) + ' → ' + CAM.az.toFixed(6));
  S.running = true;
}

/* ── 输出 ── */
const bad = R.filter(x => !x[0] && x[0] !== 'I');
let h = '<h3>' + (R.filter(x => x[0] === true).length) + ' / ' + R.filter(x => x[0] !== 'I').length + ' 通过</h3>';
if (bad.length){
  h += '<div style="color:#ff6b6b;margin:6px 0 10px">下面 ' + bad.length + ' 条没过：</div>';
  for (const [c,n,d] of bad) h += '<div class="bad">FAIL  ' + n + (d ? '   [' + d + ']' : '') + '</div>';
  h += '<hr>';
}
for (const [c,n,d] of R){
  if (c === 'I') { h += '<div class="info" style="color:#8a97a9;margin:8px 0 2px">' + n + '</div>'
                      + '<pre style="white-space:pre-wrap;color:#8a97a9;font-size:11px">' + d + '</pre>'; continue; }
  h += '<div class="' + (c ? 'ok' : 'bad') + '">' + (c ? 'PASS  ' : 'FAIL  ') + n + (d ? '   [' + d + ']' : '') + '</div>';
}
let box = document.getElementById('uicheck');
if (!box){ box = document.createElement('pre'); box.id = 'uicheck';
  box.style.cssText = 'position:fixed;inset:0;z-index:99999;overflow:auto;margin:0;padding:14px;'
                     + 'background:#0b0e13;color:#e9eef6;font:12px/1.5 Consolas,monospace;white-space:pre-wrap';
  document.body.appendChild(box); }
box.innerHTML = h;
document.title = (bad.length ? 'FAIL ' : 'PASS ') + R.filter(x=>x[0]===true).length
               + '/' + R.filter(x => x[0] !== 'I').length;
})();
'@

$t = $t.Substring(0, $i) + "`n" + $probe + $t.Substring($i)
[IO.File]::WriteAllText($out, $t, (New-Object Text.UTF8Encoding($false)))
"wrote {0}  {1:N0} bytes" -f (Split-Path $out -Leaf), (Get-Item $out).Length
& powershell -NoProfile -ExecutionPolicy Bypass -File ($S_SYNTAX) -Path $out
exit $LASTEXITCODE