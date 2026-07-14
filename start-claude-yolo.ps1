# Starts Docker Desktop (Windows containers mode), builds the image if needed,
# and drops you straight into Claude Code with permission prompts disabled.
#
# YOLO mode caveats: the repo and Avery.Controls are bind-mounted read-write,
# and the container can reach the LAN (lab-mini-2, network instruments).
# Commit/push before running. See README.md.

[CmdletBinding()]
param(
    # Force a docker compose build even if the image already exists.
    [switch]$Rebuild
)

$ErrorActionPreference = 'Stop'

$dockerDesktop = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
$dockerCli     = 'C:\Program Files\Docker\Docker\DockerCli.exe'

function Get-EngineOs {
    try { docker version --format '{{.Server.Os}}' 2>$null } catch { $null }
}

if (-not (Get-EngineOs)) {
    Write-Host 'Starting Docker Desktop...'
    Start-Process $dockerDesktop
    $deadline = (Get-Date).AddMinutes(3)
    while (-not (Get-EngineOs)) {
        if ((Get-Date) -gt $deadline) { throw 'Docker daemon did not come up within 3 minutes.' }
        Start-Sleep -Seconds 3
    }
}

if ((Get-EngineOs) -ne 'windows') {
    Write-Host 'Switching Docker to Windows containers...'
    & $dockerCli -SwitchWindowsEngine
    $deadline = (Get-Date).AddMinutes(2)
    while ((Get-EngineOs) -ne 'windows') {
        if ((Get-Date) -gt $deadline) { throw 'Docker did not switch to Windows containers mode.' }
        Start-Sleep -Seconds 3
    }
}

Push-Location $PSScriptRoot
try {
    if ($Rebuild -or -not (docker image ls -q lotus-claude-windows:latest)) {
        Write-Host 'Building image (first build takes a while)...'
        docker compose build
        if ($LASTEXITCODE -ne 0) { throw 'Image build failed.' }
    }

    Write-Host 'Launching Claude Code (permission prompts disabled)...' -ForegroundColor Yellow
    # `claude` is an npm .cmd shim, which CreateProcess can't exec directly —
    # it needs a shell in front of it to resolve.
    docker compose run --rm claude powershell -NoLogo -Command 'claude --dangerously-skip-permissions'
}
finally {
    Pop-Location
}
