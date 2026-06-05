<#
trace-index.ps1
Scan .temp/trace/<sid>/ dirs and build index.md -- an overview of all sessions' traces.
Deterministic, ZERO model tokens.

ASCII-only source (PS5.1 decodes BOM-less .ps1 as GBK; non-ASCII breaks parsing).
taskGoal is runtime DATA (read from meta.json / _distilled.md), so Chinese there is fine.

For each session: sid | taskGoal | events | graph? | updated.
taskGoal comes from <sid>/meta.json (written by the aggregation subagent);
sessions without meta fall back to the first USER line in _distilled.md.

Usage:
  trace-index.ps1            # rebuild .temp/trace/index.md
#>
param([string]$TraceRoot = "")
$ErrorActionPreference = "Stop"
if (-not $TraceRoot) {
  $root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
  $TraceRoot = Join-Path $root ".temp\trace"
}
if (-not (Test-Path $TraceRoot)) { throw "trace root not found: $TraceRoot" }

function Cell([string]$s, [int]$n) {
  if ([string]::IsNullOrEmpty($s)) { return "" }
  $s = $s -replace '\s+', ' ' -replace '\|', '/'   # pipe breaks markdown tables
  if ($s.Length -gt $n) { return $s.Substring(0, $n) + "..." }
  return $s
}

$rows = New-Object System.Collections.ArrayList
foreach ($d in (Get-ChildItem $TraceRoot -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
  $sid = $d.Name
  $meta = Join-Path $d.FullName "meta.json"
  $dist = Join-Path $d.FullName "_distilled.md"
  $taskGoal = ""; $lastN = ""
  $updated = $d.LastWriteTime.ToString("yyyy-MM-dd HH:mm")

  if (Test-Path $meta) {
    try { $m = Get-Content $meta -Encoding UTF8 -Raw | ConvertFrom-Json; $taskGoal = "$($m.taskGoal)"; $lastN = "$($m.lastN)" } catch {}
  }
  if (-not $taskGoal -and (Test-Path $dist)) {
    $u = Get-Content $dist -Encoding UTF8 | Where-Object { $_ -match '^#\d+ \[.*\] USER \| ' } | Select-Object -First 1
    if ($u) { $taskGoal = ($u -replace '^#\d+ \[.*\] USER \| ', '') + " [no meta; 1st instruction]" }
  }
  if (-not $lastN -and (Test-Path $dist)) {
    $lastN = "$((Get-Content $dist -Encoding UTF8 | Where-Object { $_ -match '^#\d+ ' } | Measure-Object).Count)"
  }
  $hasGraph = if (Test-Path (Join-Path $d.FullName "task-graph.mmd")) { "Y" } else { "-" }
  [void]$rows.Add([pscustomobject]@{ sid = $sid; taskGoal = (Cell $taskGoal 70); events = $lastN; graph = $hasGraph; updated = $updated })
}

$md = New-Object System.Collections.ArrayList
[void]$md.Add("# Trace Session Index")
[void]$md.Add("")
[void]$md.Add("> open a session's task-graph.mmd for the map; or drill:  sn <eventNo> -SessionId <sid>")
[void]$md.Add("")
[void]$md.Add("| sid | taskGoal | events | graph | updated |")
[void]$md.Add("|-----|----------|-------|-------|---------|")
foreach ($r in $rows) {
  [void]$md.Add("| $($r.sid) | $($r.taskGoal) | $($r.events) | $($r.graph) | $($r.updated) |")
}
$out = Join-Path $TraceRoot "index.md"
[System.IO.File]::WriteAllText($out, ($md -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Output "index written: $out ($($rows.Count) sessions)"
