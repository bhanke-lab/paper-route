# fiix-analytics-auto-downloader

A lightweight PowerShell script that automatically downloads scheduled Fiix Analytics (Looker) PDF reports from email and saves them to a local or shared drive. No browser interaction, no external modules, no dependencies beyond PowerShell 5.1+.

## Why This Exists

Fiix Analytics (powered by Google Looker) can schedule deliveries via email, but there's no built-in way to automatically save those PDFs to a shared folder where your team can access them. This script closes that gap.

It was built for a maintenance team that needed daily shift turnover reports available on a shared drive every morning, for end use with a auto presentation script.

## How It Works

1. Fiix Analytics sends a scheduled PDF report via email (Looker)
2. PowerShell connects to Gmail via IMAP/TLS
3. Searches for today's unread report by sender + subject
4. Parses MIME, decodes base64, extracts the PDF attachment
5. Saves to a target folder with a date-stamped filename
6. Marks the email as read

The script uses raw `System.Net.Sockets.TcpClient` and `SslStream` for IMAP — no third-party modules required.

## Requirements

- Windows with PowerShell 5.1+
- A Gmail account with [App Password](https://myaccount.google.com/apppasswords) enabled (requires 2-Step Verification)
- A Fiix Analytics scheduled delivery configured to email a PDF report
- A target folder (local path, mapped drive, or UNC path)

## Quick Start

### 1. Generate a Gmail App Password

1. Go to [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)
2. If the option doesn't appear, enable 2-Step Verification first
3. Create a new app password (name it anything — e.g., `Fiix Report Script`)
4. Copy the 16-character password

### 2. Configure the Fiix Scheduled Delivery

1. In Fiix, open the Analytics report you want to deliver
2. Click **Schedule Delivery**
3. Set:
   - **Recurrence:** your desired schedule (e.g., M–F)
   - **Time:** when you want the email sent (e.g., `07:00`)
   - **Destination:** Email
   - **Send to:** your Gmail address
   - **Format:** PDF
4. Save

### 3. Configure the Script

Open `FiixAnalyticsDownloader.ps1` and edit the configuration block at the top:
$gmailUser     = "your-email@gmail.com"
$gmailAppPass  = "xxxx xxxx xxxx xxxx"    # App Password from step 1
$fiixSender    = "noreply@lookermail.com"
$subjectFilter = "Your Report Name"       # Must match the email subject
$savePath      = "Z:"
$logFile       = "C:ScriptsFiixReport.log"


> **Security note:** The app password is stored in plaintext in the script. Keep the script in a secured directory with appropriate file permissions. Do not commit credentials to version control.

### 4. Test It

Run the script manually first to confirm it works: powershell.exe -ExecutionPolicy Bypass -File "C:ScriptsFiixAnalyticsDownloader.ps1"

Check the log file for output. You should see something like:
2026-04-29 07:15:03  Starting Fiix report download...
2026-04-29 07:15:04  Logged in to Gmail.
2026-04-29 07:15:06  Found email (msg 12345). Fetching...
2026-04-29 07:15:08  Email fetched (245 KB). Extracting PDF...
2026-04-29 07:15:08  Saved: Z:WOTURNOVER_04-29-2026_7AM.pdf (198432 bytes)
2026-04-29 07:15:09  Done.

### 5. Schedule with Task Scheduler

1. Open **Task Scheduler** → **Create Basic Task**
2. **Name:** `Fiix Analytics Download`
3. **Trigger:** Daily at a time ~15 minutes after the Fiix delivery (e.g., `07:15`)
4. **Action:** Start a program
   - **Program:** `powershell.exe`
   - **Arguments:** `-ExecutionPolicy Bypass -File "C:\Scripts\FiixAnalyticsDownloader.ps1"`
5. In **Properties → Triggers**, edit the trigger:
   - Check **Repeat task every 10 minutes** for a duration of **1 hour**
   - Check **Run task as soon as possible after a scheduled start is missed**
6. Under **General**, select **Run only when user is logged on**

The retry ensures the script picks up the email even if it arrives a few minutes late.

## Output

Files are saved with the naming convention: `WOTURNOVER_MM-DD-YYYY_7AM.pdf`

The prefix, date format, and time label are configurable in the script's `$fileName` line.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `No matching unread emails found` | Email hasn't arrived yet, or was already marked as read | Check Gmail inbox. Mark the email as unread and re-run. |
| `Gmail login failed` | App password is incorrect or revoked | Regenerate at myaccount.google.com/apppasswords |
| `No PDF attachment could be extracted` | Looker changed the email MIME format | Check the log. Open the raw email source in Gmail to inspect. |
| Script doesn't run on schedule | Windows user not logged in, or task misconfigured | Right-click the Task Scheduler job → **Run** to test manually. |
| Target folder not accessible | Network drive disconnected or permissions changed | Verify the drive is mapped. Try a local path as a fallback. |
| `Decoded bytes don't start with PDF header` | Decoded successfully but may not be a PDF | Script saves it anyway. Check the output file. |

## Adapting for Your Site

This script is not specific to any one report. To use it for a different Fiix Analytics delivery:

1. Set up a new scheduled delivery in Fiix Analytics for your report
2. Update `$subjectFilter` to match the email subject line
3. Update `$savePath` and `$fileName` format as needed
4. To download multiple reports, duplicate the script with different configurations and create a separate Task Scheduler job for each

## How It Works (Technical)

- Opens a raw TCP socket to `imap.gmail.com:993` over TLS
- Authenticates with `LOGIN` using the app password
- Runs `SEARCH UNSEEN FROM "..." SUBJECT "..." SINCE <today>` to find the email
- Fetches the full message with `FETCH <uid> RFC822`
- Walks the MIME structure looking for `Content-Type: application/pdf` or a `.pdf` filename in `Content-Disposition`
- Collects the base64 body, cleans it, pads it, decodes it
- Validates the output starts with `%PDF` (hex `25 50 44 46`) as a sanity check
- Writes the bytes to disk and marks the email as `\Seen`

No external modules. No COM objects. No `Invoke-WebRequest`. Just sockets and string parsing.

## Teardown

To remove completely:

1. Delete the Task Scheduler job
2. Delete the script and log file
3. Revoke the Gmail app password at [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)
4. Remove the Fiix scheduled delivery

## License
MIT
