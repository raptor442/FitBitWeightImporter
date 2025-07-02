<#
.SYNOPSIS
    Parse Omada weight text and bulk-upload to Fitbit, now with:
        • lb → kg conversion
        • logId + full API response output
        • automatic rate-limit handling
#>

# ── CONFIG ─────────────────────────────────────────────────────────
$accessToken   = $Env:FITBIT_ACCESS_TOKEN
if (-not $accessToken) { throw "FITBIT_ACCESS_TOKEN env var not set." }

# Time to wait between calls under normal operation (sec)
$delaySeconds  = 30                     # ≈120 requests/hour → under 150 cap
# Safety pause after exactly 150 requests (sec)
$fullPauseSec  = 3600                   # 1 hour

# ── RAW LOG (paste Omada clipboard here) ───────────────────────────
$rawLog = @'
...paste Omada “Weight History → View as list” text here...
'@

# ── PARSE (same logic as before) ───────────────────────────────────
$patternInline = '^(?<w>[\d.]+)\s*(lb?s?|pounds)\s+on\s+\w+\s+(?<m>\d{1,2})/(?<d>\d{1,2})'
$patternWeight = '^(?<w>[\d.]+)\s*(lb?s?|pounds)$'
$patternDate   = '^on\s+\w+\s+(?<m>\d{1,2})/(?<d>\d{1,2})'

$records = [System.Collections.Generic.List[object]]::new()
$lines   = $rawLog -split "`n"

for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i].Trim()
    if ($line -match $patternInline) {
        $records.Add([pscustomobject]@{ Month=[int]$Matches.m; Day=[int]$Matches.d; Weight=[double]$Matches.w })
        continue
    }
    if ($line -match $patternWeight) {
        $w = [double]$Matches.w
        if ($i+1 -lt $lines.Count -and ($lines[$i+1].Trim() -match $patternDate)) {
            $records.Add([pscustomobject]@{ Month=[int]$Matches.m; Day=[int]$Matches.d; Weight=$w })
            $i++
        }
    }
}

# Deduplicate (keep first entry per day)
$dedup = @{}
foreach ($r in $records) {
    $k = '{0:00}-{1:00}' -f $r.Month,$r.Day
    if (-not $dedup.ContainsKey($k)) { $dedup[$k]=$r }
}

$currentYear = (Get-Date).Year
$lastMonth   = ($records[0]).Month
$clean       = [System.Collections.Generic.List[object]]::new()

foreach ($r in $records) {
    $k='{0:00}-{1:00}' -f $r.Month,$r.Day
    if (-not $dedup.ContainsKey($k)) { continue }
    if ($r.Month -gt $lastMonth) { $currentYear-- }
    $lastMonth=$r.Month
    $clean.Add([pscustomobject]@{
        Date   = (Get-Date -Year $currentYear -Month $r.Month -Day $r.Day).ToString('yyyy-MM-dd')
        Weight = $r.Weight
    })
    $dedup.Remove($k)
}

Write-Host "✓ Parsed and cleaned $($clean.Count) unique weigh-ins."

$csvPath = '.\weights_clean.csv'
$clean | Sort-Object Date | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "✓ Wrote $csvPath for auditing."

# ── UPLOAD LOOP ────────────────────────────────────────────────────
$headers = @{ Authorization = "Bearer $accessToken" }
$reqCount = 0

foreach ($entry in $clean | Sort-Object Date) {

    # 1) Respect hard limit of 150 req/h
    if ($reqCount -ge 150) {
        Write-Host "⌛ Reached 150 calls → sleeping $fullPauseSec seconds to respect Fitbit rate cap."
        Start-Sleep -Seconds $fullPauseSec
        $reqCount = 0
    }

    # 2) Build payload — convert lb → kg (Fitbit expects kg internally)
    $kg = [math]::Round($entry.Weight / 2.20462, 2)
    $body = @{ weight = $kg; date = $entry.Date }

    try {
        $resp = Invoke-RestMethod -Method Post `
                                  -Uri 'https://api.fitbit.com/1/user/-/body/log/weight.json' `
                                  -Headers $headers -Body $body `
                                  -ContentType 'application/x-www-form-urlencoded'

        $logId = $resp.weightLog.logId
        Write-Host "→ $($entry.Date)  $($entry.Weight) lb  (logId $logId)"
        # Uncomment next line to see full response JSON
        # $resp | ConvertTo-Json -Depth 5 | Out-File -Append .\fitbit_upload_debug.json
        $reqCount++
        Start-Sleep -Seconds $delaySeconds
    }
    catch {
        $err = $_.Exception
        if ($err.Response -and $err.Response.StatusCode.value__ -eq 429) {
            # Handle 429 rate limit with Retry-After header
            $retryAfter = $err.Response.Headers['Retry-After']
            if ($retryAfter) {
                Write-Warning "⚠️  429 Too Many Requests → sleeping $retryAfter seconds."
                Start-Sleep -Seconds ([int]$retryAfter + 5)
            } else {
                Write-Warning "⚠️  429 Too Many Requests → sleeping $fullPauseSec seconds."
                Start-Sleep -Seconds $fullPauseSec
            }
            # retry the same entry after waiting
            $reqCount = 0
            $entry  # loop will retry automatically
        } else {
            Write-Warning "⚠️  Failed on $($entry.Date): $($err.Message)"
        }
    }
}

Write-Host "`nAll done!"
