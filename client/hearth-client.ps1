# hearth client for Windows PowerShell.
#
#   notepad $PROFILE
#   # add:  . "$HOME\.hearth-client.ps1"
#
# PowerShell 5.1 (ships with Windows) and 7+ both work. No WSL needed.
#
# Required before dot-sourcing:
#   $env:HEARTH_GATEWAY   e.g. http://192.168.1.10:4000
#   the key goes in         $HOME\.hearth-key
#
# No Ollama here and nothing is downloaded. Every request goes to the gateway
# host, which does the inference and the routing. If that machine is off, none
# of this works — by design.

if (-not $env:HEARTH_GATEWAY -and $env:AI_STACK_GATEWAY) {
    $env:HEARTH_GATEWAY = $env:AI_STACK_GATEWAY
}
if (-not $env:HEARTH_GATEWAY) {
    Write-Host "hearth: set `$env:HEARTH_GATEWAY first (e.g. http://HOST:4000)" -ForegroundColor Yellow
    Write-Host "          Run scripts/client-setup.sh on the gateway host for copy-paste instructions." -ForegroundColor Yellow
    return
}

$script:HearthKeyFile = Join-Path $HOME ".hearth-key"
$script:LegacyKeyFile = Join-Path $HOME ".ai-stack-key"
if (Test-Path $script:HearthKeyFile) {
    $env:HEARTH_KEY = (Get-Content $script:HearthKeyFile -Raw).Trim()
} elseif (Test-Path $script:LegacyKeyFile) {
    $env:HEARTH_KEY = (Get-Content $script:LegacyKeyFile -Raw).Trim()
} elseif ($env:AI_STACK_KEY) {
    $env:HEARTH_KEY = $env:AI_STACK_KEY
}

# OpenAI-compatible, so most tools pick these up with no further config.
$env:OPENAI_API_BASE = "$($env:HEARTH_GATEWAY)/v1"
$env:OPENAI_BASE_URL = "$($env:HEARTH_GATEWAY)/v1"
$env:OPENAI_API_KEY  = $env:HEARTH_KEY

function Get-AiStackHeaders {
    if (-not $env:HEARTH_KEY) {
        Write-Host "No key. Put it in $($script:AiStackKeyFile)" -ForegroundColor Yellow
        return $null
    }
    @{ "Authorization" = "Bearer $($env:HEARTH_KEY)"; "Content-Type" = "application/json" }
}

function ai-ping {
    # The gateway answers 503 {"db":"disconnected"} when its Postgres is down.
    # Your key lives in that database, so "answering" is not "usable" — read the
    # body. -SkipHttpErrorCheck needs PS7, hence the catch-and-inspect fallback.
    Write-Host -NoNewline "gateway $($env:HEARTH_GATEWAY) ... "
    $body = $null
    try {
        $body = Invoke-RestMethod -Uri "$($env:HEARTH_GATEWAY)/health/readiness" -TimeoutSec 5
    } catch {
        $resp = $_.Exception.Response
        if ($resp) {
            try {
                $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
                $body = $sr.ReadToEnd() | ConvertFrom-Json
            } catch { $body = $null }
        }
    }
    if (-not $body) {
        Write-Host "UNREACHABLE" -ForegroundColor Red
        Write-Host "  - is the gateway host awake?"
        Write-Host "  - same network? try: Test-NetConnection $($env:HEARTH_GATEWAY -replace 'https?://','') -Port 4000"
    } elseif ($body.db -eq "connected") {
        Write-Host "up" -ForegroundColor Green
    } else {
        Write-Host "DEGRADED" -ForegroundColor Yellow
        Write-Host "  Answering, but its database is down — your key will return 401."
        Write-Host "  On the gateway host: scripts/boot.sh"
    }
}

function ai-models {
    $h = Get-AiStackHeaders; if (-not $h) { return }
    try {
        $r = Invoke-RestMethod -Uri "$($env:HEARTH_GATEWAY)/v1/models" -Headers $h -TimeoutSec 15
        Write-Host "roles this key can use:"
        $r.data | ForEach-Object { Write-Host "  $($_.id)" }
    } catch {
        Write-Host "failed — is the gateway up and the key correct?" -ForegroundColor Red
    }
}

function ai-ask {
    # ai-ask "question"            -> local-chat
    # ai-ask local-code "question" -> a specific role
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Words)

    $h = Get-AiStackHeaders; if (-not $h) { return }
    $role = "local-chat"
    if ($Words.Count -gt 1 -and $Words[0] -match '^(local|cloud)-') {
        $role = $Words[0]; $Words = $Words[1..($Words.Count - 1)]
    }
    $body = @{
        model    = $role
        messages = @(@{ role = "user"; content = ($Words -join " ") })
    } | ConvertTo-Json -Depth 5

    try {
        $r = Invoke-RestMethod -Uri "$($env:HEARTH_GATEWAY)/v1/chat/completions" `
                               -Method Post -Headers $h -Body $body -TimeoutSec 600
        Write-Output $r.choices[0].message.content
    } catch {
        Write-Host "error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "if this is a 401, the key is wrong; if 400, the role may not exist for this key."
    }
}

# Roles, never model names — the same contract as on the host. When the model
# behind local-code changes, nothing here needs editing.
function ask       { ai-ask local-code  @args }   # coding, private
function ask-chat  { ai-ask local-chat  @args }   # general questions
function ask-fast  { ai-ask local-chat  @args }
function ask-big   { ai-ask local-big   @args }   # reasoning
function ask-cloud { ai-ask cloud-cheap @args }   # leaves the machine

Write-Host "hearth client loaded. Try: ai-ping, ai-models, ask-chat ""say hello""" -ForegroundColor DarkGray
