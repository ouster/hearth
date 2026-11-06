# hearth client for Windows PowerShell. ADR 0016, phase 4: SSH tunnel only.
#
#   notepad $PROFILE
#   # add:  . "$HOME\.hearth-client.ps1"
#
# PowerShell 5.1 and 7+. Needs the built-in OpenSSH client (ssh.exe).
#
# The host's oMLX listens on 127.0.0.1:1234 only; this machine reaches it
# through an SSH tunnel, on and off the LAN.
#
# Set before dot-sourcing (scripts/client-setup.sh --windows prints these):
#   $env:HEARTH_SSH          user@host, e.g. colin@Colins-Mac-Studio.local
#   $env:HEARTH_CLOUD_MODEL  Gemini model id for ask-cloud (from the host's roles.tsv)
# Secrets (files, never put in environment variables):
#   $HOME\.hearth-key         this machine's API key (laptop-<name>)
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

function Test-HearthPort([int]$Port) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $c.Connect("127.0.0.1", $Port); $c.Close(); return $true
    } catch { return $false }
}

function Test-HearthForwards {
    if (-not (Test-HearthPort ([int]$script:HearthLocalPort))) { return $false }
    if (-not (Test-HearthPort ([int]$script:HearthWebuiPort))) { return $false }
    if ($script:HearthSearxngPort -ne "0" -and -not (Test-HearthPort ([int]$script:HearthSearxngPort))) { return $false }
    return $true
}

# A listener is not enough. The token goes to this port, so the process must be
# our ssh -L. An empty CommandLine is not proof, and means refuse.
function Test-HearthOurSsh {
    $pat = "127.0.0.1:$($script:HearthLocalPort):127.0.0.1:1234"
    try {
        $hit = @(Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction Stop |
            Where-Object { $_.CommandLine -and ($_.CommandLine -like "*$pat*") })
        return ($hit.Count -gt 0)
    } catch {
        return $false
    }
}

function Test-HearthStranger {
    (Test-HearthPort ([int]$script:HearthLocalPort)) -and -not (Test-HearthOurSsh)
}

# Safe to send the token. Does not start a tunnel.
function Confirm-HearthTokenTunnel {
    if (Test-HearthStranger) {
        Write-Host "127.0.0.1:$($script:HearthLocalPort) is open, but not the hearth ssh tunnel. Not sending the token." -ForegroundColor Red
        return $false
    }
    if (-not (Test-HearthOurSsh) -or -not (Test-HearthPort ([int]$script:HearthLocalPort))) {
        Write-Host "DOWN — no tunnel. Run: ai-tunnel" -ForegroundColor Red
        return $false
    }
    return $true
}

# Stranger: refuse, do not start ssh. Otherwise bring the forwards up.
function Connect-HearthTunnel {
    if (Test-HearthStranger) {
        Write-Host "127.0.0.1:$($script:HearthLocalPort) is open, but not the hearth ssh tunnel. Not sending the token." -ForegroundColor Red
        return $false
    }
    if (-not (Test-HearthForwards)) {
        if (-not (ai-tunnel)) { return $false }
    }
    if (-not (Test-HearthOurSsh) -or -not (Test-HearthPort ([int]$script:HearthLocalPort))) {
        Write-Host "DOWN — no tunnel. Run: ai-tunnel" -ForegroundColor Red
        return $false
    }
    return $true
}

function Restore-HearthEnv([string]$Name, $Previous) {
    if ($null -eq $Previous) {
        Remove-Item -Path "Env:$Name" -ErrorAction SilentlyContinue
    } else {
        Set-Item -Path "Env:$Name" -Value $Previous
    }
}

function ai-tunnel {
    if (Test-HearthStranger) {
        Write-Host "tunnel: 127.0.0.1:$($script:HearthLocalPort) is open, but not the hearth ssh tunnel. Refusing." -ForegroundColor Red
        return $false
    }
    if ((Test-HearthOurSsh) -and (Test-HearthPort ([int]$script:HearthLocalPort))) {
        if (Test-HearthForwards) {
            Write-Host "tunnel: already listening on 127.0.0.1:$($script:HearthLocalPort)"
            return $true
        }
        $missing = @()
        if (-not (Test-HearthPort ([int]$script:HearthWebuiPort))) { $missing += "WebUI $($script:HearthWebuiPort)" }
        if ($script:HearthSearxngPort -ne "0" -and -not (Test-HearthPort ([int]$script:HearthSearxngPort))) { $missing += "SearXNG $($script:HearthSearxngPort)" }
        Write-Host "tunnel: 127.0.0.1:$($script:HearthLocalPort) is open but a forward is missing ($($missing -join ', '))." -ForegroundColor Red
        Write-Host "        Run: ai-tunnel-stop; ai-tunnel" -ForegroundColor Red
        return $false
    }
    # In this console, not a hidden window: the first connect has to show the
    # host-key prompt. -f backgrounds after auth (same as the bash client).
    $sshArgs = @(
        "-f", "-N",
        "-o", "ExitOnForwardFailure=yes",
        "-o", "ServerAliveInterval=30",
        "-o", "ServerAliveCountMax=3",
        "-L", "127.0.0.1:$($script:HearthLocalPort):127.0.0.1:1234",
        "-L", "127.0.0.1:$($script:HearthWebuiPort):127.0.0.1:3000")
    if ($script:HearthSearxngPort -ne "0") {
        $sshArgs += @("-L", "127.0.0.1:$($script:HearthSearxngPort):127.0.0.1:8888")
    }
    $sshArgs += $env:HEARTH_SSH
    & ssh @sshArgs
    if ($LASTEXITCODE -ne 0 -or -not ((Test-HearthOurSsh) -and (Test-HearthForwards))) {
        Write-Host "tunnel: FAILED — try: ssh $($env:HEARTH_SSH)" -ForegroundColor Red
        return $false
    }
    $sx = ""
    if ($script:HearthSearxngPort -ne "0") { $sx = ", SearXNG → 127.0.0.1:$($script:HearthSearxngPort)" }
    Write-Host "tunnel: up (oMLX → 127.0.0.1:$($script:HearthLocalPort), WebUI → 127.0.0.1:$($script:HearthWebuiPort)$sx)"
    return $true
}

function ai-tunnel-stop {
    Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
        Where-Object { $_.CommandLine -like "*127.0.0.1:$($script:HearthLocalPort):127.0.0.1:1234*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId; Write-Host "tunnel: stopped" }
}

function ai-ping {
    if (-not (Confirm-HearthTokenTunnel)) { return }
    $k = Get-HearthSecret ".hearth-key"; if (-not $k) { return }
    try {
        Invoke-WebRequest -UseBasicParsing -TimeoutSec 8 -Uri "$($script:HearthUrl)/models" `
            -Headers @{ Authorization = "Bearer $k" } | Out-Null
        Write-Host "up" -ForegroundColor Green
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code -eq 401) { Write-Host "BAD TOKEN — $HOME\.hearth-key was refused" -ForegroundColor Red }
        else { Write-Host "NO ANSWER — host asleep or oMLX down (on the host: scripts/boot.sh)" -ForegroundColor Red }
    }
}

function ai-models {
    if (-not (Confirm-HearthTokenTunnel)) { return }
    $k = Get-HearthSecret ".hearth-key"; if (-not $k) { return }
    (Invoke-RestMethod -TimeoutSec 8 -Uri "$($script:HearthUrl)/models" -Headers @{ Authorization = "Bearer $k" }).data |
        ForEach-Object { "  " + $_.id }
}

function ai-ask {
    if (-not $args) { Write-Host 'usage: ai-ask "question"'; return }
    if (-not (Confirm-HearthTokenTunnel)) { return }
    $k = Get-HearthSecret ".hearth-key"; if (-not $k) { return }
    $body = @{ model = "local-main"; messages = @(@{ role = "user"; content = ($args -join " ") }) } | ConvertTo-Json -Depth 5
    $r = Invoke-RestMethod -TimeoutSec 300 -Method Post -Uri "$($script:HearthUrl)/chat/completions" `
        -Headers @{ Authorization = "Bearer $k" } -ContentType "application/json" -Body $body
    "$($r.choices[0].message.content)".Trim()
}

function ai-webui {
    if (Test-HearthStranger) {
        Write-Host "127.0.0.1:$($script:HearthLocalPort) is open, but not the hearth ssh tunnel." -ForegroundColor Red
        return
    }
    if (-not (Test-HearthForwards)) { if (-not (ai-tunnel)) { return } }
    Start-Process "http://127.0.0.1:$($script:HearthWebuiPort)"
}

# aider: token set only for the child process, then the previous value put back.
function Invoke-HearthAider {
    if (-not (Connect-HearthTunnel)) { return }
    $k = Get-HearthSecret ".hearth-key"; if (-not $k) { return }
    $prevBase = $env:OPENAI_API_BASE
    $prevKey = $env:OPENAI_API_KEY
    $env:OPENAI_API_BASE = $script:HearthUrl; $env:OPENAI_API_KEY = $k
    try { aider --model openai/local-main --weak-model openai/local-main @args }
    finally {
        Restore-HearthEnv OPENAI_API_KEY $prevKey
        Restore-HearthEnv OPENAI_API_BASE $prevBase
    }
}
function ask       { Invoke-HearthAider @args }
function ask-big   { Invoke-HearthAider @args }
function ask-local { Invoke-HearthAider @args }
function ask-chat  { Invoke-HearthAider @args }
function ask-arch  { Invoke-HearthAider --architect --editor-model openai/local-main @args }

# local-deep (ADR 0020): must already be loaded on the host. An unloaded role
# would be answered by local-main without saying so, so refuse unless listed.
function ask-deep {
    if (-not (Connect-HearthTunnel)) { return }
    $k = Get-HearthSecret ".hearth-key"; if (-not $k) { return }
    $ids = (Invoke-RestMethod -TimeoutSec 8 -Uri "$($script:HearthUrl)/models" -Headers @{ Authorization = "Bearer $k" }).data.id
    if ($ids -notcontains "local-deep") {
        Write-Host "local-deep is not loaded on the host. On the host: scripts/demand-load.sh local-deep up (a 48 GB host swaps out local-main; ... down brings it back)" -ForegroundColor Yellow
        return
    }
    $prevBase = $env:OPENAI_API_BASE
    $prevKey = $env:OPENAI_API_KEY
    $env:OPENAI_API_BASE = $script:HearthUrl; $env:OPENAI_API_KEY = $k
    try { aider --model openai/local-deep --weak-model openai/local-deep @args }
    finally {
        Restore-HearthEnv OPENAI_API_KEY $prevKey
        Restore-HearthEnv OPENAI_API_BASE $prevBase
    }
}

# The only command that leaves for the cloud, with THIS machine's own key.
function ask-cloud {
    if (-not $env:HEARTH_CLOUD_MODEL) { Write-Host "hearth: set `$env:HEARTH_CLOUD_MODEL" -ForegroundColor Yellow; return }
    $g = Get-HearthSecret ".hearth-gemini-key"; if (-not $g) { return }
    $prevGemini = $env:GEMINI_API_KEY
    $env:GEMINI_API_KEY = $g
    try { aider --model "gemini/$($env:HEARTH_CLOUD_MODEL)" --weak-model "gemini/$($env:HEARTH_CLOUD_MODEL)" @args }
    finally { Restore-HearthEnv GEMINI_API_KEY $prevGemini }
}
