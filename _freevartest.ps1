# 自由变量检查器的反查：恒过的检查等于没有检查。
#
# 主证据：把真源码里那行 `const dt = Math.min(0.05, clock.getDelta());` 删掉 ——
# 那就是 2026-09-30 交付前那个 bug 的原样复现（frame() 拿 dt 当自由变量用，
# 每帧抛 ReferenceError，画面全黑，而当时所有检查全绿）。要求检查器必须 FAIL
# 并且**点名 dt**。点名很关键：只报「有 1 个自由变量」的话，删别的也一样会 FAIL，
# 抓不到真问题也算一种恒过。
$ErrorActionPreference = 'Stop'
$dir = 'E:\minimax_code_project\0929_project\partridge-bike'
$src = Join-Path $dir '_app3d.html'
$chk = Join-Path $dir '_freevar.ps1'
$fail = 0

function Run-Check($p) {
  # ⚠️ 必须临时把 ErrorActionPreference 降下来：检查器报 FAIL 时会往 stderr
  # 写正文，`Stop` + 原生命令 stderr 在 PowerShell 里是 terminating error，
  # 反查自己会当场停住，走不到「看退出码」那一步。
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $chk -Path $p 2>&1
  $code = $LASTEXITCODE
  $ErrorActionPreference = $old
  return @{ code = $code; out = ($o -join "`n") }
}
function Judge($ok, $name, $detail) {
  if ($ok) { Write-Output ("  PASS  {0}" -f $name) }
  else {
    $script:fail++
    Write-Output ("  FAIL  {0}" -f $name)
    if ($detail) { Write-Output ("        " + ($detail -replace "`r?`n", ' | ')) }
  }
}

# ── 1) 真源码：必须 PASS ──
$r = Run-Check $src
Judge ($r.code -eq 0) '真源码：所有标识符都有出处，不该报' ("退出码 $($r.code) " + $r.out)

# ── 2) 坏样本 = 真源码删掉 dt 那一行（就是那个真 bug 的原样复现）──
$txt = [IO.File]::ReadAllText($src)
$mut = Join-Path $dir '_freevar_mutant.html'
$new = [regex]::Replace($txt, '(?m)^\s*const dt = Math\.min\(0\.05, clock\.getDelta\(\)\);\r?\n', '')
if ($new -eq $txt) {
  $fail++
  Write-Output '  FAIL  没找到要删的那行 dt 声明 —— 反查自己失效了（源码改了？）'
} else {
  [IO.File]::WriteAllText($mut, $new, (New-Object Text.UTF8Encoding($false)))
  $r = Run-Check $mut
  Judge (($r.code -eq 1) -and ($r.out -match '(?m)^\s+dt\s')) `
        '坏样本（删掉 dt 声明 = 那个真 bug）：必须 FAIL 而且要点名 dt' `
        ("退出码 $($r.code) " + $r.out)
  mavis-trash $mut
}

# ── 3) 几段小代码：自由变量 / 不该报的写法 ──
$cases = @(
  @{ name = '坏样本：顶层用了没声明的量'
     js   = 'const S={t:0}; function f(){ S.t += dt; } f();'
     want = 1 }
  @{ name = '坏样本：赋值给未声明的全局（严格模式下会炸）'
     js   = "'use strict'; const S={n:0}; function f(){ S.n++; leaked = 3; } f();"
     want = 1 }
  @{ name = '坏样本：for 的初始化漏了 const'
     js   = 'const a=[]; for (i=0;i<3;i++) a.push(i);'
     want = 1 }
  @{ name = '好样本：箭头函数形参（=> 必须合成一个 token 才认得出）'
     js   = 'const approach = (cur, want, k, dt) => cur + (want-cur)*(1-Math.pow(k,dt)); approach(0,1,0.2,0.016);'
     want = 0 }
  @{ name = '好样本：解构声明 const { a, b: c, d = 1, ...rest }'
     js   = 'const src={a:1,b:2,e:9,f:3}; const { a, b: c, d = 1, ...rest } = src; a+c+d+rest.f;'
     want = 0 }
  @{ name = '好样本：catch 形参 / 属性访问 / 对象字面量的键都不算自由变量'
     js   = 'const o={free:1,n:{deep:2}}; try{ JSON.parse("{"); }catch(err){ o.n.deep = err; } o.free;'
     want = 0 }
  @{ name = '好样本：模板字面量 ${} 内部是代码，不是字符串'
     js   = 'const rnd=()=>0.4; const v=3; const c=`rgba(${v},${v*2},${Math.round(255*rnd())},1)`; c.length;'
     want = 0 }
  @{ name = '好样本：类方法与 getter/setter 的形参'
     js   = 'class A{ constructor(n){this.n=n;} get v(){return this.n;} set v(x){this.n=x;} m(a,b){return a+b;} } new A(1).m(1,2);'
     want = 0 }
  @{ name = '好样本：两个 script 块时只取最后一个（前面那个是 THREE 占位）'
     html = "<!DOCTYPE html><html><body><script>/*__THREE__*/</script><script>'use strict';const q=1;q;</script></body></html>"
     want = 0 }
)
$tmp = Join-Path $dir '_freevartest.html'
foreach ($c in $cases) {
  $body = if ($c.html) { $c.html } else { "<!DOCTYPE html><html><head><meta charset=`"utf-8`"></head><body><script>`r`n" + $c.js + "`r`n</script></body></html>" }
  [IO.File]::WriteAllText($tmp, $body, (New-Object Text.UTF8Encoding($false)))
  $r = Run-Check $tmp
  Judge ($r.code -eq $c.want) $c.name ("期望退出码 $($c.want)，实际 $($r.code) " + $r.out)
}
if (Test-Path $tmp) { mavis-trash $tmp }

if ($fail -gt 0) { Write-Output ("freevar 反查 {0} 项不对" -f $fail); exit 1 }
Write-Output 'freevar 反查成立：坏样本抓得住（而且报得出名字），好样本不误伤'
