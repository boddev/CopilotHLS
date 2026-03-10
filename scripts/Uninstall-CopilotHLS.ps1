<#
.SYNOPSIS
    Removes CopilotHLS apps from a testing environment using Agents Toolkit environment state.
#>

[CmdletBinding()]
param(
    [ValidateSet('dev', 'local')]
    [string]$Environment = 'dev',

    [string[]]$Project,

    [switch]$AlsoRemoveAppRegistrations,

    [switch]$KeepGeneratedIds
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'CopilotHLS-Deployment.psm1') -Force

$repoRoot = Get-CopilotHlsRepositoryRoot
$projects = Resolve-CopilotHlsProjects -Project $Project -Operation Uninstall -RepositoryRoot $repoRoot

Confirm-CopilotHlsCommands -Commands @('teamsapp')

$uninstallOptions = @('m365-app')
if ($AlsoRemoveAppRegistrations) {
    $uninstallOptions += 'app-registration'
}

$results = New-Object System.Collections.Generic.List[object]

foreach ($projectDefinition in $projects) {
    Write-Host "`n=== $($projectDefinition.Name) ==="
    Write-Host "Running teamsapp uninstall for $($projectDefinition.Name)..."

    Invoke-CopilotHlsCli -Command 'teamsapp' -Arguments @(
        'uninstall',
        '-i',
        'false',
        '--mode',
        'env',
        '--env',
        $Environment,
        '--folder',
        $projectDefinition.RootPath,
        '--options',
        ($uninstallOptions -join ',')
    ) -WorkingDirectory $repoRoot

    if (-not $KeepGeneratedIds) {
        Clear-CopilotHlsGeneratedEnvValues -ProjectDefinition $projectDefinition -Environment $Environment
    }

    $envPath = Get-CopilotHlsEnvPath -ProjectDefinition $projectDefinition -Environment $Environment
    $envValues = Get-CopilotHlsEnvValues -Path $envPath
    $results.Add([pscustomobject]@{
        Project     = $projectDefinition.Name
        TeamsAppId  = $envValues['TEAMS_APP_ID']
        M365TitleId = $envValues['M365_TITLE_ID']
        ShareLink   = $envValues['SHARE_LINK']
    })
}

Write-Host "`nUninstall summary:"
$results | Format-Table -AutoSize
