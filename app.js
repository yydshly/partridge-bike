const $=s=>document.querySelector(s);
let data,builds=[],active='minimax',running=false,toastTimer;
const esc=value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const unknown='<span class="missing">未提供</span>';
const toast=text=>{$('#toast').textContent=text;$('#toast').hidden=false;clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('#toast').hidden=true,2300);};
function stop(){running=false;$('#frame-container').replaceChildren();$('.poster').hidden=false;$('#stop-demo').hidden=true;$('#viewer-status').textContent='点击启动后，可直接使用作品自带的控制面板。';}
function select(id,launch=false){
 const run=builds.find(r=>r.id===id);if(!run)return;active=id;stop();
 document.querySelectorAll('[role=tab]').forEach(b=>{const selected=b.dataset.id===id;b.setAttribute('aria-selected',String(selected));b.tabIndex=selected?0:-1;});
 $('#demo-panel').setAttribute('aria-labelledby',`tab-${id}`);
 $('#poster-image').src=run.preview||`previews/${id}.png`;$('#poster-image').alt=`${run.name} 的鹧鸪骑单车作品`;
 $('#features').textContent=run.features.join(' · ');
 $('#standalone').href=run.demoUrl||`demos/${id}/`;$('#download-artifact').href=run.artifactUrl||`demos/${id}/index.html`;$('#download-artifact').download=`${id}-partridge-bike.html`;
 if(launch)start();
}
function start(){
 if(running)return;running=true;$('.poster').hidden=true;$('#stop-demo').hidden=false;$('#viewer-status').textContent='正在加载作品…';
 const run=builds.find(r=>r.id===active);const frame=document.createElement('iframe');frame.title=`${run.name} 3D 鹧鸪骑行交互作品`;frame.src=run.demoUrl||`demos/${active}/`;frame.allow='fullscreen';frame.setAttribute('allowfullscreen','');
 frame.addEventListener('load',()=>{$('#viewer-status').textContent='体验中 · 可拖拽场景、调节速度，或使用作品自带的控制面板。';});
 $('#frame-container').append(frame);
}
function openImage(url,title){$('#evidence-title').textContent=title;$('#evidence-full').src=url;$('#evidence-full').alt=title;$('#evidence-original').href=url;$('#evidence-dialog').showModal();}
function openEvidence(file,title){if(file==='deepseek-session.png')file+='?v=deepseek-stats-2';openImage(`evidence/${file}`,title);}
async function boot(){
 const response=await fetch('data.json',{cache:'no-cache'});if(!response.ok)throw Error('数据暂时无法读取');data=await response.json();
 const catalog=[...(data.showcaseExtras||[]),...data.runs];builds=['minimax','opus','codex','deepseek','hunyuan'].map(id=>catalog.find(r=>r.id===id)).filter(Boolean);
 $('#cards').innerHTML=builds.map((r,i)=>`<article class="work-card ${r.id}"><button class="card-preview" data-screenshot="${r.id}" type="button" aria-label="放大 ${esc(r.name)} 的运行截图"><img src="${esc(r.preview||`previews/${r.id}.png`)}" alt="${esc(r.name+'：'+r.short)}" ${i>1?'loading="lazy"':''}><span class="card-index">0${i+1}</span><span class="card-arrow" aria-hidden="true">↗</span></button><div class="card-meta"><span class="model-name"><span class="model-dot"></span>${esc(r.name)}</span><span class="harness">${esc(r.harness)}</span></div><p class="build-kind">${r.historical?'历史完整版':'同题任务 · 最终成品'}</p><h3>${esc(r.short)}</h3><div class="card-stats"><div><small>${r.historical?'历史版本用时':r.timeIsApproximate?'用户提供用时':'界面任务耗时'}</small><strong class="${r.timeSeconds===null?'missing':''}">${esc(r.timeLabel)}</strong></div><div><small>本次费用 · CNY</small><strong class="${r.costCny===null?'missing':''}">${r.costCny===null?'未提供':esc(r.costLabel||'¥'+r.costCny.toFixed(2))}</strong>${Number.isFinite(r.quotaUsage?.amount)?`<small>界面共消耗 ${esc(r.quotaUsage.displayLabel)}</small>`:''}</div></div><div class="card-actions"><button type="button" data-screenshot="${r.id}" aria-label="查看 ${esc(r.name)} 效果大图">效果大图 ↗</button><button type="button" data-play="${r.id}" aria-label="体验 ${esc(r.name)} 的作品">启动 3D 体验 →</button></div></article>`).join('');
 $('#tabs').innerHTML=builds.map(r=>`<button id="tab-${r.id}" type="button" role="tab" data-id="${r.id}" aria-controls="demo-panel" aria-selected="false" tabindex="-1">${esc(r.name)}${r.historical?' · 原版':''}</button>`).join('');
 const rows=[['工具环境',r=>esc(r.harness)],['模型设置 / 版本标记',r=>esc(r.setting)],['任务耗时',r=>r.timeSeconds===null?unknown:r.timeIsApproximate?`<span class="number">约 ${Math.round(r.timeSeconds/60)}′</span><span class="subcell">${esc(r.timeLabel)} · 用户说明</span>`:`<span class="number">${Math.floor(r.timeSeconds/60)}<span class="subunit">′</span>${String(r.timeSeconds%60).padStart(2,'0')}″</span><span class="subcell">${esc(r.timeLabel)}</span>`],['费用 · CNY',r=>r.costCny===null?unknown:`${r.costBasis==='free_quota'?`<span class="free-quota">${esc(r.costLabel)}</span><span class="subcell">WorkBuddy · 夜间免费</span>`:`<span class="number money">¥${r.costCny.toFixed(2)}</span>`}`],['额度消耗 · 界面',r=>Number.isFinite(r.quotaUsage?.amount)?`<span class="number">${esc(r.quotaUsage.displayLabel)}</span><span class="subcell">WorkBuddy 界面单位</span>`:unknown],['Tokens · 账单合计',r=>r.tokens===null?unknown:`<span class="number">${r.tokens.toLocaleString('en-US')}</span>`],['API 请求次数',r=>r.requests===null?unknown:`<span class="number">${r.requests}</span>`],['界面速率 · tok/s',r=>Number.isFinite(r.interfaceStats?.tokensPerSecond)?`<span class="number">${r.interfaceStats.tokensPerSecond}</span>`:unknown],['缓存命中率 · 界面',r=>Number.isFinite(r.interfaceStats?.cacheHitRatePercent)?`<span class="number">${r.interfaceStats.cacheHitRatePercent}%</span>`:unknown],['3D 实现',r=>esc(r.engine)],['记录依据',r=>r.evidence.length?`<button class="cell-source" data-evidence="${r.evidence[0]}" data-title="${esc(r.name)} · 任务截图" type="button">查看截图 ↗</button>`:`<span class="subcell">${esc(r.recordSourceLabel||'模型名称来自用户说明')}</span>`]];
 $('#metrics').innerHTML=rows.map(([label,render])=>`<tr><th scope="row">${label}</th>${data.runs.map(r=>`<td>${render(r)}</td>`).join('')}</tr>`).join('');
 document.querySelectorAll('[data-play]').forEach(b=>b.addEventListener('click',()=>{select(b.dataset.play,true);$('#playground').scrollIntoView({behavior:matchMedia('(prefers-reduced-motion:reduce)').matches?'instant':'smooth'});}));
 document.querySelectorAll('[data-screenshot]').forEach(b=>b.addEventListener('click',()=>{const run=builds.find(r=>r.id===b.dataset.screenshot);openImage(run.preview||`previews/${run.id}.png`,`${run.name} · 实际运行效果`);}));
 document.querySelectorAll('[role=tab]').forEach(b=>{b.addEventListener('click',()=>select(b.dataset.id,running));b.addEventListener('keydown',event=>{const buttons=[...document.querySelectorAll('[role=tab]')];let i=buttons.indexOf(b);if(event.key==='ArrowRight')i=(i+1)%buttons.length;else if(event.key==='ArrowLeft')i=(i+buttons.length-1)%buttons.length;else if(event.key==='Home')i=0;else if(event.key==='End')i=buttons.length-1;else return;event.preventDefault();buttons[i].focus();select(buttons[i].dataset.id,running);});});
 document.querySelectorAll('[data-evidence]').forEach(b=>b.addEventListener('click',()=>openEvidence(b.dataset.evidence,b.dataset.title)));
 select(active);
}
$('#start-demo').addEventListener('click',start);$('#stop-demo').addEventListener('click',stop);
$('#close-evidence').addEventListener('click',()=>$('#evidence-dialog').close());
$('#evidence-dialog').addEventListener('click',e=>{if(e.target!==e.currentTarget)return;const box=e.currentTarget.getBoundingClientRect();if(e.clientX<box.left||e.clientX>box.right||e.clientY<box.top||e.clientY>box.bottom)e.currentTarget.close();});
$('.copy-prompt').addEventListener('click',async()=>{try{await navigator.clipboard.writeText(data?.prompt||'实现一个鹧鸪骑单车动画效果，需要3d展示，可控制。');toast('提示词已复制');}catch{toast('可选中提示词文字后复制');}});
boot().catch(error=>{$('#cards').textContent=error.message+'，请刷新页面。';$('#viewer-status').textContent='数据加载失败。可通过“独立打开”体验成品。';$('#start-demo').disabled=true;});
