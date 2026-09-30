param([string]$Target, [int]$From, [int]$To, [string]$New)
# 按 1 基行号把 $Target 的 [$From..$To] 整段换成 $New 的内容。
# 保留原文件的 BOM 状态和行尾。插完立刻报结构，方便当场验。
$ErrorActionPreference = 'Stop'

$bytes = [IO.File]::ReadAllBytes($Target)
$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
$text  = [IO.File]::ReadAllText($Target)
if ($hasBom) { $text = $text.Substring(1) }
$crlf = $text.Contains("`r`n")
$nl = if ($crlf) { "`r`n" } else { "`n" }
$lines = $text -split "`r`n|`n"

if ($From -lt 1 -or $To -gt $lines.Count -or $From -gt $To) { throw "bad range $From..$To (file has $($lines.Count) lines)" }
Write-Output ("replacing {0}..{1}" -f $From, $To)
Write-Output ("  first: [{0}]" -f $lines[$From-1].Trim())
Write-Output ("  last : [{0}]" -f $lines[$To-1].Trim())
Write-Output ("  prev : [{0}]" -f $(if($From -ge 2){$lines[$From-2].Trim()}else{'<BOF>'}))
Write-Output ("  next : [{0}]" -f $(if($To -lt $lines.Count){$lines[$To].Trim()}else{'<EOF>'}))

$nb = [IO.File]::ReadAllBytes($New)
$nt = [IO.File]::ReadAllText($New)
if ($nt.Length -gt 0 -and $nt[0] -eq [char]0xFEFF) { $nt = $nt.Substring(1) }
# 去掉尾部多余空行，只留内容本身
$nl2 = $nt -split "`r`n|`n"
while ($nl2.Count -gt 1 -and $nl2[$nl2.Count-1].Trim() -eq '' -and $nl2[$nl2.Count-2].Trim() -eq '') { $nl2 = $nl2[0..($nl2.Count-2)] }

$out = @()
if ($From -ge 2) { $out += $lines[0..($From-2)] }
$out += $nl2
if ($To -lt $lines.Count) { $out += $lines[$To..($lines.Count-1)] }

$enc = New-Object Text.UTF8Encoding($hasBom)
[IO.File]::WriteAllText($Target, ($out -join $nl), $enc)

$after = [IO.File]::ReadAllText($Target) -split "`r`n|`n"
"written: {0} lines (was {1})" -f $after.Count, $lines.Count
"  now first: [{0}]" -f $after[$From-1].Trim()
"  now last : [{0}]" -f $after[$From + $nl2.Count - 1].Trim()
