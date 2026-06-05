<#
sn.ps1  (show-node) -- drill down a trace node.
Given an event number (e.g. 22) or a tool_use_id prefix, print the FULL original
record (tool name + complete input + complete result) from the session jsonl.

KEY: the jsonl is taken from _distilled.md's "source transcript:" line, so the
anchor (#N) and the id lookup always use the SAME jsonl. Otherwise, when a session
is resumed (a new transcript file becomes "newest"), a bare fallback would pick the
wrong jsonl and the id would not be found.

ASCII-only source (PS5.1 decodes BOM-less .ps1 as GBK). Reads with -Encoding UTF8.

Usage:
  sn.ps1 22            # bare event number (recommended)
  sn.ps1 "#22"         # with hash (needs quotes - # is a comment char)
  sn.ps1 toluXXXX      # tool_use_id prefix
  sn.ps1 22 -MaxChars 9000
#>
param(
  [Parameter(Position=0, Mandatory=$true)][string]$Id,
  [string]$SessionId = "",
  [string]$Distilled = "",
  [int]$MaxChars = 6000
)
$ErrorActionPreference = "Stop"
# bare number -> event anchor (#N)
if ($Id -match '^\d+$') { $Id = "#$Id" }

# distilled list path: per-session <sid> dir under .temp/trace (project root via script location)
if (-not $Distilled) {
  $root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
  $traceRoot = Join-Path $root ".temp\trace"
  if ($SessionId) { $Distilled = Join-Path $traceRoot "$SessionId\_distilled.md" }
  else {
    $cand = Get-ChildItem $traceRoot -Recurse -Filter "_distilled.md" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($cand) { $Distilled = $cand.FullName } else { $Distilled = Join-Path $traceRoot "_distilled.md" }
  }
}

# jsonl: PREFER the source recorded in _distilled.md (keeps anchor & id lookup consistent)
$f = $null
if (Test-Path $Distilled) {
  foreach ($l in (Get-Content $Distilled -Encoding UTF8 -TotalCount 3)) {
    if ($l -match '^source transcript:\s*(.+?)\s*$') { $cand = $matches[1]; if (Test-Path $cand) { $f = $cand }; break }
  }
}
# fallback: by -SessionId, else newest jsonl
if (-not $f) {
  $projects = Join-Path $env:USERPROFILE ".claude\projects"
  $j = $null
  if ($SessionId) { $j = Get-ChildItem $projects -Recurse -Filter "$SessionId*.jsonl" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }
  if (-not $j) { $j = Get-ChildItem $projects -Recurse -Filter "*.jsonl" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }
  if (-not $j) { throw "no transcript jsonl found (and no source in $Distilled)" }
  $f = $j.FullName
}

# resolve anchor #N -> tool id prefix (via _distilled.md)
$tid = $Id
if ($Id.StartsWith("#")) {
  if (-not (Test-Path $Distilled)) { throw "distilled list not found: $Distilled (run /trace first)" }
  $line = Get-Content $Distilled -Encoding UTF8 | Where-Object { $_ -match "^$([regex]::Escape($Id))\s" } | Select-Object -First 1
  if (-not $line) { throw "anchor $Id not found in distilled list" }
  Write-Output "[anchor] $line"
  Write-Output ""
  $mm = [regex]::Match($line, 'id=([A-Za-z0-9_]+)')
  if ($mm.Success) { $tid = $mm.Groups[1].Value }
  else { Write-Output "(USER/AI text event - no tool record; the line above is the summary)"; return }
}

$objs = Get-Content $f -Encoding UTF8 | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} } | Where-Object { $_ }

function Clip([string]$s, [int]$n) {
  if ([string]::IsNullOrEmpty($s)) { return "" }
  if ($s.Length -gt $n) { return $s.Substring(0, $n) + "`n...[+$($s.Length - $n) more chars]" }
  return $s
}

$hit = $false
foreach ($o in $objs) {
  if ($o.type -eq 'assistant' -and $o.message.content) {
    foreach ($c in $o.message.content) {
      if ($c.type -eq 'tool_use' -and $c.id -and $c.id.StartsWith($tid)) {
        $hit = $true
        Write-Output "=== TOOL CALL ==="
        Write-Output "name: $($c.name)"
        Write-Output "id  : $($c.id)"
        Write-Output "time: $($o.timestamp)"
        Write-Output "--- input ---"
        Write-Output (Clip ($c.input | ConvertTo-Json -Depth 8) $MaxChars)
      }
    }
  }
  if ($o.type -eq 'user' -and $o.message.content) {
    foreach ($c in $o.message.content) {
      if ($c.type -eq 'tool_result' -and $c.tool_use_id -and $c.tool_use_id.StartsWith($tid)) {
        $rc = $c.content
        if ($rc -is [array]) { $rc = ($rc | ForEach-Object { if ($_.text) { $_.text } else { ($_ | ConvertTo-Json -Compress) } }) -join "`n" }
        Write-Output "--- result ---"
        Write-Output (Clip "$rc" $MaxChars)
      }
    }
  }
}
if (-not $hit) { Write-Output "no tool_use with id prefix '$tid' found in jsonl ($f)" }
