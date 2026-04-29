# ============================================================
# FiixAnalyticsDownloader.ps1
#
# Downloads the daily Fiix Analytics PDF from Gmail via IMAP
# and saves it to a shared network drive. No external modules.
#
# Author: Bennett Hanke
# License: MIT
# ============================================================

# Configuration
$gmailUser     = "your-email@gmail.com"
$gmailAppPass  = "xxxx xxxx xxxx xxxx"           # Gmail App Password — see README
$fiixSender    = "noreply@lookermail.com"

# Settings
$subjectFilter = "Owego WO Shift Turnover"
$savePath      = "Z:\"
$imapServer    = "imap.gmail.com"
$imapPort      = 993
$logFile       = "C:\Scripts\FiixReport.log"

# Logging
function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Tee-Object -FilePath $logFile -Append
}

# Extract PDF from MIME
function Extract-PdfFromMime($emailText) {
    $allLines = $emailText -split "`r?`n"

    $inPdfPart = $false
    $foundHeaders = $false
    $isBase64 = $false
    $b64Collector = New-Object System.Text.StringBuilder

    for ($i = 0; $i -lt $allLines.Count; $i++) {
        $line = $allLines[$i]

        if ($line -match "Content-Type:\s*application/(pdf|octet-stream)" -or
            $line -match 'Content-Disposition:.*filename.*\.pdf') {
            $inPdfPart = $true
            $foundHeaders = $false
            $isBase64 = $false
            $null = $b64Collector.Clear()
            continue
        }

        if ($inPdfPart -and -not $foundHeaders) {
            if ($line -match "Content-Transfer-Encoding:\s*base64") {
                $isBase64 = $true
            }
            if ($line.Trim() -eq "") {
                $foundHeaders = $true
                continue
            }
            continue
        }

        if ($inPdfPart -and $foundHeaders) {
            if ($line -match "^--") { break }
            $trimmed = $line.Trim()
            if ($trimmed -ne "") {
                [void]$b64Collector.Append($trimmed)
            }
        }
    }

    if ($b64Collector.Length -eq 0) { return $null }

    $b64 = $b64Collector.ToString()
    $b64 = $b64 -replace '[^A-Za-z0-9+/=]', ''

    $remainder = $b64.Length % 4
    if ($remainder -ne 0) {
        $b64 += ("=" * (4 - $remainder))
    }

    try {
        $bytes = [Convert]::FromBase64String($b64)
        if ($bytes.Length -gt 4 -and $bytes[0] -eq 0x25 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x44 -and $bytes[3] -eq 0x46) {
            return $bytes
        }
        Write-Log "WARNING: Decoded bytes don't start with PDF header, saving anyway."
        return $bytes
    } catch {
        Write-Log "Base64 decode failed: $_"
        return $null
    }
}

# Main
try {
    Write-Log "Starting Fiix report download..."

    $tcp = New-Object System.Net.Sockets.TcpClient($imapServer, $imapPort)
    $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false)
    $ssl.AuthenticateAsClient($imapServer)

    $reader = New-Object System.IO.StreamReader($ssl)
    $writer = New-Object System.IO.StreamWriter($ssl)
    $writer.AutoFlush = $true

    $null = $reader.ReadLine()

    # Login
    $writer.WriteLine("a1 LOGIN `"$gmailUser`" `"$gmailAppPass`"")
    do { $line = $reader.ReadLine() } while ($line -notmatch "^a1 ")
    if ($line -notmatch "^a1 OK") { throw "Gmail login failed: $line" }
    Write-Log "Logged in to Gmail."

    # Select inbox
    $writer.WriteLine("a2 SELECT INBOX")
    do { $line = $reader.ReadLine() } while ($line -notmatch "^a2 ")

    # Search for today's unread report
    $today = (Get-Date).ToString("dd-MMM-yyyy")
    $writer.WriteLine("a3 SEARCH UNSEEN FROM `"$fiixSender`" SUBJECT `"$subjectFilter`" SINCE $today")
    $searchResult = ""
    do {
        $line = $reader.ReadLine()
        if ($line -match "^\* SEARCH") { $searchResult = $line }
    } while ($line -notmatch "^a3 ")

    if ([string]::IsNullOrWhiteSpace($searchResult) -or $searchResult.Trim() -eq "* SEARCH") {
        Write-Log "No matching unread emails found for $today. Exiting."
        $writer.WriteLine("a9 LOGOUT"); $reader.Close(); $writer.Close(); $ssl.Close(); $tcp.Close()
        exit 0
    }

    $uids = ($searchResult -replace "\* SEARCH ", "").Trim().Split(" ")
    $uid = $uids[-1]
    Write-Log "Found email (msg $uid). Fetching..."

    # Fetch full message
    $writer.WriteLine("a4 FETCH $uid RFC822")
    $rawEmail = New-Object System.Text.StringBuilder
    do {
        $line = $reader.ReadLine()
        if ($line -match "^a4 OK") { break }
        if ($line -match "^\)$") { continue }
        [void]$rawEmail.AppendLine($line)
    } while ($true)

    $emailText = $rawEmail.ToString()
    Write-Log "Email fetched ($(($emailText.Length / 1024).ToString('N0')) KB). Extracting PDF..."

    # Extract PDF
    $pdfBytes = Extract-PdfFromMime $emailText

    if ($null -eq $pdfBytes) {
        Write-Log "WARNING: No PDF attachment could be extracted from the email."
    } else {
        $fileName = "WOTURNOVER_" + (Get-Date).ToString("MM-dd-yyyy") + "_" + (Get-Date).ToString("%h") + (Get-Date).ToString("tt").ToUpper() + ".pdf"
        $filePath = Join-Path $savePath $fileName

        [System.IO.File]::WriteAllBytes($filePath, $pdfBytes)

        Write-Log "Saved: $filePath ($($pdfBytes.Length) bytes)"
    }

    # Mark as read
    $writer.WriteLine("a5 STORE $uid +FLAGS (\Seen)")
    do { $line = $reader.ReadLine() } while ($line -notmatch "^a5 ")

    # Logout
    $writer.WriteLine("a9 LOGOUT")
    $reader.Close(); $writer.Close(); $ssl.Close(); $tcp.Close()
    Write-Log "Done."

} catch {
    Write-Log "ERROR: $_"
}
