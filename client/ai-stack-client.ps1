# ai-stack client for Windows PowerShell.
#
#   notepad $PROFILE
#   # add:  . "$HOME\.ai-stack-client.ps1"
#
# PowerShell 5.1 (ships with Windows) and 7+ both work. No WSL needed.
#
# Set before dot-sourcing, or edit the defaults below:
#   $env:AI_STACK_GATEWAY   e.g. http://192.168.50.154:4000
#   the key goes in         $HOME\.ai-stack-key
#
# No Ollama here and nothing is downloaded. Every request goes to the gateway
# on the Mac Studio, which does the inference and the routing. If that machine
# is off, none of this works — by design.

if (-not $env:AI_STACK_GATEWAY) { $env:AI_STACK_GATEWAY = "http://192.168.50.154:4000" }

$script:AiStackKeyFile = Join-Path $HOME ".ai-stack-key"
if (Test-Path $script:AiStackKeyFile) {
    $env:AI_STACK_KEY = (Get-Content $script:AiStackKeyFile -Raw).Trim()
}

# OpenAI-compatible, so most tools pick these up with no further config.
$env:OPENAI_API_BASE = "$($env:AI_STACK_GATEWAY)/v1"
$env:OPENAI_BASE_URL = "$($env:AI_STACK_GATEWAY)/v1"
$env:OPENAI_API_KEY  = $env:AI_STACK_KEY

function Get-AiStackHeaders {
    if (-not $env:AI_STACK_KEY) {
        Write-Host "No key. Put it in $($script:AiStackKeyFile)" -ForegroundColor Yellow
        return $null
    }
    @{ "Authorization" = "Bearer $($env:AI_STACK_KEY)"; "Content-Type" = "application/json" }
}

function ai-ping {
    Write-Host -NoNewline "gateway $($env:AI_STACK_GATEWAY) ... "
    try {
        Invoke-RestMethod -Uri "$($env:AI_STACK_GATEWAY)/health/readiness" -TimeoutSec 5 | Out-Null
        Write-Host "up" -ForegroundColor Green
    } catch {
        Write-Host "UNREACHABLE" -ForegroundColor Red
        Write-Host "  - is the Mac Studio awake?"
        Write-Host "  - same network? try: Test-NetConnection $($env:AI_STACK_GATEWAY -replace 'https?://','') -Port 4000"
    }
}

function ai-models {
    $h = Get-AiStackHeaders; if (-not $h) { return }
    try {
        $r = Invoke-RestMethod -Uri "$($env:AI_STACK_GATEWAY)/v1/models" -Headers $h -TimeoutSec 15
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
        $r = Invoke-RestMethod -Uri "$($env:AI_STACK_GATEWAY)/v1/chat/completions" `
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

Write-Host "ai-stack client loaded. Try: ai-ping, ai-models, ask-chat ""say hello""" -ForegroundColor DarkGray
