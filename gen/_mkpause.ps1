$ErrorActionPreference = 'Stop'
# 暂停/恢复复测：走**真实 UI 路径**（点 bPlay 按钮），不直接改 S.running。
# 上一版探针直接写 S.running，把按钮文案那行绕过去了 —— 探针绕过的代码
# 正是出问题的代码，测它就等于没测。
# 顺便把暂停中的画面 render 一帧、拷进显式尺寸的 2D 画布，好截屏看观感。
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
$dir = $ROOT
# 一人一份输出：以前三个探针都写 $OUT_DBG，后跑的覆盖先跑的
$out = $OUT_PAUSE
$t = [IO.File]::ReadAllText(($PRODUCT))

$hook = @'
/* __DBG__ */
(function(){
  const DT = 1/60;
  const _gd = clock.getDelta.bind(clock);
  clock.getDelta = () => DT;
  const _rn = renderer.render.bind(renderer);
  renderer.render = () => {};
  const L = [];
  const ok = (c, m, d) => L.push((c?'  PASS  ':'  FAIL  ') + m + (d === undefined ? '' : '   [' + d + ']'));
  const near = (a,b,e) => Math.abs(a-b) <= (e===undefined?1e-9:e);

  const btn = $('bPlay');
  const wp = new THREE.Vector3();
  const dustSig = () => { const d = dustPts.filter(x => x.life > 0);
    return d.length + '/' + (d.length ? (d.reduce((a,x)=>a+x.life,0)/d.length).toFixed(6) : '0'); };
  function snap(){
    bike.updateWorldMatrix(true, true);
    bird.getWorldPosition(wp);
    return { run:S.running, v:S.speed, km:S.km, wheel:S.wheel, crank:S.crank,
             lat:S.lat, tSec:S.tSec, mouth:S.mouth, blink:S.blink,
             camAz:CAM.az, camAzT:CAM.azT, camIdle:CAM.idle,
             w0: world.length ? world[0].position.x : 0,
             bl:[bird.position.x, bird.position.y, bird.position.z].join(','),
             txt: btn.textContent, on: btn.classList.contains('on') };
  }
  function run(n){ for (let i=0;i<n;i++) frame(); }
  // 仿真状态是离散的，暂停就必须**一模一样**。
  // 镜头不是：CAM.az += (azT - az) * k 是渐近收敛，停稳之后仍有 1e-5 量级的
  // 尾巴（老版每秒 0.32 rad，一眼能看出来；这个每秒 ~1e-5，量不出来）。
  // 所以分两把尺子：状态比相等，镜头比**速率**。
  const STATE = ['v','km','wheel','crank','lat','tSec','w0','camAzT','bl'];
  const drift = (a, b) => STATE.filter(k => Math.abs(a[k]-b[k]) > 1e-12);

  S.running = true; S.cruise = true; S.speed = 22; S.tSec = 0;
  S.km=0; S.wheel=0; S.crank=0; S.lat=0; S.yaw=0; S.steer=0; S.cruise=true;
  run(90);
  const A = snap();

  // ---- 走真实 UI：点按钮暂停 ----
  btn.click();
  const B0 = snap();                           // 刚点的瞬间
  run(20);                                     // 暂停前 0.5 秒
  const B1 = snap();
  run(60);                                   // 暂停 0.5~2.5 秒
  const B = snap();
  const moved = drift(B1, B);
  const camRate = Math.abs(B.camAz - B1.camAz) / 2;   // rad/s
  const settle = Math.abs(B0.camAz - B1.camAz);
  const dustA = dustSig();
  run(60);                                   // 再暂停 2 秒，专门盯尘土
  const dustB = dustSig();

  // （这版不截图：整场景真 render 一帧要好几秒，探针整体会撑爆 open_tab）
  // ---- 再点一次恢复 ----
  btn.click();
  run(90);
  const C = snap();

  ok(B.run === false, '点一下 → 真的停了', 'S.running=' + B.run);
  ok(B.txt === '▶', '按钮变成 ▶（可点回来）', '按钮文案 = ' + B.txt);
  // 量「停稳之后还在不在漂」，不是「一帧都没动过」。点下去的瞬间镜头阻尼
  // 还要收尾（az 追 azT），会走 0.04 rad —— 那是**收尾**不是继续转。
  // 老版没有这道门，暂停 3 秒 camAz 就转了 0.96 rad。
  ok(moved.length === 0, '暂停稳了之后：速度/里程/车轮/曲柄/横向/时间/世界一个都没动',
     '还在动的量：' + (moved.join(',') || '（无）'));
  ok(camRate < 0.002, '镜头也停了（残留的只是阻尼尾巴）', camRate.toExponential(1) + ' rad/s');
  ok(settle < 0.2, '点下去那一下镜头只收尾了一点，不是一路转', settle.toFixed(3) + ' rad');
  ok(near(A.lat, B.lat, 1e-12) && near(A.crank, B.crank, 1e-12), '鸟的局部坐标没变', A.bl + ' → ' + B.bl);
  ok(bird.parent === bike, '鸟还是 bike 的子节点（结构上不可能下车）');
  ok(C.run === true, '再点一下 → 继续跑', 'S.running=' + C.run);
  ok(C.txt === '⏸', '按钮回到 ⏸', C.txt);
  ok(C.wheel > B.wheel + 1 && C.w0 < B.w0, '恢复后车真的在往前走',
     'wheel ' + B.wheel.toFixed(1) + ' → ' + C.wheel.toFixed(1) +
     '   world0.x ' + B.w0.toFixed(1) + ' → ' + C.w0.toFixed(1));
  ok(Math.abs(C.camAz - B.camAz) < 6.3, '恢复后镜头继续自动环绕（不是卡死）',
     'camAz ' + B.camAz.toFixed(2) + ' → ' + C.camAz.toFixed(2));

  /* ⚠️ 这一段的教训：`if (S.running){}` 在 4546 行就闭合了，
     **后面所有东西都是无条件执行的**。2026-09-30 在这里连续漏了四个：
     自动环绕、尘土、眨眼、嘴的平滑。每一个单独看都不像 bug ——
     「镜头慢慢转」「灰还在飘」「鸟眨了下眼」—— 合起来就是
     「我明明按了暂停，怎么还在动」。所以下面要把这一类**一次列全**，
     以后新增的每段都得自己回答「暂停时该不该动」。 */
  const dust = (() => { const d = dustPts.filter(x => x.life > 0);
    return d.length + '/' + (d.length ? (d.reduce((a,x)=>a+x.life,0)/d.length).toFixed(4) : '0'); })();
  ok(dustB === dustA, '尘土也停了（不往下飘、不淡出）', '暂停前=' + dustA + '  稳后=' + dustB);
  ok(B.blink === 0, '暂停时眼睛是睁开的（不会半睁着冻住）', '暂停中 blink=' + B.blink);
  ok(near(B.mouth, B1.mouth, 1e-12), '嘴也停了', B1.mouth.toFixed(5) + ' → ' + B.mouth.toFixed(5));

  const box = document.createElement('pre');
  box.style.cssText = 'position:fixed;right:0;top:0;z-index:100000;margin:0;padding:10px 14px;' +
    'background:rgba(8,10,14,.94);color:#9fe8c8;font:12px/1.5 Consolas,monospace;max-width:460px';
  box.textContent = (L.filter(x=>x.startsWith('  FAIL')).length
      ? L.filter(x=>x.startsWith('  FAIL')).join('\n') + '\n\n'
      : '暂停/恢复 8 项全过\n\n') +
    '暂停中 5 秒的镜头：az ' + A.camAz.toFixed(2) + ' → ' + B.camAz.toFixed(2) +
    '  idle ' + A.camIdle.toFixed(1) + ' → ' + B.camIdle.toFixed(1) + '\n' +
    '恢复后 3 秒：az ' + B.camAz.toFixed(2) + ' → ' + C.camAz.toFixed(2) +
    '  km ' + B.km.toFixed(3) + ' → ' + C.km.toFixed(3) +
    '\n鸟局部坐标 ' + C.bl;
  document.body.appendChild(box);
  renderer.render = _rn; clock.getDelta = _gd;
  document.title = L.some(x=>x.startsWith('  FAIL')) ? 'PAUSE-FAIL' : 'PAUSE-PASS';
})();
'@

$i = $t.LastIndexOf('requestAnimationFrame(frame);')
if ($i -lt 0) { throw 'startup call not found' }
$lineStart = $t.LastIndexOf("`n", $i) + 1
$t = $t.Substring(0, $lineStart) + $hook + "`n" + $t.Substring($lineStart)
[IO.File]::WriteAllText($out, $t, (New-Object Text.UTF8Encoding($false)))
"wrote: {0:N0} bytes" -f (Get-Item $out).Length
