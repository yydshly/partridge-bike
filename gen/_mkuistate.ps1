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
/* 深链那两个字段**必须在任何测试动过 S 之前**记下来。
   探针第 2 节会把 S.km 改成 3.2 再点「重置」，所以后面再读就只剩
   「重置之后」的值了 —— 拿它判「深链生效没有」是测不到东西的。 */
const KMINIT = { q: new URLSearchParams(location.search).get('km'),
                 km: S.km, s0: (typeof S0 !== 'undefined' ? S0.km : '(没有 S0)') };
R.push(['I', '—— 初始状态快照 ——', JSON.stringify(D0)]);
R.push(['I', '—— 初始 DOM ——', JSON.stringify(U0)]);
R.push(['I', '—— 深链初始值（未被动过）——', JSON.stringify(KMINIT)]);

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
/* ⚠️ 这里原来写的是 `D1.S.km === 0`。带 ?km=2.0 加载时它红了 ——
   因为「重置」应该回到的是**初始里程**，而初始里程就是深链指定的那个 2。
   钉死字面量 0 的判据在有深链之后就是错的，而且它错得很有欺骗性：
   不带参数加载时它照样全绿，看起来一直是对的。
   真正该问的是「重置 == 快照」，所以拿 S0.km 比。 */
uok(D1.S.km === KMINIT.s0 && D1.S.seg === -1 && D1.S.tSec === 0 && D1.S.lat === 0 && D1.S.yaw === 0
   && D1.S.steer === 0, '重置：里程回到**初始值**（带 ?km= 时就是那个起点，不是 0）/路段/计时/横向/朝向/车把',
   'km=' + D1.S.km + '（S0.km=' + KMINIT.s0 + '）seg=' + D1.S.seg + ' tSec=' + D1.S.tSec + ' lat=' + D1.S.lat
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
  uok(q1.az !== q0.az || q1.pol !== q0.pol || q1.dist !== q0.dist,
     '暂停中点机位预设：镜头**要动**（视角不是仿真的组成部分）',
     'az ' + q0.az.toFixed(6) + ' → ' + q1.az.toFixed(6)
     + '  pol ' + q0.pol.toFixed(6) + ' → ' + q1.pol.toFixed(6)
     + '  dist ' + q0.dist.toFixed(6) + ' → ' + q1.dist.toFixed(6));
  uok(q1.tSec === q0.tSec, '暂停中时钟也停（仿真停，这条不能松）', q0.tSec + ' → ' + q1.tSec);
  /* 自动环绕是**行为**不是视角，暂停时必须停 —— 否则就是「画面在背后偷跑」，
     实测暂停 3 秒 camAz 转了 0.96 rad。
     ⚠️ 探针里 dt≈0，漂移量不出来（跑 400 帧那种量法这里不能用），
        所以这条去看源码里那句 gate 还在不在。 */
  uok(/S\.running\s*&&\s*CAM\.spin/.test(frame.toString()),
     '自动环绕仍然跟着 S.running 停（它是行为，不是视角）',
     'frame() 里那一句现在是：' +
     (frame.toString().match(/if \([^)]*CAM\.spin[^)]*\)/) || ['（没找到）'])[0]);
  el('bPlay').click();                                  // 恢复
  frame();
  uok(CAM.az !== q1.az, '恢复之后镜头补滑到暂停时选的机位（那才是应该的）',
     'az ' + q1.az.toFixed(6) + ' → ' + CAM.az.toFixed(6));
  el('bSpin').click();
}

/* ── 3c. 暂停期间能不能拖？拖了要不要立刻见效 ──
   ⚠️ 这三条的理由在 2026-10-02 **整个翻过来了**。
      原来这里守的是「暂停中拖动画面一个比特都不动，输入先记下、恢复后兑现」，
      依据是一句我自己写的产品注释：「暂停要的是一张完全静止的画」。
      用户直接否掉了：「不对啊，暂停的时候这是 3D，鼠标应该可以拖动画面啊」。
      对的 —— 镜头是**视角**，不是仿真的组成部分。车停了，但「换个角度看看」
      恰恰是暂停时最该做的事。把视角冻住只会被读成「拖了没反应」。
      所以：镜头插值不再跟 S.running 绑定；自动环绕仍然停（那是行为不是视角）。

   ⚠️ 量法：派真的 PointerEvent 到 cv 上，不在判据里另抄一份 `azT -= dx*0.0072`。
      抄一份的话产品改了系数判据照样绿 —— 判据和实现两份代码各自漂，
      比没有判据更坏。 */
{
  const ev = (t, x, shift) => cv.dispatchEvent(new PointerEvent(t, {bubbles:true, clientX:x,
                clientY:300, button: shift ? 2 : 0, buttons:1, pointerId:1, isPrimary:true,
                shiftKey: !!shift}));
  el('bPlay').click();                                   // 暂停
  el('bFront').click();                                  // 机位归零，差异才量得出来
  frame();
  const o0 = { az: CAM.az, azT: CAM.azT, tx: CAM.target.x };
  ev('pointerdown', 600, false);
  CAM.dragging = true;                                   // 合成事件上 setPointerCapture 会抛，
  ev('pointermove', 760, false);                         // try/catch 吞掉，dragging 得手动置上
  frame(); frame();
  const o1 = { az: CAM.az, azT: CAM.azT, tx: CAM.target.x };
  uok(Math.abs(o1.azT - o0.azT) > 0.2,
     '暂停中拖动**被记录**（azT 真的被拖偏了 —— 否则就是拖压根没接上）',
     'azT ' + o0.azT.toFixed(3) + ' → ' + o1.azT.toFixed(3));
  uok(o1.az !== o0.az,
     '暂停中拖动画面**立刻跟着动**（这就是 3D：暂停 ≠ 冻住视角）',
     'az ' + o0.az.toFixed(6) + ' → ' + o1.az.toFixed(6) + '，方向和幅度跟着 azT 的 ' +
     (o1.azT - o0.azT).toFixed(3) + ' rad。旧版本这里 az 一个比特都不动，' +
     '用户读到的就是「拖了没反应」');
  /* 平移（右键/双指）走 camPan()，它**直接**改 CAM.target，而 camera.position.set()
     每帧都读它 —— 所以它从来就不受暂停约束。两条路现在行为一致了。 */
  ev('pointerdown', 600, true);
  ev('pointermove', 700, true);
  uok(Math.abs(CAM.target.x - o1.tx) > 1e-6,
     '平移（右键/双指）在暂停中同样立刻生效（与环绕一致，不再有两套反应）',
     'CAM.target.x ' + o1.tx.toFixed(6) + ' → ' + CAM.target.x.toFixed(6) + '（暂停中）');
  CAM.dragging = false;
  el('bPlay').click();                                   // 恢复
  frame();
  uok(CAM.az !== o1.az, '恢复播放后视角继续跟着拖动走（没有断层）',
     'az ' + o1.az.toFixed(6) + ' → ' + CAM.az.toFixed(6) + '，目标 ' + CAM.azT.toFixed(3));
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

/* ── 4. 段专属物件：四个新构造函数当初是**算过**才敢那么摆的，
      那些数当时只活在注释里，改代码的人看不见、也没有任何东西拦着他。
      这里把它们钉成判据。
   ⚠️ 下面的阈值都取自实测（不是拍脑袋），而且**每条都把量出来的数带在
      detail 里** —— 判据红的时候不用回头猜是哪一步跑偏了。 */
{
  const bx = new THREE.Box3();
  const bandOf = id => BANDS.find(B => B.id === id);
  /* 前六件（fence/reed/tunnel/boulder/house/rail）+ 后十二件招牌元素。
     ⚠️ 跨路构件（B.over，比如村口的牌楼）**不在这个表里** ——
        它本来就该骑在下面，用「离路中心多远」去量它等于量了个 0。
        那几件由下一条专门量「净空 + 柱脚在不在路外」。 */
  const OWNBANDS = ['tunnel','fence','reed','rail','boulder','house',
                    'gate','well','sluice','netrack','litter','bench',
                    'revet','summit','walker','plate','pylon','stele']
                        .filter(id => !BANDS.find(B => B.id === id).over);
  /* 「这棵的冠往路那边伸出多远」—— ① 和反查 ⑩ 共用同一个出处。
     判据里另写一份实现，两份会各自漂：改坏这半边，判据照样全绿。 */
  const reachOf = o => { bx.setFromObject(o);
                         return o.position.z > -LANE ? (-LANE - bx.min.z) : (bx.max.z + LANE); };
  const minReachOf = B => B.objs.reduce((m,o) => Math.min(m, reachOf(o)), 1e9);

  /* ① 隧道树必须是**成拱**的：每一棵的树冠都要越过路中心线，
        否则就不是隧道，是两排各站各的树。
        ⚠️ 这里必须**按每一棵自己那一侧**算伸过去多远，不能一刀切只看 min.z。
        我第一版写的判据是 `bx.min.z < -LANE`，可路中心 z = -LANE 是负数，
        于是站在负侧的树（44 棵里的 22 棵，`side = B.side || (i%2?1:-1)`）
        的 min.z 恒为负、恒小于 -LANE ⇒ 恒成立。
        换句话说「44 棵全部成拱」只测了正侧的一半，还绿得毫无破绽。
        正侧的树要往 -z 伸（看 min.z），负侧的树要往 +z 伸（看 max.z）。
        细节里两侧的最小伸出量分开打，就是为了再也藏不住「只测了一半」。 */
  {
    const B = bandOf('tunnel');
    const rows = [];
    for (const o of B.objs){
      rows.push({ d: Math.abs(o.position.z - (-LANE)), reach: reachOf(o) });
    }
    const R = rows.map(r => r.reach);
    const posR = rows.filter((r,i) => B.objs[i].position.z >  -LANE).map(r => r.reach);
    const negR = rows.filter((r,i) => B.objs[i].position.z <  -LANE).map(r => r.reach);
    const srt = R.slice().sort((x,y) => x-y);
    const minOf = a => a.length ? a.reduce((m,v) => Math.min(m,v)) : NaN;
    const mid   = srt.length ? srt[srt.length >> 1] : NaN;
    const maxOf = a => a.length ? a.reduce((m,v) => Math.max(m,v)) : NaN;
    const minReach = minOf(R);
    const crossed = R.filter(v => v > 0).length;
    const dist = d => rows.map(r => r.d.toFixed(2)).sort((x,y) => x-y);
    uok(B.objs.length > 0 && posR.length > 0 && negR.length > 0 && crossed === B.objs.length,
       '隧道树成拱：' + crossed + '/' + B.objs.length + ' 棵的树冠越过了路中心线（两侧都测了）',
       '路中心 z=' + (-LANE).toFixed(3) + '；正侧 ' + posR.length + ' 棵，冠最靠内伸到 ' +
       minOf(posR).toFixed(2) + ' m 越过中心；负侧 ' + negR.length + ' 棵，冠最靠内伸到 ' +
       minOf(negR).toFixed(2) + ' m 越过中心');
    /* 这里量的是**分布**，不是「最紧那棵」。
       踩过的坑值得留着：我第一版拿「最紧那棵伸出 > 0.30 m」当余量门槛，
       并在注释里写「两侧最小伸出量都远在它之上」—— 实测正侧最小只有 0.18 m，
       判据当场变红。**那句话是我看着自己想要的数编的**，判据红的是它。
       而且「44 棵里最紧的一棵」是个尾概率：同侧相邻两棵隔 5.9 m，
       邻树的冠早就盖过它了，单独一棵 0.18 m 在画面上根本看不出来，
       拿它当门槛既不贴画面、又逼着人去调参数，纯属自己给自己找事。
       真正决定「林荫是不是拱」的是**一片**冠盖不盖得住路面上方，
       所以这里量中位数，门槛按**路面自己的几何**取 —— 半幅 ROAD_W/2 = 1.95 m：
       冠越过中心线还要再多出小半个路面，才谈得上「盖住路面上方」，
       而不是刚好碰到中线。这个数是从几何推的，不是从实测凑的。 */
    uok(mid > ROAD_W/2,
       '隧道树的**典型**冠盖过路中心线 ' + mid.toFixed(2) + ' m（要求 > 半幅 ' + (ROAD_W/2).toFixed(2) + ' m）',
       '44 棵伸出量：最小 ' + minReach.toFixed(2) + ' / 中位 ' + mid.toFixed(2) +
       ' / 最大 ' + maxOf(R).toFixed(2) + ' m；离路中心 ' + dist().slice(0,3).join('~') +
       '~' + dist().slice(-1)[0] + ' m（定种子布局，数字可复现）');
    /* ⚠️ 这里**故意不再**加一条「最小冠半径 > 最远离路距离」。
       我第一版加了，红在 5.38 > 5.56 —— 但那条量错了东西：
       bbox 的 z 向直径只是「冠最大半径」的下界，而树是随机转过角度的，
       往路那边伸出去多远和 z 向直径不是一回事。
       真正该问的是「这棵的冠有没有越过路中心」，那就是上面两条。
       判据必须问画面呈现出什么，不能拿一个相关的量代替它。 */
  }

  /* ⑩ 反查：把**负侧**那 22 棵的冠缩回树干，看判据会不会红。
        这正是旧判据看不见的那一半 —— 旧写法是 `bx.min.z < -LANE`，
        负侧树的 min.z 恒为负、恒小于 -LANE，**缩到 0.4 倍它照样绿**。
        一条只能测一半的判据比没有判据更坏：它让人以为隧道被守着。
        这条反查就是钉住「新判据确实两侧都看」。 */
  {
    const B = bandOf('tunnel');
    const neg = B.objs.filter(o => o.position.z < -LANE);
    const pos = B.objs.filter(o => o.position.z > -LANE);
    const keep = neg.map(o => o.scale.clone());
    for (const o of neg){ o.scale.multiplyScalar(0.4); o.updateMatrixWorld(true); }
    const deadNeg = neg.filter(o => reachOf(o) <= 0).length;
    const livePos = pos.filter(o => reachOf(o) > 0).length;
    neg.forEach((o, i) => { o.scale.copy(keep[i]); o.updateMatrixWorld(true); });
    uok(deadNeg > 0 && livePos === pos.length && neg.length > 0 && pos.length > 0,
       '反查 ⑩：把负侧的冠缩回树干 → 判据立刻看得见（' + deadNeg + '/' + neg.length + ' 棵不再成拱）',
       '同一次改动下正侧 ' + livePos + '/' + pos.length + ' 棵仍成拱；旧的 min.z 判据在这里恒绿，缩到 0.4 倍也发现不了');
    const back = neg.filter(o => reachOf(o) > 0).length;
    uok(back === neg.length, '反查 ⑩ 收尾：scale 还原后负侧 ' + back + '/' + neg.length + ' 棵恢复成拱（上一条不是靠改参数红的）',
       '还原后 44 棵全部成拱，最紧的那棵伸出 ' + minReachOf(B).toFixed(2) + ' m');
  }

  /* ② 段专属物件**不许压在路面上**。
        路面是 z ∈ [T_MIN, T_MAX]、中心 -LANE、半宽 ROAD_W/2。
        谁把某条带的 z 调小到半宽以内，骑过去就是一头撞进房子/树里 ——
        而带子权重、语法、九套 harness 全绿。这条就是拦那个的。 */
  {
    const worst = [];
    for (const id of OWNBANDS){
      const B = bandOf(id);
      let dmin = 1e9;
      for (const o of B.objs) dmin = Math.min(dmin, Math.abs(o.position.z - (-LANE)));
      worst.push(id + ':' + dmin.toFixed(2));
      uok(B.objs.length > 0 && dmin > ROAD_W/2,
         '「' + id + '」的物件都站在路面之外（最近 ' + dmin.toFixed(2) + ' m > 半宽 ' + (ROAD_W/2).toFixed(2) + ' m）',
         id + ' 最近着地点离路中心 ' + dmin.toFixed(2) + ' m');
    }
    R.push(['I', '—— 段专属带的离路距离 ——', worst.join('  ')]);
  }

  /* ⑤ 路面正上方 RIDE_H 米以内必须是**空的** —— 骑过去撞得到的东西都在这里。
        量的是**世界坐标下的每一个顶点**，不是 o.position，也不是 bbox。
        这两个替代品都试过，各错一半：
          · bbox：索塔的拉索是从塔顶斜下来横过路面的，bbox 是整个对角矩形，
                  max.y 永远等于塔顶高度 —— 低的那一头藏在 bbox 里，看不见。
          · o.position：牌楼的 o.position.z 正好是路中心，量出来是 0；
                  索塔的 o.position 在路肩上，可它的拉索横过路面。
        顶点法两边都对：斜的按真实形状算，跨路的按真实位置算。
        ⚠️ 也正因为它够强，② 那句「离路中心多远」就不能照抄到跨路构件上：
           牌楼本来就该骑在下面，离路中心 0 是**应该**有的值，不是缺陷。 */
  {
    const RIDE_H = 2.00;                   // m：骑手头顶约 1.8 m，留 0.2 余量
    const ALLIDS = ['tunnel','fence','reed','rail','boulder','house',
                    'gate','well','sluice','netrack','litter','bench',
                    'revet','summit','walker','plate','pylon','stele'];
    const v = new THREE.Vector3();
    const hits = [];
    let nverts = 0;
    for (const id of ALLIDS){
      const B = bandOf(id);
      for (const o of B.objs) o.traverse(m => {
        if (!m.isMesh || !m.geometry.attributes.position) return;
        const pos = m.geometry.attributes.position;
        m.updateMatrixWorld(true);
        for (let i = 0; i < pos.count; i++){
          nverts++;
          v.fromBufferAttribute(pos, i).applyMatrix4(m.matrixWorld);
          if (v.y < RIDE_H && v.z > T_MIN && v.z < T_MAX){
            hits.push(id + '@y' + v.y.toFixed(2) + '/z' + v.z.toFixed(2));
            return;                        // 每个 mesh 只报一次，不然刷屏
          }
        }
      });
    }
    uok(ALLIDS.every(id => bandOf(id).objs.length > 0) && nverts > 1000,
       '顶点巡检真的跑起来了（' + nverts + ' 个顶点 / ' + ALLIDS.length + ' 条带，不是空转）',
       'ALLIDS 里每一条带都得有物件，否则下面那条可能在只量一部分的情况下变绿');
    uok(hits.length === 0,
       '路面正上方 ' + RIDE_H.toFixed(2) + ' m 以内没有段专属构件（骑过去撞不到）',
       hits.length ? (hits.length + ' 处压着路面：' + hits.slice(0,5).join(' '))
                   : ALLIDS.length + ' 条带逐顶点量过；路面 z ∈ [' + T_MIN.toFixed(2) + ', ' + T_MAX.toFixed(2) + ']');
  }

  /* ⑤b 反查：把牌楼的两根柱子从 ±2.6 m 收到 ±1.2 m —— 柱子就都站进了
        路面中间。⑤ 必须当场变红，而且要报出是哪一条带。
        （只收柱子不收梁：收的是「脚」，净空那半边本来就该不变。） */
  {
    const B = bandOf('gate');
    const posts = [];
    B.objs.forEach(o => o.traverse(m => { if (m.isMesh && m.geometry.type === 'BoxGeometry'
        && Math.abs(m.geometry.parameters.width - 0.42) < 1e-6) posts.push(m); }));
    const keep = posts.map(m => m.position.z);
    posts.forEach((m, i) => { m.position.z = (i % 2 ? 1 : -1) * 1.2; m.updateMatrixWorld(true); });
    const inRoad = posts.filter(m => { bx.setFromObject(m); return bx.max.z > T_MIN && bx.min.z < T_MAX; }).length;
    posts.forEach((m, i) => { m.position.z = keep[i]; m.updateMatrixWorld(true); });
    uok(posts.length > 0 && inRoad === posts.length,
       '反查 ⑤：把牌楼的柱子收到路中间 → 判据立刻抓到（' + inRoad + '/' + posts.length + ' 根站进了路面）',
       '只判 o.position.z 的写法在这里量到的是 0（牌楼本来就在路中心），' +
       '而 0 在跨路构件上是应该有的值 —— 拿它当保护等于没有保护');
    const back = posts.filter(m => { bx.setFromObject(m); return bx.max.z < T_MIN || bx.min.z > T_MAX; }).length;
    uok(back === posts.length, '反查 ⑤ 收尾：柱子放回 ' + back + '/' + posts.length + ' 根都回到路面外',
       '还原之后 ⑤ 又绿了（上一条不是靠改参数红的）');
  }

  /* ⑥ 「带子里有物件」**不等于**「玩家看得见」。
        applyBands 每帧按权重算 visible，权重算成 0 时整条带子集体隐身 ——
        而 objs.length > 0 照样成立，②③④⑤ 全部照绿，一个红都不会有。
        招牌元素是这一轮新加的十二件，权重表也新加了十二个键，
        正好是最容易「开关忘了接上」的地方。所以这里直接问
        **在本段中点、权重算完之后，还有几件是 visible 的**。
        ⚠️ 问完必须把 visible 还原（调回 applyBands(S.km)），
           否则后面所有判据看到的都是「停在上一段中点」的世界。 */
  {
    const NEW12 = ['gate','well','sluice','netrack','litter','bench',
                   'revet','summit','walker','plate','pylon','stele'];
    const rep = [];
    for (const id of NEW12){
      const B = bandOf(id);
      let seg = -1;
      for (let i = 0; i < ROUTE.length; i++) if (ROUTE[i][id]) seg = i;
      if (seg < 0){ rep.push(id + ':无段'); continue; }
      applyBands(ROUTE[seg].at + ROUTE[seg].km*0.5);
      const vis = B.objs.filter(o => o.visible).length;
      rep.push(id + ':' + vis + '/' + B.objs.length);
      uok(seg >= 0 && vis > 0,
         '「' + id + '」在「' + ROUTE[seg].name + '」段中点真的看得见（' + vis + '/' + B.objs.length + ' 件）',
         'ownW(' + id + ') 在该段中点 = ' + ownW(id, ROUTE[seg].at + ROUTE[seg].km*0.5).toFixed(2) +
         '；算成 0 的话整条带子集体隐身，而 objs.length 仍然是 ' + B.objs.length);
    }
    applyBands(S.km);                     // 还原，别把世界停在别人的段里
    R.push(['J', '—— 12 件招牌元素在本段的可见数 ——', rep.join('  ')]);
  }

  /* ③ 护栏的横杆长度必须等于**组间距**，两段才接得上、看不出缝。
        gap 是从 span/n 算出来的，所以判据也从 span/n 算 ——
        写死 5.333 的话，哪天把 n 从 18 改成 24，这条就成了纯噪音。 */
  {
    const B = bandOf('rail');
    const want = B.span / B.n;
    let lo = 1e9, hi = -1e9;
    for (const o of B.objs){ bx.setFromObject(o); const w = bx.max.x - bx.min.x;
                             lo = Math.min(lo, w); hi = Math.max(hi, w); }
    uok(Math.abs(lo - want) < 0.02 && Math.abs(hi - want) < 0.02,
       '护栏横杆长度 = 组间距（span/n = ' + want.toFixed(3) + ' m，两段接得上）',
       '18 组的 X 跨度：' + lo.toFixed(3) + ' ~ ' + hi.toFixed(3) + ' m');
  }

  /* ④ 六条带的物件都要**落在地面上**（position.y = 0）。
        房子浮在半空、石头埋进土里，都是「画面里一眼可见但没有任何检查会红」的那类。 */
  {
    const badY = [];
    for (const id of OWNBANDS){
      const B = bandOf(id);
      for (const o of B.objs) if (Math.abs(o.position.y) > 1e-6) badY.push(id + '@' + o.position.y.toFixed(2));
    }
    uok(badY.length === 0, '段专属带的物件都落在地面上（position.y = 0，含 12 件招牌元素）',
       badY.length ? ('浮空/入土 ' + badY.length + ' 处：' + badY.slice(0,5).join(' ')) : '17 条带全在 y=0');
  }

  /* ⑤ ?km= 深链。**分两种加载**：带参数时必须真的落在那一公里，
        而且 S0 快照里也得是那个值（深链写在 S0 之后，所以「重置」才回得来）。
        不带参数时必须是 0。
        ⚠️ 判据是**条件式**的，所以只加载不带参数的那一次时，
           「深链生效」那一半等于没测 —— 页面清扫时必须额外跑一次
           _uistate.html?km=2.0，两次的标题都要 PASS 才算数。 */
  {
    const q = KMINIT.q;
    if (q === null){
      uok(KMINIT.km === 0 && KMINIT.s0 === 0, '不带 ?km= 时从 0 起步（这一半不测深链，深链要另跑带参的那次）',
         'S.km=' + KMINIT.km + ' S0.km=' + KMINIT.s0);
    } else {
      const want = parseFloat(q);
      uok(KMINIT.km === want, '?km=' + q + ' → 开局就落在 ' + want + ' km（探针动 S 之前量的）',
         'S.km=' + KMINIT.km);
      uok(KMINIT.s0 === want, '深链写在 S0 快照**之后**，所以「重置」也回到 ' + want + ' km（不是跳回 0）',
         'S0.km=' + KMINIT.s0);
      uok(segAt(KMINIT.km) >= 0 && segAt(KMINIT.km) < ROUTE.length,
         '深链落点能解析出合法段（' + routeName(KMINIT.km) + '）', 'segAt(' + KMINIT.km + ')=' + segAt(KMINIT.km));
    }
  }
}

/* ── 5. 六段各有各的光 ──
   段专属物件分六段了，光却是全局一套 —— 严格说还是「一条路的六段」。
   applySegLight 在 composeMood 算完之后叠一层修正，**不碰那张全局表**。
   下面这几条钉的是「层」的行为：段内取值、加权平均、跨段连续、与天气/时段正交。 */
{
  /* 固定一个已知的天气/时段，后面所有数都从它推，别拿当前状态当基线 */
  applyMood('day', 'clear');
  const m0 = MOOD;
  const center = ROUTE.map((s,i) => s.at + s.km*0.5);
  const probe  = () => { const o = [];
    for (const km of center){ applySegLight(km);
      o.push({ km, dir:dir.intensity, hemi:hemi.intensity,
               far:scene.fog.far, exp:renderer.toneMappingExposure,
               cr:dir.color.r, cb:dir.color.b }); }
    return o; };
  const P = probe();

  /* ① 六个段的直射光必须**两两不同**，且都等于该段档案值 × 全局值。
        段内只有这一段的存在度是 1，加权平均必然精确等于档案值 ——
        这条同时钉住了「加权平均没有写成累加」。 */
  const pairs = P.map((p,i) => p.dir - m0.dirI * SEGLIGHT[i].dir);
  uok(pairs.every(d => Math.abs(d) < 1e-6),
     '段内取值 = 全局值 × 该段档案值（加权平均，不是累加）',
     '六段偏差：' + pairs.map(d => d.toExponential(1)).join(' '));
  uok(new Set(P.map(p => p.dir.toFixed(4))).size === P.length,
     '六段的直射光两两不同（' + P.map(p => p.dir.toFixed(2)).join(' / ') + '）',
     P.map((p,i) => ROUTE[i].name + ':' + p.dir.toFixed(2)).join(' '));

  /* ② 两条真正在画面上说得通的对比，而不是「数值不一样就行」：
        林荫头顶有树冠，直射光必须明显低于开阔的河堤/长桥；
        长桥最开阔，雾的远端必须比林荫远。 */
  const byName = n => P[ROUTE.findIndex(s => s.name === n)];
  uok(byName('林荫').dir < byName('河堤').dir * 0.75,
     '林荫的直射光明显低于河堤（树冠把太阳挡掉大半，否则「隧道」只是两排树）',
     '林荫 ' + byName('林荫').dir.toFixed(2) + ' vs 河堤 ' + byName('河堤').dir.toFixed(2));
  uok(byName('长桥').far > byName('林荫').far,
     '长桥的雾看得比林荫远（桥上最开阔）',
     '长桥 ' + byName('长桥').far.toFixed(0) + ' vs 林荫 ' + byName('林荫').far.toFixed(0));
  uok(byName('镇子').cr - byName('镇子').cb > byName('长桥').cr - byName('长桥').cb,
     '镇子的光比长桥暖（土墙瓦顶；用红蓝差当暖度的可观测代理）',
     '镇子 暖度=' + (byName('镇子').cr - byName('镇子').cb).toFixed(3)
     + '  长桥 暖度=' + (byName('长桥').cr - byName('长桥').cb).toFixed(3));

  /* ③ 跨段界必须**连续**：村口→河堤那一段，篱笆在矮、芦苇在长，
        光也得跟着滑过去，不能在段界上跳一档。 */
  {
    const b = ROUTE[0].at + ROUTE[0].km;              // 村口/河堤的界
    let prev = null, mono = true, tr = [];
    for (let d = -SEG_BLEND; d <= SEG_BLEND + 1e-9; d += SEG_BLEND*0.2){
      applySegLight(b + d);
      const v = dir.intensity;
      tr.push(d.toFixed(2) + ':' + v.toFixed(3));
      if (prev !== null && v < prev - 1e-9) mono = false;   // 离开林荫方向应是单调上升
      prev = v;
    }
    uok(mono, '跨段界光连续，没有跳档：' + tr.join(' '),
       '段界 ' + b.toFixed(2) + ' km，d 从 -' + SEG_BLEND + ' 到 +' + SEG_BLEND);
  }

  /* ③b 「连续」和「不突兀」是两件事。
        上一条只保证没有**跳档**（单步是连续的），可 2 倍多的亮度变化摊在
        500 m 上，在 36 km/h 下是 50 秒走完 —— 眼睛对亮度的**变化率**
        敏感，函数连续也照样能被看出「灯啪一下亮了」。
        2026-10-01 用户实骑提的就是这个：「晴天从有树荫到没有树荫太突兀」。

        量的量是 **dir + hemi**，不是只看 dir：眼睛感到的亮度是这两盏灯
        一起给的，只看直射会把林荫的变化夸大（0.42 vs 1.10 是 2.6 倍，
        而 dir+hemi 只有 1.9 倍 —— 半球光在林荫只压了 10%，补回来不少）。

        门槛不是拍脑袋的：**用户没 complaint 的那些过渡里最陡的那一个**
        （镇子→长桥）就是上限。超过它的才叫「突兀」，
        而这一条的作用是防止以后有人把任何一段调出新的陡坎。
        ⚠️ 量完把真实数写进 detail —— 免得下次只看到 PASS
           就以为这条是凑出来的。 */
  {
    const STEP = 0.025;                                // km = 25 m
    const lum = () => dir.intensity + hemi.intensity;  // 眼睛感到的亮度
    const rows = [];
    for (let i = 0; i < ROUTE.length; i++){
      const j = (i+1) % ROUTE.length;
      const edge = ROUTE[i].at + ROUTE[i].km;
      let mx = 0, prev = null;
      for (let d = -SEG_BLEND_LIGHT; d <= SEG_BLEND_LIGHT + 1e-9; d += STEP){
        applySegLight(edge + d);
        const v = lum();
        if (prev !== null && prev > 1e-6) mx = Math.max(mx, Math.abs(v - prev)/prev);
        prev = v;
      }
      rows.push({ nm: ROUTE[i].name + '→' + ROUTE[j].name, v: mx * (100/(STEP*1000)) });
    }
    const show = list => list.map(r => r.nm + ' ' + (r.v*100).toFixed(1) + '%').join('  ');
    R.push(['K', '—— 段界亮度变化率（每 100 m）——', show(rows)]);

    /* ⚠️⚠️ 这里踩过两次「拿自己量自己」，两次都是绿的，两次都看不出来：
       第一版排除林荫用子串 `-林荫|林荫-`，**没排掉** ——
         过渡名是 `河堤→林荫`，箭头不是破折号，两边都匹配不上，
         于是「最陡的」拿林荫自己当上限。
       第二版改成 `split('→')` 排对了，**但单位不一致**：
         `worst` 是比例（0.293），上限是从显示字符串里
         `parseFloat('6.3%')` 拿回来的**百分数**（6.3），
         于是判据实际在比 `0.293 <= 6.3` —— 永远成立。
         而 detail 里两个数都印成百分数（29.3% / 6.3%），
         一眼看去「29.3 大于 6.3 却 PASS」只会显得像阈值写松了。
       两条教训都落进了代码结构里，不再靠「记得别写错」：
       ① `rows` 存的是 `{nm, v: 数字}`，**只有打印时才转百分数** ——
          判据比的就是它自己印出来的那个数，不可能再错开。
       ② 上限是**冻住的常量**，不是从被测集合里现算的最大值 ——
          现算的话，上限会跟着被测对象一起漂，永远差一口。
       判据里凡是「排除某一项」，拿**结构**去排（拆开比名字），不拿子串凑。 */
    const SLOPE_CAP = 0.063;   // 6.3%/100 m，来源见下面注释
    /* 6.3% 的来历（不是拍脑袋）：2026-10-01 用户实骑只 complaint 了林荫
       那一进一出，别的四段过渡都骑过去了没提 —— 那四段里最陡的实测值
       （镇子→长桥）就是「不突兀」的定义。冻成常量而不是每次重算，
       是为了让「以后谁调出新的陡坎」真的能变红。 */
    const hasShade = r => r.nm.split('→').includes('林荫');
    const others = rows.filter(r => !hasShade(r));
    const shade  = rows.filter(hasShade);
    const TOL = 5e-4;   // 0.05 个百分点，够吸收打印时的四舍五入

    uok(rows.length === 6 && others.length === 4 && shade.length === 2,
       '六个过渡都量到了，并按「有没有林荫」分成 4 + 2 两组（分组本身是下面两条的前提）',
       '不含林荫：' + others.map(r => r.nm).join(' ') + '｜含林荫：' + shade.map(r => r.nm).join(' '));

    const wo = others.reduce((a, r) => Math.max(a, r.v), 0);
    uok(wo <= SLOPE_CAP + TOL,
       '不含林荫的四段过渡都不陡（上限 6.3%/100 m，冻住的常量）',
       '最陡 ' + (wo*100).toFixed(1) + '%/100 m。36 km/h 下 100 m = 10 秒。逐段：' + show(rows));

    const ws = shade.reduce((a, r) => Math.max(a, r.v), 0);
    const wsAt = shade.filter(r => r.v === ws).map(r => r.nm).join(' ');
    /* ⚠️ 这条的**理由在 2026-10-02 换过一次**，写在这儿免得下次又照着旧理由读它。
       原话是「这正是用户实骑提的那一条」—— **不对**。用户明确说了：突兀来自
       **演示切镜**，不是骑行；骑行那一侧由 ③c 量的「一帧跳多少」负责。
       判据挂着一已被证伪的理由，比没有判据更坏 —— 它让数字显得像有意为之。
       所以现在这条只做一件事：**防回退**，调亮之后不许再变陡。
       上限 16.5% 是「调亮这次改动的成果值」，**冻住的常量**，
       不是从被测集合里现算的最大值（那样上限会跟着被测对象一起漂，恒过）。
       ⚠️ 这个常量的依据比原来那个弱：原来是「用户骑过没意见」，
          现在是「用户还没骑过」。要更强的依据得等用户实骑一次。 */
    const SHADE_CAP = 0.165;
    uok(ws <= SHADE_CAP + TOL,
       '林荫那一进一出：调亮之后不许再变陡（防回退，不是「不突兀」）',
       '最陡 ' + (ws*100).toFixed(1) + '%/100 m，发生在 ' + wsAt +
       '。上限 16.5% = 调亮（SEGLIGHT[2].dir 0.42→0.66）之后的成果值，实测砍掉 44%。' +
       '调亮这条路到头了：0.82 仍有 10.3%，而那时隧道已不像隧道。' +
       '⚠️ 用户尚未实骑确认这个值。参考：不含林荫的四段最陡 6.3%。');

    /* 反查 ⑪：上面那条是绿的，所以得证明它不是恒过。
       把上限砍一半 → 「四段都不陡」必须翻 false。
       （上一版正是恒过的：0.293 和 6.3 跨单位比，砍半也抓不到。） */
    {
      const half = SLOPE_CAP / 2;
      const caught = others.filter(r => r.v > half + TOL);
      uok(caught.length > 0,
         '反查 ⑪：上限砍半后「四段都不陡」立刻翻 false（证明它不是恒过）',
         '砍半后上限 ' + (half*100).toFixed(2) + '%/100 m，被抓到：' +
         (caught.length ? show(caught) : '（一条都没抓到 —— 那这条判据就是空的）'));
    }
  }

  /* ③c 切换时（演示切镜 / 换时段 / 换天气）光不许跳。
     2026-10-02 用户实看指出来的：「不是骑行中显得突兀，是演示效果切换的时候」。
     量出来确实如此：镜2→3 河堤 1.2 km → 林荫 2.0 km，时段天气一字未改，
     亮度**一帧掉 32%**；SEG_BLEND_LIGHT 那 0.25 km 渐变在切镜时压根没参与。
     ⚠️ 我先前用「每 100 m 变化率」去描述它 —— 那量的是**匀速骑过段界**，
        是另一个现象。切镜是**一帧之内**的跳变，根本没有「每 100 m」这回事。
        判据问错了层面，后面的排查方向就整体偏了：照着斜率去调段光，
        而斜率再小也管不到那一帧。所以「这里问的是什么」写死在下面。

     这里测的是过渡**原语本身**，故意不去调 dirShot ——
     dirShot 会顺手改 S / CAM / MOOD / 场景内容，漏还原一项，
     后面几条判据量的就不是同一个世界了（而那种错误不会报错，只会静悄悄地偏）。
     「dirShot 到底有没有接上」交给最后那条源码断言。 */
  {
    const cf = o => ({ on:o.on, armed:o.armed, t:o.t, dur:o.dur,
                       sd:o.sd, sh:o.sh, se:o.se, gd:o.gd, gh:o.gh, ge:o.ge,
                       sc:o.sc.clone(), shc:o.shc.clone(), shg:o.shg.clone(),
                       gc:o.gc.clone(), ghc:o.ghc.clone(), ghg:o.ghg.clone() });
    const sv = { d: dir.intensity, h: hemi.intensity, e: renderer.toneMappingExposure,
                 dc: dir.color.clone(), hc: hemi.color.clone(), hg: hemi.groundColor.clone(),
                 f: cf(FADE) };
    const restore = () => {
      dir.intensity = sv.d; hemi.intensity = sv.h; renderer.toneMappingExposure = sv.e;
      dir.color.copy(sv.dc); hemi.color.copy(sv.hc); hemi.groundColor.copy(sv.hg);
      const f = sv.f;
      FADE.on = f.on; FADE.armed = f.armed; FADE.t = f.t; FADE.dur = f.dur;
      FADE.sd = f.sd; FADE.sh = f.sh; FADE.se = f.se;
      FADE.gd = f.gd; FADE.gh = f.gh; FADE.ge = f.ge;
      FADE.sc.copy(f.sc); FADE.shc.copy(f.shc); FADE.shg.copy(f.shg);
      FADE.gc.copy(f.gc); FADE.ghc.copy(f.ghc); FADE.ghg.copy(f.ghg);
    };
    /* 一次完整的过渡：切换前显示 2.0，切换那一刻写 4.0，
       然后按 1/60 一步走完。量「切完当帧显示什么」和「单帧最多变多少」。
       FADE 的内部状态一并带出来 —— 上一版就是「55 帧一动不动」，
       光看亮度看不出是 on 被关了还是 dur 读错了。 */
    const runFade = (dur, doRestore) => {
      FADE.dur = dur; FADE.t = 0; FADE.armed = false; FADE.on = true;
      FADE.sd = 1.0; FADE.sh = 1.0; FADE.se = 1.0;
      FADE.sc.setHex(0xffffff); FADE.shc.setHex(0xffffff); FADE.shg.setHex(0x808080);
      dir.color.setHex(0xffffff); hemi.color.setHex(0xffffff); hemi.groundColor.setHex(0x808080);
      dir.intensity = 2.2; hemi.intensity = 1.8; renderer.toneMappingExposure = 0.94;
      if (doRestore) lightFadeStep(0);
      const atCut = dir.intensity + hemi.intensity;
      let mx = 0, prev = atCut, n = 0;
      for (let t = 0; t < dur + 1/60; t += 1/60){
        lightFadeStep(1/60); n++;
        const v = dir.intensity + hemi.intensity;
        if (prev > 1e-6) mx = Math.max(mx, Math.abs(v - prev)/prev);
        prev = v;
      }
      return { atCut, mx, n, end: dir.intensity + hemi.intensity,
               endE: renderer.toneMappingExposure,
               on: FADE.on, armed: FADE.armed, tt: FADE.t, dd: FADE.dur, gd: FADE.gd };
    };
    const ok        = runFade(0.9,  true);    // 现状
    const noRestore = runFade(0.9,  false);   // 反查：忘了「按回去」那一步
    const tooFast   = runFade(0.02, true);    // 反查：过渡被压成一眨眼
    restore();

    uok(Math.abs(ok.atCut - 2.0) < 1e-9,
       '切完那一帧显示的还是切换前的光（不然就是「先闪一下再倒回来」）',
       '切完当帧 ' + ok.atCut.toFixed(3) + '（应 2.000）。省掉 lightFadeStep(0) 的话这里是 ' +
       noRestore.atCut.toFixed(3) + ' —— 一帧到位，正是用户看到的那一下');
    uok(Math.abs(ok.end - 4.0) < 1e-6 && Math.abs(ok.endE - 0.94) < 1e-6,
       '过渡走完要**精确落在**目标上，不是停在半路',
       ok.n + ' 帧后亮度 ' + ok.end.toFixed(3) + '（目标 4.000）、曝光 ' + ok.endE.toFixed(3) +
       '（目标 0.940）。走完 FADE.on=' + ok.on + ' armed=' + ok.armed +
       ' t=' + ok.tt.toFixed(3) + ' dur=' + ok.dd + ' 钉住的目标 dir=' + ok.gd.toFixed(3));
    uok(ok.mx <= 0.05,
       '过渡期间每帧的亮度变化 ≤ 5%（0.9 s 把整个落差摊掉）',
       '单帧最大 ' + (ok.mx*100).toFixed(1) + '%，共 ' + ok.n + ' 帧。' +
       '不做过渡 = 100%（一帧到位）；把时长压到 0.02 s = ' + (tooFast.mx*100).toFixed(0) + '%');
    uok(dirShot.toString().indexOf('lightFadeIn') >= 0 && dirShot.toString().indexOf('lightFadeStep') >= 0
       && frame.toString().indexOf('lightFadeStep') >= 0,
       '这套过渡真的接在切镜和帧循环上（不然上面测的是一个没人调用的原语）',
       'dirShot：' + (dirShot.toString().indexOf('lightFadeIn')  >= 0 ? '有' : '没有') + ' lightFadeIn、' +
                 (dirShot.toString().indexOf('lightFadeStep') >= 0 ? '有' : '没有') + ' lightFadeStep(0)；' +
       'frame：'  + (frame.toString().indexOf('lightFadeStep')   >= 0 ? '有' : '没有') + ' lightFadeStep(dt)');
  }

  /* ④ 阴天**不该有树荫**。
        2026-10-01 用户实骑指出来的：「下雨怎么可能有树荫」—— 对，
        云层下面没有成束的光，也就没有束的边界，不该有硬边树影扫过路面。
        ⚠️ 我原先在这里守的是**反过来的**东西：「下雨天林荫照样比河堤暗，
           段的光是叠在天气之上的」—— 那等于把「下雨有树荫」写成了要求，
           还给它配了一条判据守着。判据守着错的东西，比没有判据更坏：
           它让错误显得像是有意为之。
        所以这里改成问画面本身：**阴天时直射光不投影**。
        「林荫比别处暗一点」是另一回事（天穹被树冠挡了一块，任何天气下
        都成立），那件事仍由 SEGLIGHT 负责，两件事别混成一件。 */
  {
    const shadows = [];
    for (const wk of ['clear','rain','snow','fog']){
      applyMood('day', wk);
      applySegLight(center[ROUTE.findIndex(s=>s.name==='林荫')]);
      shadows.push(wk + '=' + dir.castShadow);
    }
    uok(dir.castShadow === false,
       '阴天（刚切到雾）直射光不投影 —— 路面均匀受光，没有硬边树荫',
       '四种天气的 dir.castShadow：' + shadows.join('  '));
    uok(WEATHER.clear.k === 0 && WEATHER.rain.k > 0 && WEATHER.snow.k > 0 && WEATHER.fog.k > 0,
       '只有晴天才开阴影（这条判据的前提本身也得成立）',
       'WEATHER 的 k：clear=' + WEATHER.clear.k + ' rain=' + WEATHER.rain.k +
       ' snow=' + WEATHER.snow.k + ' fog=' + WEATHER.fog.k);
    applyMood('day', 'clear');
    uok(dir.castShadow === true, '切回晴天，投影要回来（上一条不是恒真的）',
       'clear 时 dir.castShadow = ' + dir.castShadow + '，林荫那 44 棵树的硬边影回来了');
    /* 阴天仍然可以比旁边暗，但那是「天穹被树冠挡了一块」，
       不是「有影子」。幅度上不该再有晴天那么狠 —— 所以只要求弱于晴天。 */
    const R = [];
    for (const km of center){ applySegLight(km); R.push(dir.intensity); }
    uok(R[ROUTE.findIndex(s=>s.name==='林荫')] < R[ROUTE.findIndex(s=>s.name==='河堤')],
       '阴天林荫仍比河堤暗一点（天穹被树冠挡住一块，这一条与天气无关）',
       R.map((v,i) => ROUTE[i].name + ':' + v.toFixed(2)).join(' '));
    applyMood('night', 'clear');
    const N = [];
    for (const km of center){ applySegLight(km); N.push(dir.intensity); }
    uok(N[ROUTE.findIndex(s=>s.name==='林荫')] < N[ROUTE.findIndex(s=>s.name==='河堤')] * 0.75,
       '夜晚林荫照样比河堤暗（段光关系与时段无关）',
       N.map((v,i) => ROUTE[i].name + ':' + v.toFixed(2)).join(' '));
    applyMood('day', 'clear');
  }

  /* ⑤ 每帧真的调用了。applySegLight 是个函数，写对了不叫就等于没有 ——
        和 applyBands 同一类问题，所以单独钉一条。 */
  {
    /* ⚠️ 取样点原来选的是「村口/河堤交界」和「长桥」，红在 1.134 → 1.134。
       那两处的档案倍率是 1.076 和 1.08 —— 本来就几乎一样，差 0.004，
       却拿 0.05 当门槛。**判据的取样点必须挑有量程的那两个**，
       挑两个天然接近的点，等于在测噪声。
       这里改用林荫（0.42），差一个数量级。 */
    const a = ROUTE[0].at + ROUTE[0].km + SEG_BLEND*0.5;   // 界后一点：半档
    applySegLight(a);
    const want = dir.intensity;
    S.km = ROUTE[2].at + ROUTE[2].km*0.5;                  // 挪到林荫
    S.seg = segAt(S.km);
    frame();
    uok(Math.abs(dir.intensity - want) > 0.2,
       'frame() 每帧把光带着 km 走：tick 一次后 dir 从 ' + want.toFixed(3)
       + ' 变成 ' + dir.intensity.toFixed(3),
       'km=' + S.km.toFixed(2) + '（林荫，档案 0.42）');
    applySegLight(a);
  }
  R.push(['I', '—— 六段光档案实测 ——',
    ROUTE.map((s,i) => s.name + ' dir×' + SEGLIGHT[i].dir + ' hemi×' + SEGLIGHT[i].hemi
                      + ' far×' + SEGLIGHT[i].fogFar).join('\n')]);
}

/* ── 6. 导演模式 ──
   它是**一张分镜表**，不是「自动巡航换个名字」：每镜跳到自己的公里数、
   切自己的时段/天气/机位。下面钉的是这张表和这台机器的接线。 */
{
  uok(!!el('bDir'), '面板上有「导演模式」的入口（不是藏在某个快捷键里）', 'b' + (el('bDir') ? 'Dir 存在' : 'Dir 不存在'));
  uok(SHOTS.length >= 6, '分镜表有 ' + SHOTS.length + ' 镜（够把六段走一遍）');

  /* ① 覆盖面。**这是本节最要紧的一条**：用户要的是「把所有能力演示一遍」，
        所以判据必须数「演示到了没有」，而不是数「代码写了几行」。
        少一个天气就算没做完 —— 所以这里是集合比对，不是钉具体是哪一镜。 */
  {
    const segs = new Set(), wks = new Set(), tks = new Set(), cams = new Set();
    let cinShots = 0;
    for (const s of SHOTS){
      segs.add(routeName(s.km));
      wks.add(s.wk); tks.add(s.tk); cams.add(s.cam);
      if (s.cin) cinShots++;
      // 每一镜的落点必须真在它自己的那一段里（按段表算，不钉死 0.3/1.2）
      uok(s.km >= 0 && s.km < ROUTE_LEN, '第 ' + SHOTS.indexOf(s) + ' 镜的落点 ' + s.km + ' km 在全程内');
    }
    const names = ROUTE.map(r => r.name);
    uok([...segs].length === names.length,
       '六段都走到了（' + [...segs].join('·') + '）',
       '走到的段：' + [...segs].join(' ') + ' / 六段：' + names.join(' '));
    uok(wks.size === Object.keys(WEATHER).length,
       '四种天气都演示到了（' + [...wks].join('·') + '）', [...wks].join(' '));
    uok(tks.size === Object.keys(TIMES).length,
       '三个时段都演示到了（' + [...tks].join('·') + '）', [...tks].join(' '));
    uok(cinShots > 0, '至少有一镜是电影模式（' + cinShots + ' 镜）');
    uok(cams.size >= 3, '用到了 ' + cams.size + ' 种机位');
    for (const c of cams) uok(c === 'bSpin' || !!CAMS[c], '机位 ' + c + ' 在机位表里（有出处，不是手写的一组数）');
  }

  /* ② 一镜一镜跑：公里数、时段、天气、机位、电影模式，逐项对上分镜表。 */
  {
    let bad = [];
    for (let i = 0; i < SHOTS.length; i++){
      const s = SHOTS[i];
      dirStop();
      el('bDir').click();                 // 真点面板上那个键
      for (let k = 0; k < i; k++) dirShot(k + 1);   // 快进到第 i 镜
      const r = { km:S.km, seg:S.seg, tk:MOOD.tk, wk:MOOD.wk, cin:CIN.on, cam:CAM.spin ? 'bSpin' : null };
      if (Math.abs(S.km - s.km) > 1e-6)       bad.push('第' + i + '镜 km ' + S.km + '≠' + s.km);
      if (S.seg !== segAt(s.km))             bad.push('第' + i + '镜 seg 没跟着走');
      if (MOOD.tk !== s.tk)                  bad.push('第' + i + '镜 时段 ' + MOOD.tk + '≠' + s.tk);
      if (MOOD.wk !== s.wk)                  bad.push('第' + i + '镜 天气 ' + MOOD.wk + '≠' + s.wk);
      if (CIN.on !== !!s.cin)                bad.push('第' + i + '镜 电影模式 ' + CIN.on + '≠' + !!s.cin);
      if (!r.cam && !(s.cam === 'bSpin')) {
        const lit = ['bFollow','bFront','bBack','bBird','bBike'].filter(b => el(b).classList.contains('on'));
        if (lit[0] !== s.cam) bad.push('第' + i + '镜 机位 ' + lit.join() + '≠' + s.cam);
      }
    }
    uok(bad.length === 0, '八镜逐项对上分镜表：公里/段/时段/天气/机位/电影模式',
       bad.length ? bad.join('; ') : SHOTS.map(s => s.km + 'km ' + s.tk + '/' + s.wk).join('  '));
  }

  /* ③ 走完一轮会绕回第 1 镜，不是停在最后一镜不动。 */
  {
    dirStop(); el('bDir').click();
    const before = DIR.i;
    DIR.t = SHOTS[before].dur;              // 把这一镜的时长用完
    frame();
    uok(DIR.i === (before + 1) % SHOTS.length,
       '时长到了自动切下一镜（第 ' + (before + 1) + ' 镜 → 第 ' + DIR.i + ' 镜），走完绕回第 1 镜',
       'i=' + before + ' → ' + DIR.i + '，共 ' + SHOTS.length + ' 镜');
  }

  /* ④ 停：Esc 和再点一下都得停，灯也得灭。
        ⚠️ 这一条最要紧的不是「能停」，是**电影模式那一镜也得能停** ——
           电影模式会把面板藏起来，用户连按钮都点不着，只能靠 Esc。
           所以 Esc 这条不是可有可无的便利，是唯一的出路。 */
  {
    const toCine = SHOTS.findIndex(s => s.cin);
    dirStop(); el('bDir').click();
    for (let k = 0; k <= toCine; k++) dirShot(k);
    const inCine = CIN.on;
    document.dispatchEvent(new KeyboardEvent('keydown', { code:'Escape', bubbles:true }));
    uok(DIR.on === false, 'Esc 能停导演模式（这是电影模式那一镜唯一的出路）', 'DIR.on=' + DIR.on);
    uok(!el('bDir').classList.contains('on'), '停了以后面板上那盏灯跟着灭');
    uok(inCine && !CIN.on, '进了电影模式的那一镜，退出时电影模式也一并收掉（不能把人留在全屏里）',
       '进电影模式=' + inCine + ' 退出后=' + CIN.on);
    el('bDir').click();
    uok(DIR.on === true, '再点一下能重新开始');
    el('bDir').click();
    uok(DIR.on === false, '再点一下能停（按钮是开关，不是「只进不出」）');
  }

  /* ⑤ 用户本来就在电影模式里看，导演不该把它带走。 */
  {
    enterCinema();
    const wasOn = CIN.on;
    const d0 = { on:DIR.on, put:DIR.putCinema };
    el('bDir').click();
    const d1 = { on:DIR.on, put:DIR.putCinema, cin:CIN.on };
    dirStop();
    uok(wasOn && CIN.on, '导演结束时**不**退出用户自己进的电影模式',
       'enterCinema 后 CIN.on=' + wasOn + ' | click 前 DIR=' + JSON.stringify(d0)
       + ' | click 后=' + JSON.stringify(d1) + ' | dirStop 后 CIN.on=' + CIN.on);
    exitCinema();
  }
  dirStop();
  applyMood('day', 'clear');
  S.km = 0; S.seg = -1; S.cruise = false; el('bCruise').classList.remove('on');
  setCamMode('bSpin', true);
}

/* ── 输出 ── */
/* 计数一律靠 `typeof x[0] === 'boolean'` 认「这是一条断言」，
   不靠标记字母 —— 摘要行标 'I' 还是 'J' 都一样，
   而标错字母的后果是页面报出「PASS 147/148」这种自相矛盾的标题。 */
const isU = x => typeof x[0] === 'boolean';
const bad = R.filter(x => isU(x) && !x[0]);
let h = '<h3>' + (R.filter(x => isU(x) && x[0]).length) + ' / ' + R.filter(isU).length + ' 通过</h3>';
if (bad.length){
  h += '<div style="color:#ff6b6b;margin:6px 0 10px">下面 ' + bad.length + ' 条没过：</div>';
  for (const [c,n,d] of bad) h += '<div class="bad">FAIL  ' + n + (d ? '   [' + d + ']' : '') + '</div>';
  h += '<hr>';
}
for (const [c,n,d] of R){
  if (!isU([c])) { h += '<div class="info" style="color:#8a97a9;margin:8px 0 2px">' + n + '</div>'
                      + '<pre style="white-space:pre-wrap;color:#8a97a9;font-size:11px">' + d + '</pre>'; continue; }
  h += '<div class="' + (c ? 'ok' : 'bad') + '">' + (c ? 'PASS  ' : 'FAIL  ') + n + (d ? '   [' + d + ']' : '') + '</div>';
}
let box = document.getElementById('uicheck');
if (!box){ box = document.createElement('pre'); box.id = 'uicheck';
  box.style.cssText = 'position:fixed;inset:0;z-index:99999;overflow:auto;margin:0;padding:14px;'
                     + 'background:#0b0e13;color:#e9eef6;font:12px/1.5 Consolas,monospace;white-space:pre-wrap';
  document.body.appendChild(box); }
box.innerHTML = h;
document.title = (bad.length ? 'FAIL ' : 'PASS ') + R.filter(x => isU(x) && x[0]).length
               + '/' + R.filter(isU).length;
})();
'@

$t = $t.Substring(0, $i) + "`n" + $probe + $t.Substring($i)
[IO.File]::WriteAllText($out, $t, (New-Object Text.UTF8Encoding($false)))
"wrote {0}  {1:N0} bytes" -f (Split-Path $out -Leaf), (Get-Item $out).Length
& powershell -NoProfile -ExecutionPolicy Bypass -File ($S_SYNTAX) -Path $out
exit $LASTEXITCODE