<#
    NAME: Get-FitbitToken.ps1
    PURPOSE:
        • First run  → walks you through browser-based consent,
                       exchanges the code for tokens, and saves them.
        • Later runs → refreshes silently with the saved refresh_token.
        • Always exports the access token to $Env:FITBIT_ACCESS_TOKEN.
#>

param(
    [string]$ClientId,
    [string]$ClientSecret,
    [string]$RedirectUri = 'http://127.0.0.1:8080',
    [string]$Scope       = 'weight profile',      # space-delimited list
    [string]$CacheFile   = "$HOME\.fitbit_token.json"
)

### 1 ── Collect app keys if not passed in
if (-not $ClientId)     { $ClientId     = Read-Host 'Fitbit CLIENT ID' }
if (-not $ClientSecret) { $ClientSecret = Read-Host 'Fitbit CLIENT SECRET' }

### 2 ── Helper: save tokens + expose access_token to current session
function Save-Tokens {
    param($Tok)
    $Tok | ConvertTo-Json -Depth 5 | Set-Content $CacheFile
    $Env:FITBIT_ACCESS_TOKEN = $Tok.access_token
}

### 3 ── Build Basic-auth header Fitbit expects
$basicAuth  = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$ClientId`:$ClientSecret"))
$headers    = @{ Authorization = "Basic $basicAuth" }
$contentTyp = 'application/x-www-form-urlencoded'

### 4 ── Try silent refresh if a cache file exists
if (Test-Path $CacheFile) {
    try {
        $saved = Get-Content $CacheFile | ConvertFrom-Json
        if ($saved.refresh_token) {
            Write-Host "🔄  Refreshing access token with saved refresh_token …"
            $body = @{
                grant_type    = 'refresh_token'
                refresh_token = $saved.refresh_token
            }
            $tok = Invoke-RestMethod -Method Post -Uri 'https://api.fitbit.com/oauth2/token' `
                                     -Headers $headers -Body $body -ContentType $contentTyp
            Save-Tokens $tok
            Write-Host "✓  Refreshed. \$Env:FITBIT_ACCESS_TOKEN set (valid ~$([math]::Round($tok.expires_in/3600,1)) h)."
            return
        }
    }
    catch {
        Write-Warning "Refresh failed ($($_.Exception.Message)). Falling back to browser flow."
    }
}

### 5 ── Full browser authorization-code flow
$state           = [guid]::NewGuid().Guid
$escRedirectUri  = [uri]::EscapeDataString($RedirectUri)
$escScope        = [uri]::EscapeDataString($Scope)
$authUrl         = "https://www.fitbit.com/oauth2/authorize?response_type=code" +
                   "&client_id=$ClientId" +
                   "&redirect_uri=$escRedirectUri" +
                   "&scope=$escScope" +
                   "&state=$state"

Write-Host ""
Write-Host "Opening Fitbit consent page …"
Start-Process $authUrl

$code = Read-Host "`nPaste the value of code= from the address bar Fitbit redirected you to"
if (-not $code) { throw "No code supplied. Aborting." }

### 6 ── Exchange code for tokens
$body = @{
    grant_type   = 'authorization_code'
    code         = $code
    redirect_uri = $RedirectUri
}

$tok = Invoke-RestMethod -Method Post -Uri 'https://api.fitbit.com/oauth2/token' `
                         -Headers $headers -Body $body -ContentType $contentTyp
Save-Tokens $tok
Write-Host ""
Write-Host "✓  New token set in \$Env:FITBIT_ACCESS_TOKEN (valid ~$([math]::Round($tok.expires_in/3600,1)) h)"
Write-Host "✓  Tokens saved to $CacheFile for automatic refresh next time."
