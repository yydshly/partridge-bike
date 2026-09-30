$ErrorActionPreference = 'Stop'
# 临时取景脚本：从**成品** partridge-3d.html 复制一份，把一段钩子插在启动调用之前。
# 为什么不能直接看成品：后台标签页里 rAF 被冻结，截图永远停在首帧，
# 而「切到雨/雪/雾」需要 applyMood()，它在主 IIFE 里、不是全局。
# 所以只能把钩子插进 IIFE 内部，再同步跑一段天气粒子、render 一次、
# 把 canvas 拷进一个尺寸写死的 2D 画布贴到页面最上层，然后截屏。
# ⚠️ 调试画布必须显式写 style 的 width/height —— 页面里有一条
#    canvas{width:100%;height:100%}，只设 width/height 属性会被拉成整屏。
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
$dir = $ROOT
$out = $OUT_DBG
$t = [IO.File]::ReadAllText(($PRODUCT))

$hook = @'
/* __DBG__ */
(function(){
  const q = new URLSearchParams(location.search);
  const t = q.get('t'), w = q.get('w');
  if (t || w) applyMood(t || MOOD.tk, w || MOOD.wk);
  S.running = false;
  S.speed = parseFloat(q.get('v') || '18');
  // 同步把天气粒子推进 N 步：截图要的是「雨真的在下」的中间态，不是空盒子
  const N = parseInt(q.get('steps') || '160', 10);
  const d = S.speed/3.6 * (1/60);
  for (let i=0;i<N;i++){ S.tSec += 1/60; updateWeather(1/60, d); }
  if (q.get('roll') === '1'){
    for (let i=0;i<N;i++){
      for (const o of world){
        o.position.x -= d;
        if (o.position.x < -o.userData.span*0.5){
          o.position.x += o.userData.span;
          if (o.userData.onWrap) o.userData.onWrap(o);
        }
      }
    }
  }
  // 镜头是内联在 frame() 里算的，没有独立的 updateCamera()。
  // 后台标签页里 rAF 冻住 → clock.getDelta() 约等于 0 → 镜头的插值一步也走不动，
  // 于是这里先把当前值直接对齐到目标值，再手动摆一次 position/lookAt。
  CAM.az = CAM.azT; CAM.pol = CAM.polT; CAM.dist = CAM.distT;
  CAM.target.z = S.lat*0.66;
  camera.position.set(
    CAM.target.x + CAM.dist*Math.sin(CAM.pol)*Math.cos(CAM.az),
    CAM.target.y + CAM.dist*Math.cos(CAM.pol),
    CAM.target.z + CAM.dist*Math.sin(CAM.pol)*Math.sin(CAM.az)
  );
  camera.lookAt(CAM.target);
  renderer.render(scene, camera);
  // 面板挡在右边，挪到左边去，别盖住取景区
  const p = document.querySelector('.panel'); if (p) p.style.left = 'auto';
  const out = document.createElement('canvas');
  out.width = 1000; out.height = 562;
  out.style.cssText = 'position:fixed;left:0;top:0;z-index:99999;width:1000px;height:562px';
  document.body.appendChild(out);
  out.getContext('2d').drawImage(cv, 0, 0, out.width, out.height);
  // 顺手把生效状态和判定读数写进 title，人眼不用猜
  const lit = [...document.querySelectorAll('.panel button.on')].map(b => b.id).join(',');
  document.title = 'DBG ' + MOOD.label + ' | lit=' + lit +
    ' | rain=' + MOOD.rain + ' snow=' + MOOD.snow + ' wet=' + MOOD.wet +
    ' | fogFar=' + MOOD.fogFar.toFixed(0) + ' vis=' + (RAIN.obj.visible ? 1 : 0) +
    '/' + (SNOW.obj.visible ? 1 : 0) +
    ' roadFx=' + (roadFx.visible ? 1 : 0) + '@' + roadFx.material.opacity.toFixed(2) +
    ' groundFx=' + (groundFx.visible ? 1 : 0) + '@' + groundFx.material.opacity.toFixed(2) +
    ' | ground=#' + groundMat.color.getHexString() + ' road=#' + roadMesh.material.color.getHexString() +
    ' leafA=#' + M.leafA.color.getHexString() + ' roof=#' + M.roofSlate.color.getHexString();
})();
'@

# 插在启动调用之前 —— 那一行在主 IIFE 里，钩子因此能摸到 applyMood / renderer / MOOD。
# 用 LastIndexOf 找**最后**一处：文件里 requestAnimationFrame(frame); 出现两次
# （frame() 开头那次续链 + 文件末尾这次启动），最后那处才是启动调用。
# 成品是 CRLF，所以按 \n 回退到行首再插，别去匹配带 \r\n 的整行。
$i = $t.LastIndexOf('requestAnimationFrame(frame);')
if ($i -lt 0) { throw 'startup call not found' }
$lineStart = $t.LastIndexOf("`n", $i) + 1
$t = $t.Substring(0, $lineStart) + $hook + "`n" + $t.Substring($lineStart)
[IO.File]::WriteAllText($out, $t, (New-Object Text.UTF8Encoding($false)))
"wrote: {0:N0} bytes" -f (Get-Item $out).Length