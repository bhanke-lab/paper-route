# ============================================================
# Show-PdfKiosk.ps1  (PaperRoute)
#
# Watches a folder and displays the newest PDF fullscreen on
# the primary display via Microsoft Edge kiosk mode. Runs in
# its own isolated Edge profile so it never disturbs anyone's
# normal browsing. Copies the file local first, self-heals if
# the window is closed, and keeps the display awake.
#
# Author: Bennett Hanke
# License: MIT
# ============================================================

# ---- Configuration -----------------------------------------
$watchFolder = "M:\"                  # Folder to watch for new PDFs
$filePattern = "REPORT_*.pdf"         # Which files to show (match Get-EmailPdf's prefix, or use *.pdf)
$localCopy = "C:\Kiosk\current.pdf"   # Local working copy (avoids network read stalls)
$profileDir = "C:\Kiosk\EdgeProfile"  # Dedicated Edge profile keeps the kiosk isolated
$pollSeconds = 30
# ------------------------------------------------------------

# Keep the display awake (process-scoped, no admin)
$sig = @"
[DllImport("kernel32.dll")]
public static extern uint SetThreadExecutionState(uint esFlags);
"@
$power = Add-Type -MemberDefinition $sig -Name Power -Namespace Win32 -PassThru
$power::SetThreadExecutionState([uint32]2147483648 -bor [uint32]1 -bor [uint32]2) | Out-Null

$current = ""

# Only the kiosk's own Edge, identified by its dedicated profile dir
function Get-KioskEdge {
    Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like "*$profileDir*" }
}

function Stop-KioskEdge {
    Get-KioskEdge | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Launch-Edge($srcPath) {
    Stop-KioskEdge
    Start-Sleep -Milliseconds 800
    try { Copy-Item $srcPath $localCopy -Force -ErrorAction Stop } catch { return $false }
    $edgeArgs = @(
        '--kiosk', $localCopy,
        '--edge-kiosk-type=fullscreen',
        "--user-data-dir=$profileDir",
        '--no-first-run', '--no-default-browser-check'
    )
    Start-Process "msedge" -ArgumentList $edgeArgs
    return $true
}

function Tick {
    $newest = Get-ChildItem -Path $watchFolder -Filter $filePattern -ErrorAction SilentlyContinue |
    Where-Object { -not $_.PSIsContainer } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -eq $newest) { return }

    if ($newest.FullName -ne $script:current) {
        if (Launch-Edge $newest.FullName) { $script:current = $newest.FullName }
        return
    }

    # Self-heal: relaunch only if the kiosk's OWN Edge isn't running
    if ($null -eq (Get-KioskEdge)) { Launch-Edge $newest.FullName | Out-Null }
}

Tick
while ($true) {
    Start-Sleep -Seconds $pollSeconds
    try { Tick } catch { }
}