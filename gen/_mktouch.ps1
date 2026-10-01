# 窄屏 / 触屏手势体检。跟 _mkuistate 一个路子：把探针注入**成品副本**，
# 插在最后一个 `\n})();` 之前 —— 它在闭包里，所以 PTR / pinch / CAM 读得到。
#
# 它量两件以前完全没人量的东西：
#   ① 触屏手势。改之前相机只有「单指拖 = 环绕」和「滚轮 = 缩放」两件事，
#      而触屏上 e.button 恒为 0（右键平移那条分支永远进不去）、没有 wheel
#      事件、也没有任何 pinch —— 提示语里那三样，手机上一样都不成立。
#   ② 窄屏布局。改之前整个项目一条 @media 都没有。
#
# 布局怎么量：iframe + srcdoc。把**成品里那一段 <style> 和 #wrap 的真实 DOM**
# 原样搬进一个 390×844 的 iframe，于是量到的就是发布出去的那份布局，
# 而不是一份会漂的副本。不用整个产品：布局是纯 CSS + 静态 HTML，
# three.js 和那 11 MB 音频一点都用不上（不然每开一次要 11.7 MB）。
#
# 合成事件的两个坑（_mkuistate 已经踩过一次，这里照抄规矩）：
#   - 必须派到**监听器所在的元素**上（cv），派给 window 传不进去；
#   - setPointerCapture 在合成事件上会抛，产品代码 try/catch 吞掉了，不用管。
$ErrorActionPreference = 'Stop'
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
$dir = $ROOT
$src = $PRODUCT
$out = $OUT_TOUCH
if (-not (Test-Path $src)) { throw "先跑 _build.ps1：找不到 $src" }

$t = [IO.File]::ReadAllText($src)
$anchor = "`n})();"
$i = $t.LastIndexOf($anchor)
if ($i -lt 0) { throw '找不到最后的 `n})();`，注入点定位失败' }
"注入点偏移 {0:N0} / 全文 {1:N0}" -f $i, $t.Length

$probe = @'
/* ═══ 窄屏 / 触屏手势体检（_mktouch.ps1 注入，只存在于 _touchharness.html）═══ */
/* ⚠️ 整个体检体外面必须包一层「异常也出结论」。
   之前没有，于是任何一个 await 抛异常（iframe 的 load 事件在后台标签页里不触发、
   getComputedStyle 撞到 null……）的后果是：**整页一行输出都没有、标题也不变**，
   看起来像「还没跑完」，实际上是早就死了。而「还在跑」和「已经死了」
   在屏幕上长得一模一样 —— 这正是这个项目反复交的学费。
   所以：阶段名实时写进标题，异常也要渲染成一条 FAIL。 */
const R = [];                      // 提到 async 外面：catch 里要读它，
                                   // 否则「已经跑完多少条」在异常时根本报不出来
(async function(){
const stage = s => { document.title = '…' + s; };
const ok   = (c,n,d) => R.push([!!c, n, d===undefined ? '' : String(d)]);
const info = (n,d)   => R.push(['I', n, d===undefined ? '' : String(d)]);
const close = a => Math.abs(a) < 1e-9;

function pev(type, id, x, y, button){
  const up = (type === 'pointerup' || type === 'pointercancel');
  return cv.dispatchEvent(new PointerEvent(type, {
    bubbles:true, cancelable:true,
    clientX:x, clientY:y, button:button||0, buttons:up?0:1,
    pointerId:id, pointerType:'touch', isPrimary:(id===1)
  }));
}
/* 每个用例都从同一个已知初值出发，别让上一条把量污染了 */
function reset(){
  CAM.az = CAM.azT = 0; CAM.pol = CAM.polT = 1.05; CAM.dist = CAM.distT = 3.9;
  CAM.target.set(0, 0.62, 0); CAM.panning = false; CAM.dragging = false;
  PTR.clear(); pinch = null; cv.classList.remove('dragging');
}

/* ── 1. 单指拖 = 环绕。桌面原行为，一个比特都不能变 ── */
reset();
pev('pointerdown', 1, 600, 300, 0);
pev('pointermove', 1, 760, 300, 0);
ok(close(CAM.azT - (-160*0.0072)), '单指横拖 160px → azT 正好 -dx×0.0072', 'azT=' + CAM.azT.toFixed(6));
ok(CAM.polT === 1.05, '横拖（dy=0）不该动 polT', 'polT=' + CAM.polT);
ok(close(CAM.distT - 3.9), '单指拖**不碰**缩放', 'distT=' + CAM.distT);
pev('pointerup', 1, 760, 300, 0);
ok(CAM.dragging === false && PTR.size === 0, '抬起后 dragging=false 且指针表清空',
   'dragging=' + CAM.dragging + ' size=' + PTR.size);

/* ── 2. 右键拖 = 平移（桌面回归：e.button===2 那条分支还在） ── */
reset();
pev('pointerdown', 1, 400, 300, 2);
pev('pointermove', 1, 500, 300, 2);
ok(Math.abs(CAM.target.x) > 0.001 || Math.abs(CAM.target.z) > 0.001,
   '右键拖 → 镜头真的平移了',
   'target=' + CAM.target.x.toFixed(4) + ',' + CAM.target.y.toFixed(4) + ',' + CAM.target.z.toFixed(4));
ok(close(CAM.azT - 0), '右键拖不该转镜头（azT 仍是 0）', 'azT=' + CAM.azT);
pev('pointerup', 1, 500, 300, 2);

/* ── 3. 双指：张开 = 拉近，捏合 = 拉远（手机上以前根本没有） ── */
reset();
pev('pointerdown', 1, 450, 300);
pev('pointerdown', 2, 550, 300);          // 间距 100
pev('pointermove', 2, 650, 300);          // 间距 200
ok(close(CAM.distT - 1.95), '双指张开 100→200px → distT 减半（拉近）', 'distT=' + CAM.distT.toFixed(4));
pev('pointermove', 2, 550, 300);          // 回到 100
ok(close(CAM.distT - 3.9), '双指捏回 200→100px → distT 回到 3.9', 'distT=' + CAM.distT.toFixed(4));
ok(close(CAM.azT - 0) && close(CAM.polT - 1.05),
   '双指全程 azT/polT 一个数都不动（中点位移走的是平移分支，不是环绕）',
   'azT=' + CAM.azT + ' polT=' + CAM.polT);
pev('pointerup', 1, 450, 300); pev('pointerup', 2, 550, 300);

/* ── 4. 间距没变 = 只平移，不缩放 ── */
reset();
pev('pointerdown', 1, 400, 300);
pev('pointerdown', 2, 500, 300);          // 中点 450,300
pev('pointermove', 1, 450, 340);          // 两指同向平移，间距还是 100
pev('pointermove', 2, 550, 340);
ok(CAM.target.y > 0.70, '两指同向平移（间距不变）→ 镜头跟着平移',
   'target=' + CAM.target.x.toFixed(4) + ',' + CAM.target.y.toFixed(4) + ',' + CAM.target.z.toFixed(4));
ok(close(CAM.distT - 3.9), '间距一格没变 → 缩放也一个数都不动', 'distT=' + CAM.distT.toFixed(6));
pev('pointerup', 1, 450, 340); pev('pointerup', 2, 550, 340);

/* ── 5. 夹紧：捏到底 / 张到头都不许越界（和滚轮同一个范围） ── */
reset();
pev('pointerdown', 1, 400, 300);
pev('pointerdown', 2, 1400, 300);         // 间距 1000
pev('pointermove', 2, 500, 300);          // 间距 100 → 放大 10 倍
ok(CAM.distT === 16, '捏到最近也只到 16（和滚轮同一个上限）', 'distT=' + CAM.distT);
pev('pointerup', 1, 400, 300); pev('pointerup', 2, 500, 300);
reset();
pev('pointerdown', 1, 400, 300);
pev('pointerdown', 2, 500, 300);
pev('pointermove', 2, 1400, 300);
ok(CAM.distT === 1, '张到最开也只到 1（和滚轮同一个下限）', 'distT=' + CAM.distT);
pev('pointerup', 1, 400, 300); pev('pointerup', 2, 1400, 300);

/* ── 6. 两指回到一指：不许跳一下（双指手势最常见的坑） ── */
reset();
pev('pointerdown', 1, 400, 300);
pev('pointerdown', 2, 500, 300);
pev('pointermove', 1, 600, 300);
const azMid = CAM.azT;
pev('pointerup', 2, 600, 300);            // 抬掉 id2，id1 停在 600
ok(PTR.size === 1, '抬掉一根后还剩一根在拖', 'size=' + PTR.size);
pev('pointermove', 1, 620, 300);          // 从 600 走到 620，dx=20
ok(close(CAM.azT - (-20*0.0072)),
   '两指回到一指后从抬手处重新起算（镜头没有猛地甩一下）',
   'azT ' + azMid.toFixed(6) + ' → ' + CAM.azT.toFixed(6) + '，不跳变时期望 -0.144000');
pev('pointerup', 1, 620, 300);

/* ── 7. 没按下的指针不许动镜头 ── */
reset();
pev('pointermove', 99, 800, 300);
ok(CAM.azT === 0 && close(CAM.distT - 3.9), '没按下的指针 move 被忽略',
   'azT=' + CAM.azT + ' distT=' + CAM.distT);

/* ── 8. 提示语：两套文案，触屏那套不许出现手机上不存在的手势 ── */
const hDesk = document.querySelector('.hint .h-desk');
const hMob  = document.querySelector('.hint .h-mob');
ok(!!hDesk && !!hMob, '提示条里有两套文案（桌面 / 触屏）', hDesk && hMob ? '两套都在' : '缺一套');
ok(!!hMob && !/右键|滚轮/.test(hMob.textContent),
   '触屏文案里没有「右键 / 滚轮」（触屏上这两样根本不存在）',
   hMob ? '「' + hMob.textContent.trim() + '」' : '（DOM 里没有 .h-mob）');

/* ── 9. 窄屏布局：真的量矩形，不靠看图 ── */
const cssText  = document.querySelector('style').textContent;
const wrapHTML = document.getElementById('wrap').outerHTML;
const mkDoc = css => '<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">'
  + '<meta name="viewport" content="width=device-width,initial-scale=1">'
  + '<style>' + css + '</style></head><body>' + wrapHTML + '</body></html>';

const CASES = [
  { w:390, h:844, tag:'iPhone 竖',  narrow:true,  short:false, desk:false, minTap:36 },
  { w:360, h:640, tag:'安卓 竖',    narrow:true,  short:false, desk:false, minTap:36 },
  { w:320, h:568, tag:'SE 一代 竖', narrow:true,  short:false, desk:false, minTap:36 },
  { w:852, h:390, tag:'iPhone 横',  narrow:false, short:true,  desk:false, minTap:36 },
  /* ⚠️ 桌面这一档是补上的：加了两套文案之后我只验了窄屏，
     从来没验过**宽屏下桌面文案还在、窄屏规则没漏出来**。
     于是只能靠看一张半透明的截图猜「那个提示条显示的是哪一套」——
     而上一次这么猜（parridge / partridge）就白花了一小时。
     宽屏的数字：桌面按钮本来就 ~30px 高，所以下限另给，别拿触控标准去卡它。 */
  { w:1280, h:900, tag:'桌面',      narrow:false, short:false, desk:true,  minTap:24 }
];

async function measure(css, c){
  const f = document.createElement('iframe');
  f.setAttribute('aria-hidden','true');
  f.style.cssText = 'width:' + c.w + 'px;height:' + c.h + 'px;border:0;position:absolute;left:-99999px;top:0';
  document.body.appendChild(f);
  await new Promise(res => { f.onload = res; f.srcdoc = mkDoc(css); });
  const d = f.contentDocument, w = f.contentWindow;
  const rect = e => e.getBoundingClientRect();
  /* ① 谁最靠右 —— 溢出判据要点名到具体元素，不能只报一个数 */
  let worst = null, maxR = -1e9;
  for (const e of d.querySelectorAll('#wrap *')){
    const r = rect(e);
    if (!r.width && !r.height) continue;
    if (r.right > maxR){ maxR = r.right; worst = e; }
  }
  /* ② 哪个按钮太小 —— 同样点名
     ⚠️ **藏在 display:none 子树里的按钮必须跳过**。电影模式的浮条平时整条
        display:none，它那五个按钮量出来是 0×0 —— 而 0×0 不是「触控目标太小」，
        是「这个按钮这一档根本不存在」。混进去之后 5 档全红，
        而红的原因是判据量错了对象，不是产品做错了。 */
  const inHidden = e => {
    for (let n = e; n && n !== d.documentElement; n = n.parentElement){
      if (w.getComputedStyle(n).display === 'none') return true;
    }
    return false;
  };
  const small = [];
  for (const b of d.querySelectorAll('button')){
    if (inHidden(b)) continue;
    const r = rect(b);
    if (r.width < c.minTap || r.height < c.minTap) small.push('#' + (b.id || '?') + ' ' + Math.round(r.width) + '×' + Math.round(r.height));
  }
  /* ⚠️ getComputedStyle 是**每个 window 一份**的，跨 iframe 必须用 iframe 自己的，
     用主窗口那份去问 iframe 的元素，量到的是主窗口的规则。 */
  const disp = sel => { const e = d.querySelector(sel); return e ? w.getComputedStyle(e).display : '(没有这个元素)'; };
  const hudEl = d.querySelector('.hud'), hinEl = d.querySelector('.hint'), stEl = d.querySelector('.stage');
  const hud = hudEl ? rect(hudEl) : null, hin = hinEl ? rect(hinEl) : null;
  const overlap = !!(hud && hin && hud.width && hin.width
      && hud.left < hin.right && hin.left < hud.right
      && hud.top  < hin.bottom && hin.top  < hud.bottom);
  const stageW = stEl ? rect(stEl).width : 0;
  const out = {
    maxR: Math.round(maxR),
    worst: worst ? worst.tagName.toLowerCase() + (worst.id ? '#'+worst.id : '')
             + (worst.className ? '.' + String(worst.className).split(' ').join('.') : '') : '(空)',
    small, tip:disp('.tip'), desk:disp('.h-desk'), mob:disp('.h-mob'), hint:disp('.hint'),
    stage: stEl ? Math.round(rect(stEl).bottom) : -1, overlap,
    /* 窄屏规则有没有漏到宽屏去：桌面的 HUD 是「贴右上角」的一小块，
       窄屏那条把它拉成了整条横幅（left/right 都给上）。量宽度占比最直接。 */
    hudRatio: (hud && stageW) ? +(hud.width / stageW).toFixed(2) : -1,
    /* 报重叠必须报出两个矩形各在哪、差多少 —— 只说「压在一起了」等于没点名 */
    hudBox: hud ? [Math.round(hud.left), Math.round(hud.right), Math.round(hud.top), Math.round(hud.bottom)].join(',') : '(无)',
    hinBox: hin ? [Math.round(hin.left), Math.round(hin.right), Math.round(hin.top), Math.round(hin.bottom)].join(',') : '(无)'
  };
  f.remove();
  return out;
}

stage('量常规布局');
for (const c of CASES){
  const m = await measure(cssText, c);
  info(c.tag + ' ' + c.w + '×' + c.h, '最右 ' + m.maxR + 'px（' + m.worst + '）· 小按钮 '
       + m.small.length + ' 个 · tip=' + m.tip + ' hint=' + m.hint + ' · 舞台底边 ' + m.stage + 'px');
  /* ⚠️ 通过时也要说「≤」：写成「最右 367px > 视口 390px」挂在一条 PASS 后面，
     绿字里混着一句看起来像报错的话，人就开始不看输出了。 */
  ok(m.maxR <= c.w, c.tag + ' ' + c.w + '×' + c.h + '：没有元素横着溢出到屏幕外',
     m.maxR <= c.w ? '最右 ' + m.maxR + 'px ≤ 视口 ' + c.w + 'px（最靠右的是 ' + m.worst + '）'
                   : '最右 ' + m.maxR + 'px，超出视口 ' + (m.maxR - c.w) + 'px，出头的是 ' + m.worst);
  ok(m.small.length === 0, c.tag + '：每个按钮都够点（≥' + c.minTap + '×' + c.minTap + '）',
     m.small.length ? m.small.length + ' 个太小：' + m.small.slice(0,4).join(' ') : '全部达标');
  if (c.narrow){
    ok(m.tip === 'none', c.tag + '：键盘提示条在窄屏收掉了', 'display=' + m.tip);
    ok(m.desk === 'none' && m.mob !== 'none', c.tag + '：窄屏显示的是触屏文案',
       'h-desk=' + m.desk + ' h-mob=' + m.mob);
    ok(!m.overlap, c.tag + '：HUD 和提示条不重叠',
       'HUD(left,right,top,bottom)=' + m.hudBox + ' 提示条=' + m.hinBox
       + '（视口 ' + c.w + 'px 宽）');
    ok(m.stage < c.h * 0.6, c.tag + '：舞台没把面板顶出屏外（够得着、能往下滚）',
       '舞台底边 ' + m.stage + 'px / 视口高 ' + c.h + 'px');
  }
  if (c.desk){
    /* 桌面这一档：证明窄屏规则**没有**漏出来。少了它，「宽屏下显示的是哪套文案」
       就只能靠看一张半透明的截图猜 —— 而这么猜过一次，白花了一小时。 */
    ok(m.desk !== 'none' && m.mob === 'none',
       c.tag + '：宽屏显示的是桌面文案（鼠标那套），触屏文案收起来了',
       'h-desk=' + m.desk + ' h-mob=' + m.mob);
    ok(m.tip !== 'none', c.tag + '：键盘提示条在桌面还在（窄屏那条 display:none 没漏过来）',
       'display=' + m.tip);
    ok(m.hudRatio > 0 && m.hudRatio < 0.6,
       c.tag + '：HUD 还是贴右上角的一小块，没被窄屏那条拉成整条横幅',
       'HUD 宽度是舞台的 ' + (m.hudRatio * 100).toFixed(0) + '%（窄屏那条是 100%）');
    ok(!m.overlap, c.tag + '：HUD 和提示条不重叠',
       'HUD=' + m.hudBox + ' 提示条=' + m.hinBox);
  }
  if (c.short){
    ok(m.hint === 'none', c.tag + '：横屏把提示条收掉了（不然和 HUD 抢地方）', 'display=' + m.hint);
    ok(m.stage < c.h, c.tag + '：横屏时舞台让出了高度，面板还在屏内',
       '舞台底边 ' + m.stage + 'px / 视口高 ' + c.h + 'px');
  }
}

/* ══════════════ 电影模式 ══════════════
   电影模式是本轮新增的「看得见」的功能，而看得见的东西一旦只靠人眼看，
   下次改布局就没人知道它有没有坏。所以它也得有判据。
   量法和上面一样：把**成品里真实的 CSS 和 #wrap 的真实 DOM** 搬进 iframe，
   给 documentElement 挂上 .cin，然后量真实矩形和真实 computed style。 */

/* ⚠️ 必须先把 transition 关掉再量。.hud/.hint 的淡出淡出是 .45s 的 transition，
   而 getComputedStyle 返回的是**当前动画值**而不是目标值 ——
   刚挂上 .cin 就去读 opacity，读到的是还没开始淡的 1，判据于是恒过。
   这不是「量得不准」，是量到的是另一条时间线上的东西。
   transition 本身是观感，不在判据范围内（人眼看），判据只管目标状态。 */
const CSS_STILL = cssText + '\n*{transition:none !important;animation:none !important}';

async function measureCinema(css, c){
  const f = document.createElement('iframe');
  f.setAttribute('aria-hidden','true');
  f.style.cssText = 'width:' + c.w + 'px;height:' + c.h + 'px;border:0;position:absolute;left:-99999px;top:0';
  document.body.appendChild(f);
  await new Promise(res => { f.onload = res; f.srcdoc = mkDoc(css); });
  const d = f.contentDocument, w = f.contentWindow;
  const cs = sel => { const e = d.querySelector(sel); return e ? w.getComputedStyle(e) : null; };
  const rc = sel => { const e = d.querySelector(sel); if (!e) return null;
                      const r = e.getBoundingClientRect();
                      return { l:Math.round(r.left), t:Math.round(r.top),
                               r:Math.round(r.right), b:Math.round(r.bottom),
                               w:Math.round(r.width), h:Math.round(r.height) }; };
  const hgt = () => { const e = d.querySelector('.stage'); return e ? Math.round(e.getBoundingClientRect().height) : -1; };
  const root = d.documentElement;
  const out = { panelBefore: cs('.panel') ? cs('.panel').display : '(没有面板)',
                stageBefore: hgt(), vh: c.h, vw: c.w,
                barBefore: cs('.cinebar') ? cs('.cinebar').display : '(没有浮条)',
                boxBefore: cs('.sidebox') ? cs('.sidebox').display : '(没有侧边框)' };
  root.classList.add('cin');
  out.panel   = cs('.panel')  ? cs('.panel').display  : '(没有面板)';
  out.err     = cs('#err')    ? cs('#err').display    : '(没有 err)';
  out.hudOp   = cs('.hud')    ? +cs('.hud').opacity   : -1;
  out.hudDur  = cs('.hud')    ? cs('.hud').transitionDuration : '?';
  out.capOp   = cs('.cap')    ? +cs('.cap').opacity   : -1;
  out.bodyPad = cs('body')    ? cs('body').paddingTop : '?';
  out.stageCin = hgt();
  out.barD    = cs('.cinebar') ? cs('.cinebar').display : '(没有浮条)';
  out.barOp   = cs('.cinebar') ? +cs('.cinebar').opacity : -1;
  out.boxD    = cs('.sidebox') ? cs('.sidebox').display : '(没有侧边框)';
  out.boxRect = rc('.sidebox');
  root.classList.add('over');
  out.hudOpOver = cs('.hud') ? +cs('.hud').opacity : -1;
  /* 浮条「淡回来」这件事有两个面：看得见（opacity）和摸得着（pointer-events）。
     少了后一个，浮条就是一条压在画面上、但把底下拖镜头手势全吃掉的透明带 ——
     而画面上根本看不出它在那儿。 */
  out.barOpOver = cs('.cinebar') ? +cs('.cinebar').opacity : -1;
  out.barPeOver = cs('.cinebar') ? cs('.cinebar').pointerEvents : '?';
  out.barRect   = rc('.cinebar');
  out.capRect   = rc('.cap');
  root.classList.add('bare');
  out.barD_bare = cs('.cinebar') ? cs('.cinebar').display : '(没有浮条)';
  out.boxD_bare = cs('.sidebox') ? cs('.sidebox').display : '(没有侧边框)';
  root.classList.remove('bare');
  root.classList.remove('cin', 'over');
  out.panelAfter = cs('.panel') ? cs('.panel').display : '(没有面板)';
  out.stageAfter = hgt();
  f.remove();
  return out;
}

for (const c of CASES){
  if (!(c.w === 390 || c.w === 852 || c.w === 1280)) continue;   // 三档代表：竖手机 / 横手机 / 桌面
  stage('电影模式 ' + c.tag + ' ' + c.w + '×' + c.h);
  const m = await measureCinema(CSS_STILL, c);
  const tag = c.tag + ' ' + c.w + '×' + c.h;
  ok(m.panelBefore !== 'none', tag + '：进电影模式**之前**面板是在的（好样本不误伤）',
     'display=' + m.panelBefore);
  ok(m.panel === 'none' && m.err === 'none', tag + '：电影模式下面板和错误框都收起来了',
     '.panel=' + m.panel + ' #err=' + m.err);
  ok(m.hudOp === 0, tag + '：HUD 淡出到全透明（只留画面）', 'opacity=' + m.hudOp);
  ok(Math.abs(m.stageCin - m.vh) <= 2, tag + '：舞台铺满视口高度（不是留了一条边）',
     '舞台高 ' + m.stageCin + 'px / 视口高 ' + m.vh + 'px，差 ' + (m.stageCin - m.vh) + 'px');
  ok(m.hudOpOver === 1, tag + '：动一下之后（.over）HUD 淡回来，还能操作',
     'opacity=' + m.hudOpOver);
  ok(m.panelAfter === m.panelBefore, tag + '：退出电影模式后面板原样回来',
     m.panelBefore + ' → ' + m.panel + ' → ' + m.panelAfter);
  /* 台词是**内容**不是界面：藏掉它，画面里就只剩一只鸟在骑，
     这个角色全部的性格都没了。所以这一条是钉住「别顺手一起藏了」。 */
  ok(m.capOp > 0.9, tag + '：台词仍然留着（内容不是界面，别一起藏掉）', '.cap opacity=' + m.capOp);

  /* ── 极简控制条 + 侧边小框：量真实矩形，不靠看图 ──
     看得见的东西一旦只靠人眼看，下次改布局就没人知道它有没有坏。 */
  ok(m.barBefore === 'none' && m.boxBefore === 'contents',
     tag + '：进电影模式之前浮条不存在、侧边框壳是 display:contents（不进盒树，不动老布局）',
     'bar=' + m.barBefore + ' sidebox=' + m.boxBefore);
  ok(m.barD === 'flex', tag + '：电影模式里浮条真的出现了', '.cinebar display=' + m.barD);
  ok(m.barOp === 0, tag + '：浮条默认**藏着的**（不动鼠标就不该有东西压在画面上）',
     '.cinebar opacity=' + m.barOp);
  ok(m.barOpOver === 1 && m.barPeOver === 'auto',
     tag + '：动一下（.over）浮条淡回来，而且这时才接管鼠标事件',
     'opacity=' + m.barOpOver + ' pointer-events=' + m.barPeOver);
  ok(m.barD_bare === 'none' && m.boxD_bare === 'none',
     tag + '：纯画面（.bare）→ 浮条和侧边框都藏起来，只剩画面和台词',
     'bar=' + m.barD_bare + ' sidebox=' + m.boxD_bare);

  const b = m.barRect, x = m.boxRect, cp = m.capRect, vw = m.vw, vh = m.vh;
  ok(b && x && b.w > 0 && b.h > 0 && x.w > 0 && x.h > 0,
     tag + '：两个盒子都量得到**非空**的真实矩形',
     'bar=' + JSON.stringify(b) + ' sidebox=' + JSON.stringify(x));
  if (b && x && b.w > 0 && x.w > 0){
    const inView = o => o.l >= -1 && o.t >= -1 && o.r <= vw + 1 && o.b <= vh + 1;
    ok(inView(b) && inView(x), tag + '：两个盒子整个都在视口里（不能有一半在屏幕外）',
       '视口 ' + vw + '×' + vh + ' / bar ' + JSON.stringify(b) + ' / sidebox ' + JSON.stringify(x));
    /* 浮条在下方，而且**横着不越过画面中线** —— 中线是鹧鸪在的地方。
       不写死「左」还是「右」：它现在是左下角，但断言真正要说的是
       「不许横穿中心」，位置换了这条也不用改。
       ⚠️ 但这条性质**在竖屏上不成立**，第一版把它写成无条件的，
          结果 390px 竖屏直接判红 —— 浮条 5 个按钮最窄 256px，
          而半屏只有 195px。塞不下就是塞不下，判据不能假装它塞得下。
          所以先问「它塞得进半屏吗」：塞得进才要求不跨中线；
          塞不进的档位把「不适用」写进消息里，别让人以为它逃过了检查。
          将来浮条哪天变窄到 195 以下，这条会在竖屏自动开始生效。 */
    const halfFits = (b.w + 40) <= vw / 2;
    const crossesMid = b.l < vw / 2 && b.r > vw / 2;
    ok(b.b > vh * 0.5 && (!halfFits || !crossesMid),
       tag + '：浮条在**下方**'
          + (halfFits ? '，且不横穿画面中线（不挡鹧鸪）'
                      : '（这一档浮条 ' + b.w + 'px 宽，半屏只有 ' + Math.round(vw / 2)
                         + 'px，物理上放不下，「不跨中线」这条不适用）'),
       'bar ' + JSON.stringify(b) + ' / 视口 ' + vw + '×' + vh);
    /* 侧边框不能盖住正中间：0.35 而不是 0.5，因为竖屏那条窄屏规则
       会把它压到 52vw 宽，盒子左沿本来就在中线左边一点点。 */
    ok(x.l > vw * 0.35 && x.r <= vw + 1,
       tag + '：侧边框贴着**右边**，且不吃掉画面正中',
       'sidebox 左 ' + x.l + '，视口宽 ' + vw + '（要求 >' + Math.round(vw * 0.35) + '）');
    /* ⚠️ 这条是从**真人的反馈**来的，不是从设计稿：第一版把它竖着摆在
       右侧正中（top:50%），一眼就发现它横穿画面、一直挡着鹧鸪。
       所以钉的是「**不许待在竖向中间那条带子里**」——
       桌面/横屏在右下角、竖屏在右上角，两边都算过，但正中不行。 */
    ok(x.b < vh * 0.45 || x.t > vh * 0.55,
       tag + '：侧边框**不在竖向正中**（挡视线的那条带子，上下都算，但中间不行）',
       'sidebox 顶 ' + x.t + ' 底 ' + x.b + ' / 视口高 ' + vh
       + '（中间带 ' + Math.round(vh * 0.45) + '–' + Math.round(vh * 0.55) + '）');
    const hit = (p, q) => p.l < q.r && q.l < p.r && p.t < q.b && q.t < p.b;
    ok(!hit(b, x), tag + '：浮条和侧边框**不重叠**（两个都看不见是它们的活）',
       JSON.stringify(b) + ' vs ' + JSON.stringify(x));
    ok(cp && !hit(b, cp), tag + '：浮条**不压住台词**（台词是内容，压住了就等于藏掉）',
       'cap=' + JSON.stringify(cp) + ' bar=' + JSON.stringify(b));
  }
}

stage('反查');
/* ═══ 反查 ═══
   上面每一条布局判据读的都是 iframe 里的真实矩形。最大的风险不是「判据错了」，
   而是「量到的全是 0，所以恒过」——那种情况下它会一路全绿而什么也没量到。
   所以先证明它抓得住：把这次加的那两段 @media 整段抠掉（正是改动之前的样子），
   同一批判据必须翻红。方向不能写反 —— 是「装回旧的」，不是「把状态弄脏」。 */
const cssNoMedia = cssText.replace(/@media[^{]*\{(?:[^{}]|\{[^{}]*\})*\}/g, '');
ok(cssNoMedia !== cssText && cssNoMedia.length < cssText.length,
   '反查前提：抠掉 @media 之后 CSS 真的变了',
   '原 ' + cssText.length + ' 字 → 剩 ' + cssNoMedia.length + ' 字');
{
  const m = await measure(cssNoMedia, CASES[0]);
  info('反查（无 @media）390×844', '最右 ' + m.maxR + 'px（' + m.worst + '）· 小按钮 '
       + m.small.length + ' 个：' + m.small.slice(0,5).join(' ') + ' · tip=' + m.tip);
  ok(m.small.length > 0, '反查 ①：没有窄屏规则 → 按钮真的太小（判据抓得住）',
     m.small.length + ' 个小于 36px：' + m.small.slice(0,3).join(' '));
  ok(m.tip !== 'none', '反查 ②：没有窄屏规则 → 键盘提示条又露出来了（判据抓得住）', 'display=' + m.tip);
  ok(m.desk !== 'none', '反查 ③：没有窄屏规则 → 鼠标文案压在手机上（判据抓得住）', 'display=' + m.desk);
}

/* 手势侧的反查，同样是「装回旧的」 */
{
  reset();
  pev('pointerdown', 1, 450, 300);
  pev('pointerdown', 2, 550, 300);
  const before = CAM.distT;
  PTR.delete(2);                          // ← 旧实现：第二根手指进不来
  pev('pointermove', 1, 760, 300);
  ok(close(CAM.distT - before),
     '反查 ④：第二根手指被忽略时 distT 不动 → 第 3 条量的是「双指」不是「单指」',
     'distT ' + before + ' → ' + CAM.distT.toFixed(4));
  pev('pointerup', 1, 760, 300); pev('pointerup', 2, 550, 300);
}
{
  reset();
  pev('pointerdown', 1, 400, 300);
  pev('pointerdown', 2, 500, 300);
  pev('pointermove', 1, 600, 300);
  pev('pointerup', 2, 600, 300);
  CAM.lastX = 400; CAM.lastY = 300;       // ← 旧实现：两指回到一指不重新播种
  pev('pointermove', 1, 620, 300);
  ok(!(close(CAM.azT - (-20*0.0072))),
     '反查 ⑤：不重新播种 → 第 6 条「回到一指不跳变」确实翻 false',
     'azT=' + CAM.azT.toFixed(6) + '，不跳变时期望 -0.144000');
  pev('pointerup', 1, 620, 300);
}

/* 电影模式的反查，方向同样是「装回旧的」：
   把 CSS 里所有 `.cin` 选择器改名，让它们一条都匹配不上 ——
   效果就是「电影模式这套 CSS 根本不存在」，也就是本轮改动之前的样子。 */
{
  const cssNoCin = cssText.replace(/\.cin\b/g, '.cinXX');
  ok(cssNoCin !== cssText, '反查 ⑥：把 .cin 改名之后 CSS 真的变了',
     '原 ' + cssText.length + ' 字 → 剩 ' + cssNoCin.length + ' 字');
  const m = await measureCinema(cssNoCin + '\n*{transition:none !important;animation:none !important}', CASES[0]);
  ok(m.panel !== 'none', '反查 ⑦：没有电影模式 CSS → 面板收不起来（第 2 条量的是它）',
     '.panel display=' + m.panel);
  ok(m.hudOp === 1, '反查 ⑧：没有电影模式 CSS → HUD 不会淡出（第 3 条量的是它）',
     '.hud opacity=' + m.hudOp);
  ok(Math.abs(m.stageCin - m.vh) > 2, '反查 ⑨：没有电影模式 CSS → 舞台铺不满（第 4 条量的是满屏）',
     '舞台高 ' + m.stageCin + 'px / 视口高 ' + m.vh + 'px');
  /* 反查 ⑩：判据必须先关掉 transition，否则量到的是**动画当前值**而不是目标值。
     这里量的是一个**确定的事实**（过渡时长非零），不是「跑得够快还是慢」——
     第一版写成「开着过渡时 opacity 读到 1」，那是拿时序当判据，
     在慢机器上就可能读到 0.5，两边都不对。
     量时长则永远稳定，而且它直接说明了「为什么必须关」。 */
  const mAnim = await measureCinema(cssText, CASES[0]);   // 不加 !important 关动画
  const dur = mAnim.hudDur || '';
  ok(dur !== '' && dur !== '0s' && dur !== '0s, 0s',
     '反查 ⑩：HUD 确实有过渡（非 0s）→ 不关掉它，opacity 读到的是动画值而不是目标值',
     '.hud transition-duration=' + dur);
  /* 反查 ⑪⑫：把 .cin 全改名之后，浮条和侧边框那几条必须**跟着失效**。
     它们是新加的断言，最典型的恒过形态就是「元素一直在那儿，
     只不过永远量不到该有的状态」—— 不拆一次就不知道它们在不在量东西。 */
  ok(m.barD === 'none', '反查 ⑪：没有电影模式 CSS → 浮条不会出现（量它的那几条量的就是它）',
     '.cinebar display=' + m.barD);
  ok(m.boxD === 'contents', '反查 ⑫：没有电影模式 CSS → 侧边框不会变成盒子（量它的那几条量的就是它）',
     '.sidebox display=' + m.boxD);
}

/* 反查 ⑬⑭：上面那两条**位置**判据也得抓得住。
   ⑪⑫ 只拆了「浮条/侧边框在不在」—— 位置判据最典型的恒过形态是
   「量到的矩形一直是同一个数，条件恰好成立」。所以把两样东西各自
   摆回**正中**：浮条水平居中（横穿中线）、侧边框垂直居中（待在中间带）。
   方向是「摆成坏的」，不是把状态弄脏。
   两条都挑**桌面档**量 —— 那是 halfFits 成立、判据真正生效的地方。 */
{
  const cDesk = CASES.find(c => c.w === 1280);
  ok(!!cDesk, '反查前提：三档里有桌面那一档（1280）', '没找到就说明下面的反查在偷懒');
  if (cDesk){
    const barMid = CSS_STILL
      + '\n.cin .cinebar{left:50% !important;right:auto !important;transform:translateX(-50%)}';
    const mb = await measureCinema(barMid, cDesk);
    const b2 = mb.barRect, vw2 = mb.vw;
    ok(b2 && b2.l < vw2 / 2 && b2.r > vw2 / 2,
       '反查 ⑬：浮条摆回水平居中 → 「不横穿中线」那条真的会红（不是恒过）',
       'bar=' + JSON.stringify(b2) + ' / 半屏 ' + Math.round(vw2 / 2) + 'px');

    const boxMid = CSS_STILL
      + '\n.cin .sidebox{top:50% !important;bottom:auto !important;transform:translateY(-50%)}';
    const mx = await measureCinema(boxMid, cDesk);
    const x2 = mx.boxRect, vh2 = mx.vh;
    ok(x2 && !(x2.b < vh2 * 0.45 || x2.t > vh2 * 0.55),
       '反查 ⑭：侧边框摆回垂直居中（第一版的老样子）→「不在竖向正中」那条真的会红',
       'sidebox=' + JSON.stringify(x2) + ' / 视口高 ' + vh2 + 'px'
       + '（中间带 ' + Math.round(vh2 * 0.45) + '–' + Math.round(vh2 * 0.55) + '）');
  }
}

/* ── 输出 ── */
/* 计数靠 `typeof x[0] === 'boolean'` 认「这是一条断言」，不靠标记字母。
   和 _mkuistate 同一个坑：摘要行一旦标了 'I' 以外的字母，就会被算进分母
   却永远进不了分子，标题报出「PASS n/(n+1)」这种自相矛盾的东西。 */
const isU = x => typeof x[0] === 'boolean';
const bad = R.filter(x => isU(x) && !x[0]);
const passN = R.filter(x => isU(x) && x[0]).length, totalN = R.filter(isU).length;
let h = '<h3>' + passN + ' / ' + totalN + ' 通过</h3>';
if (bad.length){
  h += '<div style="color:#ff6b6b;margin:6px 0 10px">下面 ' + bad.length + ' 条没过：</div>';
  for (const [c,n,d] of bad) h += '<div class="bad">FAIL  ' + n + (d ? '   [' + d + ']' : '') + '</div>';
  h += '<hr>';
}
for (const [c,n,d] of R){
  if (c === 'I'){ h += '<div class="info" style="color:#8a97a9;margin:8px 0 2px">' + n + '</div>'
                     + '<pre style="white-space:pre-wrap;color:#8a97a9;font-size:11px">' + d + '</pre>'; continue; }
  h += '<div class="' + (c ? 'ok' : 'bad') + '">' + (c ? 'PASS  ' : 'FAIL  ') + n + (d ? '   [' + d + ']' : '') + '</div>';
}
let box = document.getElementById('touchcheck');
if (!box){ box = document.createElement('pre'); box.id = 'touchcheck';
  box.style.cssText = 'position:fixed;inset:0;z-index:99999;overflow:auto;margin:0;padding:14px;'
                     + 'background:#0b0e13;color:#e9eef6;font:12px/1.5 Consolas,monospace;white-space:pre-wrap';
  document.body.appendChild(box); }
box.innerHTML = h;
document.title = (bad.length ? 'FAIL ' : 'PASS ') + passN + '/' + totalN;
/* 异常也算一种结论。写清楚「不完整」而不是让页面保持原样 ——
   保持原样的话，标题还是产品名、人只会以为页面没加载完，
   于是把这一轮当成「没结果」而不是「有结果：体检崩了」。 */
})().catch(e => {
  document.title = 'HARNESS-ERROR';
  let b = document.getElementById('touchcheck');
  if (!b){
    b = document.createElement('pre'); b.id = 'touchcheck';
    b.style.cssText = 'position:fixed;inset:0;z-index:99999;overflow:auto;margin:0;padding:14px;'
                    + 'background:#2a0d0d;color:#ffb4b4;font:12px/1.5 Consolas,monospace;white-space:pre-wrap';
    document.body.appendChild(b);
  }
  b.textContent = '体检体抛异常，这一轮结果**不完整**（不是「还在跑」）：\n\n'
                + (e && e.stack ? e.stack : String(e))
                + '\n\n—— 崩之前已经跑完的 ' + R.filter(isU).length + ' 条 ——\n'
                + R.map(x => (!isU(x) ? 'INFO' : (x[0] ? 'PASS' : 'FAIL')) + '  ' + x[1]).join('\n');
});
'@

$t = $t.Substring(0, $i) + "`n" + $probe + $t.Substring($i)
[IO.File]::WriteAllText($out, $t, (New-Object Text.UTF8Encoding($false)))
"wrote {0}  {1:N0} bytes" -f (Split-Path $out -Leaf), (Get-Item $out).Length
& powershell -NoProfile -ExecutionPolicy Bypass -File ($S_SYNTAX) -Path $out
exit $LASTEXITCODE
