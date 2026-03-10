<#
.SYNOPSIS
    Provisions, packages, and optionally sideloads the CopilotHLS multi-agent solution.
#>

[CmdletBinding()]
param(
    [ValidateSet('dev', 'local')]
    [string]$Environment = 'dev',

    [string[]]$Project,

    [ValidateSet('Personal', 'Shared')]
    [string]$Scope = 'Shared',

    [switch]$PackageOnly,

    [switch]$SkipProvision,

    [switch]$SkipInstall,

    [switch]$ReuseExistingIds
)

$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────────────────────────────
# Welcome Banner
# ─────────────────────────────────────────────────────────────────────
function Show-WelcomeBanner {
    Write-Host ""
    Write-Host " ╔═════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host " ║                                                                                     ║" -ForegroundColor Cyan
    Write-Host " ║ ██╗  ██╗██╗     ███████╗      ██████╗ ██████╗ ██████╗ ██╗██╗      ██████╗ ████████╗ ║" -ForegroundColor Cyan
    Write-Host " ║ ██║  ██║██║     ██╔════╝     ██╔════╝██╔═══██╗██╔══██╗██║██║     ██╔═══██╗╚══██╔══╝ ║" -ForegroundColor Cyan
    Write-Host " ║ ███████║██║     ███████╗     ██║     ██║   ██║██████╔╝██║██║     ██║   ██║   ██║    ║" -ForegroundColor Cyan
    Write-Host " ║ ██╔══██║██║     ╚════██║     ██║     ██║   ██║██╔═══╝ ██║██║     ██║   ██║   ██║    ║" -ForegroundColor Cyan
    Write-Host " ║ ██║  ██║███████╗███████║     ╚██████╗╚██████╔╝██║     ██║███████╗╚██████╔╝   ██║    ║" -ForegroundColor Cyan
    Write-Host " ║ ╚═╝  ╚═╝╚══════╝╚══════╝      ╚═════╝ ╚═════╝ ╚═╝     ╚═╝╚══════╝ ╚═════╝    ╚═╝    ║" -ForegroundColor Cyan
    Write-Host " ║                                                                                     ║" -ForegroundColor Cyan
    Write-Host " ║                  Health & Life Sciences Copilot for Microsoft 365                   ║" -ForegroundColor Cyan
    Write-Host " ║                                                                                     ║" -ForegroundColor Cyan
    Write-Host " ╚═════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

Show-WelcomeBanner

Import-Module (Join-Path $PSScriptRoot 'CopilotHLS-Deployment.psm1') -Force

if ($PackageOnly) {
    $SkipProvision = $true
    $SkipInstall = $true
}

$repoRoot = Get-CopilotHlsRepositoryRoot
$projects = Resolve-CopilotHlsProjects -Project $Project -Operation Install -RepositoryRoot $repoRoot
$requiredCommands = @('atk')
if (-not $SkipInstall) {
    $requiredCommands += 'teamsapp'
}

Confirm-CopilotHlsCommands -Commands $requiredCommands

$results = New-Object System.Collections.Generic.List[object]

foreach ($projectDefinition in $projects) {
    Write-Host "`n=== $($projectDefinition.Name) ==="

    if ($projectDefinition.Name -eq 'CopilotHLS') {
        $titleUpdates = Update-CopilotHlsWorkerTitleIds -Environment $Environment -RepositoryRoot $repoRoot
        if ($titleUpdates.Count -gt 0) {
            Write-Host "Synchronized worker title IDs into the root environment file."
        }
    }

    if (-not $SkipProvision) {
        if (-not $ReuseExistingIds) {
            Clear-CopilotHlsGeneratedEnvValues -ProjectDefinition $projectDefinition -Environment $Environment
        }

        Write-Host "Running atk provision for $($projectDefinition.Name)..."
        Invoke-CopilotHlsCli -Command 'atk' -Arguments @(
            'provision',
            '-i',
            'false',
            '--env',
            $Environment,
            '--folder',
            $projectDefinition.RootPath
        ) -WorkingDirectory $repoRoot
    }
    else {
        Write-Host "Running atk package for $($projectDefinition.Name)..."
        Invoke-CopilotHlsCli -Command 'atk' -Arguments @(
            'package',
            '--env',
            $Environment,
            '--folder',
            $projectDefinition.RootPath
        ) -WorkingDirectory $repoRoot
    }

    $packagePath = Get-CopilotHlsPackagePath -ProjectDefinition $projectDefinition -Environment $Environment
    if (-not (Test-Path -LiteralPath $packagePath)) {
        throw "Expected package was not created: $packagePath"
    }

    if (-not $SkipInstall) {
        Write-Host "Sideloading package for $($projectDefinition.Name)..."
        Invoke-CopilotHlsCli -Command 'teamsapp' -Arguments @(
            'install',
            '--file-path',
            $packagePath,
            '--scope',
            $Scope
        ) -WorkingDirectory $repoRoot
    }

    $envPath = Get-CopilotHlsEnvPath -ProjectDefinition $projectDefinition -Environment $Environment
    $envValues = Get-CopilotHlsEnvValues -Path $envPath
    $results.Add([pscustomobject]@{
        Project     = $projectDefinition.Name
        Package     = $packagePath
        TeamsAppId  = $envValues['TEAMS_APP_ID']
        M365TitleId = $envValues['M365_TITLE_ID']
        ShareLink   = $envValues['SHARE_LINK']
    })
}

Write-Host "`nDeployment summary:"
$results | Format-Table -AutoSize
