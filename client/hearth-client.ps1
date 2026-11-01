# hearth client for Windows PowerShell. ADR 0016, phase 4: SSH tunnel only.
#
#   notepad $PROFILE
#   # add:  . "$HOME\.hearth-client.ps1"
#
# PowerShell 5.1 and 7+. Needs the built-in OpenSSH client (ssh.exe).
#
# The host's LM Studio listens on 127.0.0.1:1234 only; this machine reaches it
# through an SSH tunnel, on and off the LAN.
#
# Set before dot-sourcing (scripts/client-setup.sh --windows prints these):
#   $env:HEARTH_SSH          user@host, e.g. colin@Colins-Mac-Studio.local
#   $env:HEARTH_CLOUD_MODEL  Gemini model id for ask-cloud (from the host's roles.tsv)
# Secrets (files, never put in environment variables):
#   $HOME\.hearth-key         this machine's LM Studio token (laptop-<name>)
#   $HOME\.hearth-gemini-key  this machine's own Google API key, ask-cloud only

if ($env:HEARTH_GATEWAY -or $env:AI_STACK_GATEWAY) {
    Write-Host "hearth: HEARTH_GATEWAY is from the retired gateway and is ignored — set `$env:HEARTH_SSH." -ForegroundColor Yellow
}
if (-not $env:HEARTH_SSH) {
    Write-Host "hearth: set `$env:HEARTH_SSH first (e.g. you@your-host.local)" -ForegroundColor Yellow
    return
}

$script:HearthLocalPort = if ($env:HEARTH_LOCAL_PORT) { $env:HEARTH_LOCAL_PORT } else { "1234" }
$script:HearthWebuiPort = if ($env:HEARTH_WEBUI_PORT) { $env:HEARTH_WEBUI_PORT } else { "3000" }
# Host's SearXNG, for a SearXNG MCP server on this laptop (ADR 0022). "0" skips it.
$script:HearthSearxngPort = if ($env:HEARTH_SEARXNG_PORT) { $env:HEARTH_SEARXNG_PORT } else { "8888" }
$script:HearthUrl = "http://127.0.0.1:$($script:HearthLocalPort)/v1"

function Get-HearthSecret([string]$Name) {
    $f = Join-Path $HOME $Name
    if (-not (Test-Path -LiteralPath $f)) { Write-Host "hearth: $f missing" -ForegroundColor Yellow; return $null }
    $acl = Get-Acl -LiteralPath $f
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    foreach ($ace in $acl.Access) {
        if ($ace.AccessControlType -ne 'Allow') { continue }
        $who = [string]$ace.IdentityReference
        if ($who -eq $me -or $who.EndsWith('\' + $env:USERNAME)) { continue }
        if ($who -match '(^|\\)(SYSTEM|Administrators)$') { continue }
        $rights = [int]$ace.FileSystemRights
        # FILE_READ_DATA (1) or GENERIC_READ (0x80000000).
        if ((($rights -band 1) -ne 0) -or (($rights -band 0x80000000) -ne 0)) {
            Write-Host "hearth: $f is readable by $who — remove that ACL entry" -ForegroundColor Yellow
            return $null
        }
    }
    (Get-Content -LiteralPath $f -Raw).Trim()
}

function Test-HearthTunnel {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $c.Connect("127.0.0.1", [int]$script:HearthLocalPort); $c.Close(); return $true
    } catch { return $false }
}

function ai-tunnel {
    if (Test-HearthTunnel) { Write-Host "tunnel: already listening on 127.0.0.1:$($script:HearthLocalPort)"; return }
    $sshArgs = @(
        "-N", "-o", "ExitOnForwardFailure=yes", "-o", "ServerAliveInterval=30",
        "-L", "127.0.0.1:$($script:HearthLocalPort):127.0.0.1:1234",
        "-L", "127.0.0.1:$($script:HearthWebuiPort):127.0.0.1:3000")
    if ($script:HearthSearxngPort -ne "0") { $sshArgs += @("-L", "127.0.0.1:$($script:HearthSearxngPort):127.0.0.1:8888") }
    Start-Process -WindowStyle Hidden ssh -ArgumentList ($sshArgs + @($env:HEARTH_SSH))
    Start-Sleep -Seconds 3
    if (Test-HearthTunnel) { Write-Host "tunnel: up" } else { Write-Host "tunnel: FAILED — try: ssh $env:HEARTH_SSH" -ForegroundColor Red }
}

function ai-tunnel-stop {
    Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
        Where-Object { $_.CommandLine -like "*127.0.0.1:$($script:HearthLocalPort):127.0.0.1:1234*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId; Write-Host "tunnel: stopped" }
}

function ai-ping {
    $k = Get-HearthSecret ".hearth-key"; if (-not $k) { return }
    if (-not (Test-HearthTunnel)) { Write-Host "DOWN — no tunnel. Run: ai-tunnel" -ForegroundColor Red; return }
    try {
        Invoke-WebRequest -UseBasicParsing -TimeoutSec 8 -Uri "$($script:HearthUrl)/models" `
            -Headers @{ Authorization = "Bearer $k" } | Out-Null
        Write-Host "up" -ForegroundColor Green
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code -eq 401) { Write-Host "BAD TOKEN — $HOME\.hearth-key was refused" -ForegroundColor Red }
        else { Write-Host "NO ANSWER — host asleep or LM Studio down (on the host: scripts/boot.sh)" -ForegroundColor Red }
    }
}

function ai-models {
    $k = Get-HearthSecret ".hearth-key"; if (-not $k) { return }
    (Invoke-RestMethod -TimeoutSec 8 -Uri "$($script:HearthUrl)/models" -Headers @{ Authorization = "Bearer $k" }).data |
        ForEach-Object { "  " + $_.id }
}

function ai-ask {
    if (-not $args) { Write-Host 'usage: ai-ask "question"'; return }
    $k = Get-HearthSecret ".hearth-key"; if (-not $k) { return }
    $body = @{ model = "local-main"; messages = @(@{ role = "user"; content = ($args -join " ") }) } | ConvertTo-Json -Depth 5
    $r = Invoke-RestMethod -TimeoutSec 300 -Method Post -Uri "$($script:HearthUrl)/chat/completions" `
        -Headers @{ Authorization = "Bearer $k" } -ContentType "application/json" -Body $body
    "$($r.choices[0].message.content)".Trim()
}

function ai-webui {
    if (-not (Test-HearthTunnel)) { ai-tunnel }
    Start-Process "http://127.0.0.1:$($script:HearthWebuiPort)"
}

# aider: token set only for the child process, then removed.
function Invoke-HearthAider {
    $k = Get-HearthSecret ".hearth-key"; if (-not $k) { return }
    if (-not (Test-HearthTunnel)) { ai-tunnel }
    $env:OPENAI_API_BASE = $script:HearthUrl; $env:OPENAI_API_KEY = $k
    try { aider --model openai/local-main --weak-model openai/local-main @args }
    finally { Remove-Item Env:OPENAI_API_KEY, Env:OPENAI_API_BASE -ErrorAction SilentlyContinue }
}
function ask       { Invoke-HearthAider @args }
function ask-big   { Invoke-HearthAider @args }
function ask-local { Invoke-HearthAider @args }
function ask-chat  { Invoke-HearthAider @args }
function ask-arch  { Invoke-HearthAider --architect --editor-model openai/local-main @args }

# local-deep (ADR 0020): must already be loaded on the host. An unloaded role
# would be answered by local-main without saying so, so refuse unless listed.
function ask-deep {
    $k = Get-HearthSecret ".hearth-key"; if (-not $k) { return }
    if (-not (Test-HearthTunnel)) { ai-tunnel }
    $ids = (Invoke-RestMethod -TimeoutSec 8 -Uri "$($script:HearthUrl)/models" -Headers @{ Authorization = "Bearer $k" }).data.id
    if ($ids -notcontains "local-deep") {
        Write-Host "local-deep is not loaded on the host. On the host: scripts/demand-load.sh local-deep up --evict (swaps out local-main; ... down brings it back)" -ForegroundColor Yellow
        return
    }
    $env:OPENAI_API_BASE = $script:HearthUrl; $env:OPENAI_API_KEY = $k
    try { aider --model openai/local-deep --weak-model openai/local-main @args }
    finally { Remove-Item Env:OPENAI_API_KEY, Env:OPENAI_API_BASE -ErrorAction SilentlyContinue }
}

# The only command that leaves for the cloud, with THIS machine's own key.
function ask-cloud {
    if (-not $env:HEARTH_CLOUD_MODEL) { Write-Host "hearth: set `$env:HEARTH_CLOUD_MODEL" -ForegroundColor Yellow; return }
    $g = Get-HearthSecret ".hearth-gemini-key"; if (-not $g) { return }
    $env:GEMINI_API_KEY = $g
    try { aider --model "gemini/$($env:HEARTH_CLOUD_MODEL)" --weak-model "gemini/$($env:HEARTH_CLOUD_MODEL)" @args }
    finally { Remove-Item Env:GEMINI_API_KEY -ErrorAction SilentlyContinue }
}
