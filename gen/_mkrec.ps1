$ErrorActionPreference = 'Stop'
# 录像功能的探针：在成品里插一段钩子，走**真实按钮**那条路。
# 验四件事：① 按钮在 ② 选得到 WebM 编码器 ③ captureStream 抓得到帧
#           ④ 停下来真的出了一个非空的 Blob
# ⚠️ 后台标签页里 rAF 被冻结，画面不出帧，MediaRecorder 会安静地录出
#    一个「能播放但没内容」的文件。所以这里**自己同步调 frame()** 制造画面，
#    并把 clock 钉成 1/60 —— 这样录到的是真帧。
$p = $PSScriptRoot; while (-not (Test-Path (Join-Path $p '_paths.ps1'))) { $p = Split-Path $p -Parent }
if (-not $p) { throw "找不到 _paths.ps1（从 $PSScriptRoot 往上找）" }
. (Join-Path $p '_paths.ps1')
$dir = $ROOT
$out = $OUT_DBG
$t = [IO.File]::ReadAllText(($PRODUCT))

$hook = @'
/* __DBG__ */
(async function(){
  const L = [];
  const ok = (c, m, d) => L.push([!!c, m, d === undefined ? '' : String(d)]);
  const DT = 1/60;
  const _gd = clock.getDelta.bind(clock);
  clock.getDelta = () => DT;

  ok(!!$('bRec'), '面板上有「录」按钮', $('bRec') ? $('bRec').textContent : '没有');
  ok(!!$('bShot'), '原来的 PNG 按钮还在');

  const mimes = ['video/webm;codecs=vp9','video/webm;codecs=vp8','video/webm'];
  const mime = mimes.find(t => window.MediaRecorder && MediaRecorder.isTypeSupported(t));
  ok(!!mime, '选得到 WebM 编码器', mime || '一个都不支持');
  ok(!!cv.captureStream, 'canvas.captureStream 可用');

  // 走真实按钮路径。S.running 必须为真（暂停中按钮会挡回去，这是有意的）。
  S.running = true; S.cruise = true; S.speed = 22; S.tSec = 0;
  S.km=0; S.wheel=0; S.crank=0; S.lat=0; S.yaw=0; S.steer=0;
  for (let i=0;i<60;i++) frame();

  let blob = null, stopped = false, err = '';
  const realCreate = URL.createObjectURL;
  // 拦住下载：a.click() 会真的落盘，探针里换成把 blob 扣下来量大小
  URL.createObjectURL = b => { blob = b; return realCreate.call(URL, b); };
  const realClick = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function(){ if (!this.download) realClick.call(this); };

  $('bRec').click();
  ok(document.getElementById('bRec').classList.contains('on'), '按下去进入录制态（按钮高亮）',
     $('bRec').textContent);
  ok(REC !== null, 'REC 被建立', REC === null ? 'null' : 'ok');

  // 造画面。⚠️ **不能**在一个同步循环里连着调 150 次 frame()：
  // 画布是在任务末尾才提交给合成器的，一次任务只提交一次，
  // captureStream 于是只看到 0~1 帧，录出来是空的（第一版探针就栽在这，
  // 报「没产出 Blob」，看着像功能坏了，其实是探针的问题）。
  // 每两帧让出一次事件循环，合成器才有机会提交。
  const t0 = performance.now();
  let commits = 0;
  for (let k = 0; k < 45; k++){
    frame(); frame();
    commits++;
    await new Promise(r => setTimeout(r, 12));
  }
  const wall = performance.now() - t0;

  await new Promise(r => {
    const chk = setInterval(() => {
      if (blob || (wall > 0 && performance.now() - t0 > 4000)){ clearInterval(chk); r(); }
    }, 50);
    $('bRec').click();                        // 手动停
    setTimeout(() => { if (blob){ clearInterval(chk); r(); } }, 1500);
  });
  await new Promise(r => setTimeout(r, 400)); // 等 onstop

  HTMLAnchorElement.prototype.click = realClick;
  URL.createObjectURL = realCreate;
  clock.getDelta = _gd;

  ok(REC === null, '停下来之后 REC 归零', REC === null ? 'ok' : '还在');
  ok(!$('bRec').classList.contains('on'), '按钮样式复位', $('bRec').textContent);
  ok(!!blob, '真的产出了 Blob', blob ? (blob.size/1024).toFixed(1) + ' KB' : 'null');
  ok(!!blob && blob.size > 20000, 'Blob 不是空的（> 20 KB = 抓到帧了）',
     blob ? (blob.size/1024).toFixed(1) + ' KB' : '—');
  ok(!!blob && /webm/.test(blob.type), '类型是 webm', blob ? blob.type : '—');
  // 45 批 × 12ms ≈ 0.5 秒，30fps 期望 ~15 帧；9 Mbps 下应该有几 MB。
  // 这里只判「抓到了帧」这个下限，帧率/体积在真实前台标签页里才是准的。
  ok(!!blob && blob.size > 60000, '抓到了不止一两帧', blob ? (blob.size/1024).toFixed(0) + ' KB' : '—');
  ok(commits === 45, '探针自己确实画了 45 批', commits + ' 批 / 用时 ' + wall.toFixed(0) + ' ms');

  const bad = L.filter(x => !x[0]);
  const h = (bad.length ? 'FAIL ' + bad.length + '/' + L.length : 'PASS ' + L.length + '/' + L.length)
    + '  录像探针';
  document.title = h;
  const box = document.createElement('pre');
  box.style.cssText = 'position:fixed;right:0;top:0;z-index:99999;margin:0;padding:10px 14px;' +
    'background:rgba(8,10,14,.94);color:#9fe8c8;font:12px/1.5 Consolas,monospace;max-width:420px';
  box.textContent = h + '\n\n' + L.map(([c,m,d]) => (c?'PASS  ':'FAIL  ') + m + (d?'   ['+d+']':'')).join('\n');
  document.body.appendChild(box);
})();
'@

$i = $t.LastIndexOf('requestAnimationFrame(frame);')
if ($i -lt 0) { throw 'startup call not found' }
$lineStart = $t.LastIndexOf("`n", $i) + 1
$t = $t.Substring(0, $lineStart) + $hook + "`n" + $t.Substring($lineStart)
[IO.File]::WriteAllText($out, $t, (New-Object Text.UTF8Encoding($false)))
"wrote: {0:N0} bytes" -f (Get-Item $out).Length