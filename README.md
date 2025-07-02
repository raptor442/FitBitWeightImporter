# Omada → Fitbit Weight Importer

Move your entire weight history from **Omada Health** into **Fitbit** with two PowerShell scripts:

| Script | What it does |
| ------ | ------------ |
| **fitbit_generate_accesstoken.ps1** | Walks you through Fitbit OAuth, saves *access* and *refresh* tokens, and sets `$Env:FITBIT_ACCESS_TOKEN` for the current session. |
| **fitbit_import_weight.ps1** | Parses raw Omada weight text, deduplicates dates, and bulk-uploads one entry per day to Fitbit (staying below Fitbit’s 150 requests / hour limit). |

---

## Why this repo exists
Omada lets you copy your weight list, but Fitbit has *no* “CSV import” button. The combination here bridges that gap so you can keep a single, continuous weight timeline inside Fitbit.

---

## Table of Contents
1. [Prerequisites](#prerequisites)  
2. [Step 1: Export weights from Omada](#step-1-export-weights-from-omada)  
3. [Step 2: Create a Fitbit developer app](#step-2-create-a-fitbit-developer-app)  
4. [Step 3: Generate or refresh your Fitbit access token](#step-3-generate-or-refresh-your-fitbit-access-token)  
5. [Step 4: Insert Omada data into the importer script](#step-4-insert-omada-data-into-the-importer-script)  
6. [Step 5: Run the importer](#step-5-run-the-importer)  
7. [Troubleshooting](#troubleshooting)  
8. [License](#license)

---

## Prerequisites
* Windows 10 / 11, macOS, or Linux with **PowerShell 5+**  
* A **Fitbit** account and any Fitbit device (or just the app)  
* An **Omada** account with historical weight entries  
* Internet access for the API calls

---

## Step 1: Export weights from Omada
1. Sign in to **https://app.omadahealth.com/progress**.  
2. In the sidebar select **Progress → Weight History**.  
3. Click **View as list** in the upper-right of the chart.  
4. Press **Ctrl + A** (or ⌘ + A) to highlight the full table, then **Ctrl + C** to copy it.

> *Tip*  
> Do not edit the copied text. The importer script handles messy spacing, duplicate rows, and the “lbs / pounds” variations for you.

---

## Step 2: Create a Fitbit developer app
Fitbit requires an OAuth token for *any* write operation, so you must register a *Personal* app:

| Field | Minimal entry for personal use |
| ----- | ----------------------------- |
| **Application Name** | *Weight Bulk Uploader* |
| **Description** | Personal script to upload Omada weight history |
| **Application Website URL** | `http://localhost` |
| **OAuth 2.0 Application Type** | **Personal** |
| **Redirect URL** | `http://127.0.0.1:8080` |
| **Default Access Type** | **Read & Write** |
| *All other fields* | Leave blank or repeat `http://localhost` |

1. Save the form.  
2. Copy the **Client ID** and **Client Secret**.  
3. Open your new app, scroll to **OAuth 2.0 Scopes**, and tick **weight** (plus **profile** if you also want user info).  
4. Save again.

---

## Step 3: Generate or refresh your Fitbit access token
Run the helper script:

```powershell
PS> .\fitbit_generate_accesstoken.ps1
```

* **First run**  
  * The script asks for your *Client ID* and *Client Secret* (it remembers them).  
  * A browser window opens; log in and click **Allow**.  
  * Copy the `code=` value from the redirected URL back into PowerShell.  
  * Tokens are saved to `~/.fitbit_token.json` and `$Env:FITBIT_ACCESS_TOKEN` is set.

* **Later runs**  
  * The script refreshes silently using the saved *refresh token*.  
  * `$Env:FITBIT_ACCESS_TOKEN` is updated automatically.

---

## Step 4: Insert Omada data into the importer script
1. Open **fitbit_import_weight.ps1** in your editor.  
2. Find the here-string:

   ```powershell
   $rawLog = @'
   ...paste here...
   '@
   ```

3. Delete the placeholder lines between `@'` and `'@`.  
4. Paste your Omada clipboard content there.  
5. Save the file.

---

## Step 5: Run the importer
```powershell
# same PowerShell session where you ran the token generator
PS> .\fitbit_import_weight.ps1
```

What happens:

* The script cleans the log, infers year roll-overs (December → January), and keeps only the first entry per date.
* It uploads each weight to Fitbit at ~1.2 seconds per request—well below the 150 calls / hour cap.
* Progress and any errors print to the console.

Open the Fitbit mobile or web app → **Today → Weight** and spot-check a few dates.

---

## Troubleshooting
| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| **401 Unauthorized** | `$Env:FITBIT_ACCESS_TOKEN` expired | Re‑run `fitbit_generate_accesstoken.ps1` |
| **“invalid_grant”** during token exchange | `code=` reused or >10 min old | Rerun the token script and copy a fresh code |
| Duplicates appear in Fitbit | Omada list pasted twice | Clear the here‑string, paste once, rerun importer |
| Import stops after ~150 rows | Fitbit rate limit (150 req/hr) | Wait one hour, then rerun importer (it resumes) |

---

## License
MIT. See [LICENSE](LICENSE) for details.
