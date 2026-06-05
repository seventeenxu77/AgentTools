<#
trace-append.ps1
Append an incremental segment to an existing task graph WITHOUT rewriting the old graph,
so incremental aggregation only pays for the new segment (not re-copying the whole graph).

ASCII-only source (PS5.1 GBK pitfall). Reads/writes UTF8. Chinese in data is fine.

Input: <Dir>\_newseg.md produced by the subagent, with 3 marker-separated blocks:
  ===MMD===      new mermaid nodes/edges only (no flowchart/classDef header)
  ===TABLE===    new node-table rows (markdown rows, no header)
  ===DEADEND===  new dead-end items (or the literal: (none))

Actions:
  - append MMD block to <Dir>\task-graph.mmd
  - <Dir>\task-graph.md: sync the ###1 mermaid block from the updated .mmd,
    insert TABLE rows before "### 3", append DEADEND items at the end
  - update <Dir>\meta.json lastN (keep existing taskGoal)
  - delete _newseg.md

Usage:
  trace-append.ps1 -Dir <sid dir> -LastN <N>
#>
param(
  [Parameter(Mandatory=$true)][string]$Dir,
  [Parameter(Mandatory=$true)][int]$LastN
)
$ErrorActionPreference = "Stop"

$segPath  = Join-Path $Dir "_newseg.md"
$mmdPath  = Join-Path $Dir "task-graph.mmd"
$mdPath   = Join-Path $Dir "task-graph.md"
$metaPath = Join-Path $Dir "meta.json"
foreach ($p in @($segPath, $mmdPath, $mdPath)) { if (-not (Test-Path $p)) { throw "missing: $p" } }

function Block([string]$text, [string]$start, [string]$end) {
  $a = $text.IndexOf($start); if ($a -lt 0) { return "" }
  $a += $start.Length
  $b = if ($end) { $text.IndexOf($end, $a) } else { -1 }
  if ($b -lt 0) { $b = $text.Length }
  return $text.Substring($a, $b - $a).Trim()
}

# 1. parse the new segment
$seg = [System.IO.File]::ReadAllText($segPath)
$mmdSeg     = Block $seg "===MMD===" "===TABLE==="
$tableSeg   = Block $seg "===TABLE===" "===DEADEND==="
$deadendSeg = Block $seg "===DEADEND===" ""
if (-not $mmdSeg) { throw "no ===MMD=== block in _newseg.md" }

# 2. append MMD to .mmd (node/edge order does not matter in mermaid)
$mmd = ([System.IO.File]::ReadAllText($mmdPath)).TrimEnd()
$mmd = $mmd + "`r`n`r`n" + $mmdSeg + "`r`n"
[System.IO.File]::WriteAllText($mmdPath, $mmd, (New-Object System.Text.UTF8Encoding($false)))

# 3. update .md
$md = [System.IO.File]::ReadAllText($mdPath)

# 3a. sync ###1 mermaid block from the updated .mmd
$ms = $md.IndexOf('```mermaid')
if ($ms -ge 0) {
  $cs = $md.IndexOf("`n", $ms)
  if ($cs -ge 0) {
    $cs += 1
    $me = $md.IndexOf('```', $cs)
    if ($me -gt $cs) {
      $md = $md.Substring(0, $cs) + $mmd.TrimEnd() + "`r`n" + $md.Substring($me)
    }
  }
}

# 3b. insert new table rows before "### 3"
if ($tableSeg) {
  $i3 = $md.IndexOf('### 3')
  if ($i3 -ge 0) { $md = $md.Insert($i3, $tableSeg + "`r`n`r`n") }
  else { $md = $md.TrimEnd() + "`r`n" + $tableSeg + "`r`n" }
}

# 3c. append dead-end items at the end
if ($deadendSeg -and $deadendSeg -ne "(none)") {
  $md = $md.TrimEnd() + "`r`n" + $deadendSeg + "`r`n"
}
[System.IO.File]::WriteAllText($mdPath, $md, (New-Object System.Text.UTF8Encoding($false)))

# 4. update meta.json lastN, keep old taskGoal (hand-build JSON to keep Chinese readable)
$taskGoal = ""
if (Test-Path $metaPath) { try { $mm = Get-Content $metaPath -Encoding UTF8 -Raw | ConvertFrom-Json; $taskGoal = "$($mm.taskGoal)" } catch {} }
$tg = $taskGoal -replace '\\', '\\\\' -replace '"', '\"'
$newMeta = '{"taskGoal":"' + $tg + '","lastN":' + $LastN + '}'
[System.IO.File]::WriteAllText($metaPath, $newMeta, (New-Object System.Text.UTF8Encoding($false)))

# 5. cleanup
Remove-Item $segPath -Force -ErrorAction SilentlyContinue
Write-Output "appended new segment; meta.lastN=$LastN"
