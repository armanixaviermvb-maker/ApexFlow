# Compile an MQL5 file with MetaEditor from the command line and report errors/warnings.
# Usage:
#   .\scripts\compile.ps1 -MetaEditor "C:\Program Files\<MT5 folder>\metaeditor64.exe" `
#                         -Source "<DataFolder>\MQL5\Experts\ApexFlow\ApexFlow.mq5"
# Exit code: 0 on zero errors, 1 otherwise.
param(
    [string]$MetaEditor = "",
    [Parameter(Mandatory = $true)][string]$Source,
    [string]$IncludeDir = ""   # optional: <DataFolder>\MQL5 when compiling outside a data folder
)

if (-not $MetaEditor) {
    $found = Get-ChildItem "C:\Program Files\*\metaeditor64.exe", "C:\Program Files (x86)\*\metaeditor64.exe" `
        -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $found) { Write-Error "metaeditor64.exe not found; pass -MetaEditor"; exit 1 }
    $MetaEditor = $found.FullName
}
if (-not (Test-Path $Source)) { Write-Error "Source not found: $Source"; exit 1 }

$log = [System.IO.Path]::ChangeExtension((Resolve-Path $Source).Path, ".compile.log")
$meArgs = @("/compile:`"$((Resolve-Path $Source).Path)`"", "/log:`"$log`"")
if ($IncludeDir) { $meArgs += "/inc:`"$IncludeDir`"" }

Start-Process -FilePath $MetaEditor -ArgumentList $meArgs -Wait -NoNewWindow | Out-Null

if (-not (Test-Path $log)) { Write-Error "No compile log produced: $log"; exit 1 }
# MetaEditor writes the log as UTF-16LE.
$text = Get-Content $log -Encoding Unicode
$text | Where-Object { $_ -match "error|warning" } | ForEach-Object { Write-Output $_ }

$result = $text | Where-Object { $_ -match "Result:" } | Select-Object -Last 1
Write-Output $result
if ($result -match "Result:\s*0 error") { exit 0 } else { exit 1 }
