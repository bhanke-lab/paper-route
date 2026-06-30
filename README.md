# PaperRoute

PaperRoute is a dependency-free PowerShell toolkit that automatically pulls scheduled PDF reports out of an email inbox and shows the latest one fullscreen on any screen. No browser automation, no external modules, nothing beyond PowerShell 5.1+.

It is two small scripts you can use together or on their own:

- **`Get-EmailPdf.ps1`** finds the latest scheduled report in a Gmail inbox over raw IMAP/TLS, extracts the PDF, and saves it to a folder.
- **`Show-PdfKiosk.ps1`** watches that folder and displays the newest PDF fullscreen on a screen via Microsoft Edge kiosk mode.

## Why This Exists

PaperRoute was originally built to put multi-period Fiix Analytics (Google Looker BI) shift-turnover reports on a maintenance-bay TV: a scheduled Looker email each morning, auto-saved to a shared drive, auto-displayed fullscreen on a wall-mounted screen. There is no built-in way to get a scheduled BI email onto a folder or a screen without a person in the loop, so this closes that gap.

None of it is Fiix-specific. Any recurring email-to-PDF delivery works the same way:

- BI dashboards from Looker, Power BI, Tableau, or Metabase, emailed as PDF
- Nightly status, sales, or operations reports
- Monitoring, safety, or compliance exports
- Invoices, statements, or any recurring PDF that lands in an inbox

Use the downloader alone if you just want files on a drive for easy and stable reference. Add the kiosk script when you want them on a screen for real-time reporting.

## How It Works

**Downloader (`Get-EmailPdf.ps1`)**

1. Your reporting tool emails a scheduled PDF
2. PowerShell connects to Gmail over IMAP/TLS
3. Searches for today's unread report by sender and subject
4. Parses the MIME body, decodes base64, extracts the PDF
5. Saves it to your target folder with a date-stamped filename
6. Marks the email as read

**Kiosk (`Show-PdfKiosk.ps1`)**

1. Watches the target folder for the newest matching PDF
2. Copies it to a local working file, which avoids network read stalls over SMB
3. Opens it fullscreen in an isolated Edge kiosk profile on the primary display
4. Swaps automatically when a newer file arrives, and relaunches itself if the window is closed

The downloader talks IMAP through raw `System.Net.Sockets.TcpClient` and `SslStream`. No third-party modules, no COM objects, no `Invoke-WebRequest`.

## Requirements

- Windows with PowerShell 5.1 or newer
- A Gmail account with an [App Password](https://myaccount.google.com/apppasswords) (requires 2-Step Verification)
- A scheduled email delivery that sends your report as a PDF
- A target folder (local path, mapped drive, or UNC path)
- Microsoft Edge for the kiosk script (preinstalled on Windows 10 and 11)

## Quick Start

### 1. Generate a Gmail App Password

1. Go to [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)
2. If the option is missing, enable 2-Step Verification first
3. Create a new app password (name it anything, for example `PaperRoute`)
4. Copy the 16-character password

### 2. Schedule the email delivery

In your reporting tool, schedule a recurring delivery to your Gmail address with format PDF. Note the exact sender address and subject line; PaperRoute matches on both.

### 3. Configure the downloader

Open `Get-EmailPdf.ps1` and edit the configuration block:

```powershell
$gmailUser     = "your-email@gmail.com"
$gmailAppPass  = "xxxx xxxx xxxx xxxx"     # App Password from step 1
$fromAddress   = "reports@example.com"     # e.g. noreply@lookermail.com for Looker / Fiix Analytics
$subjectFilter = "Your Report Name"        # Must match the email subject
$savePath      = "Z:"                     # Local path, mapped drive, or UNC
$filePrefix    = "REPORT"                  # Saved filename prefix
$logFile       = "C:ScriptsPaperRoute.log"
```

> Security note: the app password is stored in plaintext in the script. Keep it in a secured directory and never commit real credentials.

### 4. Test it

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:ScriptsGet-EmailPdf.ps1"
```

Check the log:

```text
2026-04-29 07:15:03  Starting report download...
2026-04-29 07:15:04  Logged in to Gmail.
2026-04-29 07:15:06  Found email (msg 12345). Fetching...
2026-04-29 07:15:08  Email fetched (245 KB). Extracting PDF...
2026-04-29 07:15:08  Saved: Z:REPORT_04-29-2026_7AM.pdf (198432 bytes)
2026-04-29 07:15:09  Done.
```

### 5. Schedule it (Task Scheduler)

1. Task Scheduler, Create Basic Task
2. Name: `PaperRoute Download`
3. Trigger: daily, about 15 minutes after the email is sent
4. Action: Start a program
   - Program: `powershell.exe`
   - Arguments: `-ExecutionPolicy Bypass -File "C:\Scripts\Get-EmailPdf.ps1"`
5. In Properties, Triggers, edit the trigger:
   - Repeat every 10 minutes for 1 hour
   - Run task as soon as possible after a scheduled start is missed
6. Under General, select Run only when user is logged on

The retry window catches the email even if it lands a few minutes late.

### 6. Display it on a screen (optional)

Open `Show-PdfKiosk.ps1` and set the configuration block:

```powershell
$watchFolder = "M:"                  # Folder the downloader writes to
$filePattern = "REPORT_.pdf"         # Match the downloader prefix, or use .pdf
$localCopy   = "C:Kioskcurrent.pdf"
$profileDir  = "C:KioskEdgeProfile"
$pollSeconds = 30
```

Set the screen you want as the Windows primary display so the kiosk lands on it, then run:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:KioskShow-PdfKiosk.ps1"
```

To start it automatically on login, put a hidden shortcut in `shell:startup` pointing to:

```powershell
powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:KioskShow-PdfKiosk.ps1"
```

The kiosk runs in its own Edge profile, so it never touches anyone else's browsing tabs on the same machine.

This was originally built with SumatraPDF, but was rolled back to Edge. This is due to Sumatra not being DPI-aware, and
this project aiming to fit pdfs on high-dpi portait or landscape displays when needed (TVs). This project's framework can
be easily reworked back into Sumatra.

## Output

Files are saved as `PREFIX_MM-DD-YYYY_7AM.pdf`. The prefix, date format, and time label are set in the `$fileName` line of the downloader.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `No matching unread emails found` | Email has not arrived yet, or was already read | Check the inbox, mark the email unread, re-run |
| `Gmail login failed` | App password wrong or revoked | Regenerate at myaccount.google.com/apppasswords |
| `No PDF attachment could be extracted` | Your reporting tool changed the email MIME format | Check the log, open the raw email source to inspect |
| Script does not run on schedule | User not logged in, or task misconfigured | Right-click the task, Run, to test manually |
| Target folder not accessible | Network drive disconnected or permissions changed | Verify the mapping, or try a local path |
| Kiosk opens on the wrong screen | Target screen is not the Windows primary display | Set it as primary in Display settings |
| Kiosk PDF looks blurry or hangs | Reading the PDF straight off a network share | Already handled: the script copies local first |

## Adapting It

- **Multiple reports:** copy `Get-EmailPdf.ps1`, give each a different `$subjectFilter` and `$filePrefix`, and add a separate scheduled task.
- **A different mailbox provider:** change `$imapServer` and `$imapPort`. Any IMAP host works; the defaults are Gmail.
- **A different viewer:** the kiosk uses Edge because it is DPI-aware and on every Windows box, but any PDF viewer with a fullscreen command-line flag can be swapped into `Launch-Edge`.

## How It Works (Technical)

- Opens a raw TCP socket to `imap.gmail.com:993` over TLS
- Authenticates with `LOGIN` and the app password
- Runs `SEARCH UNSEEN FROM "..." SUBJECT "..." SINCE <today>`
- Fetches the message with `FETCH <uid> RFC822`
- Walks the MIME structure for `Content-Type: application/pdf` or a `.pdf` filename in `Content-Disposition`
- Collects, cleans, pads, and base64-decodes the body
- Validates the output starts with `%PDF` (hex `25 50 44 46`)
- Writes the bytes to disk and flags the email `\Seen`

## Teardown

1. Delete the Task Scheduler job and the kiosk startup shortcut
2. Delete the scripts and the log file
3. Revoke the Gmail app password at [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)
4. Remove the scheduled email delivery

## License

MIT
