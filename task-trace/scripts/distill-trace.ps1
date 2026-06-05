<#
distill-trace.ps1
Distill a Claude Code session transcript (jsonl) into a compact tool-call list,
to be aggregated into a task graph by a subagent. Deterministic, ZERO model tokens.

Output is namespaced per session:  <project>/.temp/trace/<sid>/_distilled.md
Also reads the existing <sid>/meta.json to report prevLastN, so the caller can
decide: reuse (no growth) / incremental (-Since prevLastN) / full.

ASCII-only source (PS5.1 decodes BOM-less .ps1 as GBK). Reads jsonl with -Encoding UTF8.

Usage:
  distill-trace.ps1 -SessionId a396b413            # full list -> _distilled.md
  distill-trace.ps1 -SessionId a396b413 -Since 100 # only events after #100 -> _increment.md
#>
param(
  [string]$SessionId = "",
  [string]$OutFile = "",
  [int]$Since = 0
)
$ErrorActionPreference = "Stop"

# 1. Locate transcript jsonl (exclude subagent transcripts: agent-*.jsonl)
$projects = Join-Path $env:USERPROFILE ".claude\projects"
if (-not (Test-Path $projects)) { throw "projects dir not found: $projects" }

$jsonl = $null
if ($SessionId) {
  $jsonl = Get-ChildItem -Path $projects -Recurse -Filter "$SessionId*.jsonl" -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -notlike 'agent-*' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
if (-not $jsonl) {
  $jsonl = Get-ChildItem -Path $projects -Recurse -Filter "*.jsonl" -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -notlike 'agent-*' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
if (-not $jsonl) { throw "no transcript jsonl found under: $projects" }
$f = $jsonl.FullName

# 2. Session id for output namespacing (first 8 chars of jsonl uuid)
$sid = [System.IO.Path]::GetFileNameWithoutExtension($f)
if ($sid.Length -gt 8) { $sid = $sid.Substring(0, 8) }

# 3. Output path (full -> _distilled.md, incremental -> _increment.md)
if (-not $OutFile) {
  $root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path
  $name = if ($Since -gt 0) { "_increment.md" } else { "_distilled.md" }
  $OutFile = Join-Path $root ".temp\trace\$sid\$name"
}
$dir = Split-Path $OutFile
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

# 3b. Read previous lastN from meta.json (for the caller's incremental decision)
$prevLastN = 0
$metaPath = Join-Path $dir "meta.json"
if (Test-Path $metaPath) {
  try { $mm = Get-Content $metaPath -Encoding UTF8 -Raw | ConvertFrom-Json; if ($mm.lastN) { $prevLastN = [int]$mm.lastN } } catch {}
}

# 4. Parse (MUST use -Encoding UTF8)
$objs = Get-Content $f -Encoding UTF8 | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} } | Where-Object { $_ }

function Short([string]$s, [int]$n) {
  if ([string]::IsNullOrEmpty($s)) { return "" }
  $s = $s -replace '\s+', ' '
  if ($s.Length -gt $n) { return $s.Substring(0, $n) + "..." }
  return $s
}
function InSum($tu) {
  $in = $tu.input
  switch ($tu.name) {
    'Bash'        { return (Short $in.command 75) }
    'PowerShell'  { return (Short $in.command 75) }
    'Read'        { return "$($in.file_path)" }
    'Edit'        { return "$($in.file_path)" }
    'Write'       { return "$($in.file_path)" }
    'Skill'       { return "$($in.skill) | $(Short $in.args 35)" }
    'WebFetch'    { return "$($in.url)" }
    'ToolSearch'  { return (Short $in.query 50) }
    'Agent'       { return (Short $in.description 45) }
    'Grep'        { return (Short $in.pattern 40) }
    'Glob'        { return (Short $in.pattern 40) }
    'Task'        { return (Short $in.description 45) }
    default       { return (Short ($in | ConvertTo-Json -Compress -Depth 3) 70) }
  }
}

# Map tool_use_id -> success
$resultMap = @{}
foreach ($o in $objs) {
  if ($o.type -eq 'user' -and $o.message.content) {
    foreach ($c in $o.message.content) {
      if ($c.type -eq 'tool_result') {
        $err = $false
        if ($c.PSObject.Properties.Name -contains 'is_error') { $err = [bool]$c.is_error }
        $resultMap[$c.tool_use_id] = -not $err
      }
    }
  }
}

$lines = New-Object System.Collections.ArrayList
$title = if ($Since -gt 0) { "# Trace increment (events after #$Since)" } else { "# Trace distilled tool-call list" }
[void]$lines.Add($title)
[void]$lines.Add("source transcript: $f")
[void]$lines.Add("")
$i = 0
foreach ($o in $objs) {
  $ts = ""
  if ($o.timestamp) { try { $ts = ([datetime]$o.timestamp).ToString("MM-dd HH:mm") } catch {} }
  if ($o.type -eq 'user') {
    $content = $o.message.content
    $isTR = $false
    if ($content -is [array]) { foreach ($c in $content) { if ($c.type -eq 'tool_result') { $isTR = $true } } }
    if (-not $isTR) {
      if ($o.isMeta) { continue }
      $txt = $content
      if ($txt -is [array]) { $txt = ($txt | ForEach-Object { $_.text }) -join ' ' }
      if ("$txt" -match '^\s*<command-name>|^\s*<local-command') { continue }
      $i++; if ($i -gt $Since) { [void]$lines.Add("#$i [$ts] USER | $(Short $txt 150)") }
    }
  }
  elseif ($o.type -eq 'assistant' -and $o.message.content) {
    foreach ($c in $o.message.content) {
      if ($c.type -eq 'text' -and $c.text.Trim()) {
        $i++; if ($i -gt $Since) { [void]$lines.Add("#$i [$ts] AI   | $(Short $c.text 120)") }
      }
      elseif ($c.type -eq 'tool_use') {
        $ok = "?"
        if ($resultMap.ContainsKey($c.id)) { $ok = if ($resultMap[$c.id]) { "ok" } else { "ERR" } }
        $idShort = if ($c.id.Length -ge 14) { $c.id.Substring(0, 14) } else { $c.id }
        $i++; if ($i -gt $Since) { [void]$lines.Add("#$i [$ts] TOOL $($c.name)( $(InSum $c) ) [$ok] id=$idShort") }
      }
    }
  }
}
[System.IO.File]::WriteAllText($OutFile, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Output "OK jsonl=$f"
Write-Output "sid=$sid events=$i prevLastN=$prevLastN"
Write-Output "out=$OutFile"
Write-Output "dir=$dir"
