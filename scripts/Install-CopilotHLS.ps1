<#
.SYNOPSIS
    Provisions, packages, and optionally sideloads the CopilotHLS multi-agent solution.

.DESCRIPTION
    Interactive installer that provisions up to 9 declarative agents for health & life sciences
    including specialist workers, Veeva connector agents, and the primary orchestrator.
    Supports agent selection, Veeva connector setup, dependency-ordered provisioning,
    and automatic worker_agents title ID resolution.

.PARAMETER Environment
    Target environment: 'dev' (default) or 'local'.

.PARAMETER Scope
    Sideload scope: 'Shared' (default) or 'Personal'.

.PARAMETER PackageOnly
    Build packages without provisioning or sideloading.

.PARAMETER SkipProvision
    Skip ATK provision step (package only).

.PARAMETER SkipInstall
    Skip teamsapp install step (provision but don't sideload).

.PARAMETER ReuseExistingIds
    Keep existing TEAMS_APP_ID values instead of clearing them.

.PARAMETER DryRun
    Simulate the installation without making any changes.

.PARAMETER SkipPrerequisites
    Skip prerequisite checks.

.PARAMETER NonInteractive
    Use default selections (all agents, no Veeva connectors).

.EXAMPLE
    .\Install-CopilotHLS.ps1
    .\Install-CopilotHLS.ps1 -DryRun
    .\Install-CopilotHLS.ps1 -PackageOnly
    .\Install-CopilotHLS.ps1 -NonInteractive
#>

[CmdletBinding()]
param(
    [ValidateSet('dev', 'local')]
    [string]$Environment = 'dev',

    [ValidateSet('Personal', 'Shared')]
    [string]$Scope = 'Shared',

    [switch]$PackageOnly,
    [switch]$SkipProvision,
    [switch]$SkipInstall,
    [switch]$ReuseExistingIds,
    [switch]$DryRun,
    [switch]$SkipPrerequisites,
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'
$InstallerVersion = '1.1'
$startTime = Get-Date

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
    $versionText = "Installer v$InstallerVersion"
    $vPadTotal = 85 - $versionText.Length
    $vPadLeft = [math]::Floor($vPadTotal / 2)
    $vPadRight = $vPadTotal - $vPadLeft
    Write-Host (" ║" + (" " * $vPadLeft) + $versionText + (" " * $vPadRight) + "║") -ForegroundColor Cyan
    Write-Host " ║                                                                                     ║" -ForegroundColor Cyan
    Write-Host " ╚═════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    if ($DryRun) {
        Write-Host "  ⚠️  DRY RUN MODE — no changes will be made" -ForegroundColor Yellow
        Write-Host ""
    }
}

function Write-StepHeader {
    param([string]$StepNumber, [string]$Title)
    Write-Host ""
    Write-Host ("━" * 60) -ForegroundColor Cyan
    Write-Host "  Step $StepNumber : $Title" -ForegroundColor Cyan
    Write-Host ("━" * 60) -ForegroundColor Cyan
}

Show-WelcomeBanner

Import-Module (Join-Path $PSScriptRoot 'CopilotHLS-Deployment.psm1') -Force

if ($PackageOnly) {
    $SkipProvision = $true
    $SkipInstall = $true
}

$repoRoot = Get-CopilotHlsRepositoryRoot

# ─────────────────────────────────────────────────────────────────────
# Step 1: Prerequisites Check
# ─────────────────────────────────────────────────────────────────────
Write-StepHeader "1" "Prerequisites"

$prereqsPassed = $true

if ($SkipPrerequisites) {
    Write-Host "  ⏭️  Skipped (--SkipPrerequisites)" -ForegroundColor Yellow
}
else {
    # PowerShell version
    $psVer = $PSVersionTable.PSVersion
    Write-Host "  ✅ PowerShell $psVer" -ForegroundColor Green

    # Check required CLI tools
    $requiredCommands = @('atk')
    if (-not $SkipInstall -and -not $PackageOnly) {
        $requiredCommands += 'teamsapp'
    }

    foreach ($cmd in $requiredCommands) {
        if (Get-Command -Name $cmd -ErrorAction SilentlyContinue) {
            Write-Host "  ✅ $cmd CLI" -ForegroundColor Green
        }
        else {
            Write-Host "  ❌ $cmd CLI — not found in PATH" -ForegroundColor Red
            $prereqsPassed = $false
        }
    }

    # Check Veeva scripts exist
    $veevaSetupScript = Join-Path $PSScriptRoot 'Setup-VeevaConnectors.ps1'
    $veevaOAuthScript = Join-Path $PSScriptRoot 'Configure-VeevaOAuth.ps1'
    if ((Test-Path $veevaSetupScript) -and (Test-Path $veevaOAuthScript)) {
        Write-Host "  ✅ Veeva connector scripts found" -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠️  Veeva connector scripts not found (optional)" -ForegroundColor Yellow
    }

    if (-not $prereqsPassed) {
        Write-Host ""
        Write-Host "  ❌ Prerequisites not met. Please resolve the issues above and try again." -ForegroundColor Red
        exit 1
    }
}

# ─────────────────────────────────────────────────────────────────────
# Step 2: M365 Tenant Authentication
# ─────────────────────────────────────────────────────────────────────
if (-not $PackageOnly) {
    Write-StepHeader "2" "M365 Tenant Authentication"

    try {
        $authCheck = & atk auth list 2>&1
        $authText = ($authCheck | Out-String).Trim()

        if ($authText -match "No account" -or $authText -match "not logged in") {
            Write-Host "  Launching M365 login..." -ForegroundColor Yellow
            if (-not $DryRun) {
                & atk auth login
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "  ❌ Authentication failed." -ForegroundColor Red
                    exit 1
                }
            }
            else {
                Write-Host "  [DRY RUN] Would launch atk auth login" -ForegroundColor Yellow
            }
        }
        Write-Host "  ✅ Authenticated to M365 tenant" -ForegroundColor Green
    }
    catch {
        if ($DryRun) {
            Write-Host "  [DRY RUN] Would authenticate to M365 tenant (atk not available)" -ForegroundColor Yellow
        }
        else {
            Write-Host "  ❌ Authentication error: $_" -ForegroundColor Red
            exit 1
        }
    }
}

# ─────────────────────────────────────────────────────────────────────
# Step 3: Agent Selection
# ─────────────────────────────────────────────────────────────────────
Write-StepHeader "3" "Agent Selection"

$allDefinitions = Get-CopilotHlsProjectDefinitions -RepositoryRoot $repoRoot

# Separate core agents (non-veeva, non-orchestrator) from veeva agents
$coreWorkers = $allDefinitions | Where-Object { $_.Category -eq 'core' }
$veevaAgents = $allDefinitions | Where-Object { $_.Category -eq 'veeva' }
$orchestrator = $allDefinitions | Where-Object { $_.Category -eq 'orchestrator' }

if ($NonInteractive) {
    # Default: all core workers + orchestrator, no Veeva
    $selectedProjects = @($coreWorkers) + @($orchestrator)
    $selectedVeeva = @()
    Write-Host "  Non-interactive mode: deploying all $($coreWorkers.Count) core agents + orchestrator" -ForegroundColor Yellow
}
else {
    Write-Host ""
    Write-Host "  How would you like to install the HLS Copilot agents?" -ForegroundColor White
    Write-Host ""
    Write-Host "    [1] Default        - Install all $($coreWorkers.Count) core agents + orchestrator (recommended)" -ForegroundColor White
    Write-Host "    [2] Customized     - Select which agents to install" -ForegroundColor White
    Write-Host ""

    do {
        $agentChoice = Read-Host "  Select an option (1 or 2)"
    } while ($agentChoice -ne '1' -and $agentChoice -ne '2')

    if ($agentChoice -eq '1') {
        $selectedWorkers = @($coreWorkers)
    }
    else {
        # Customized agent selection
        Write-Host ""
        Write-Host "  Available agents:" -ForegroundColor White
        Write-Host ""

        $workerList = @($coreWorkers)
        for ($i = 0; $i -lt $workerList.Count; $i++) {
            $dep = ''
            $name = $workerList[$i].Name -replace 'CopilotHLS-', ''
            # Show dependencies
            if ($workerList[$i].Name -eq 'CopilotHLS-RegCompliance') {
                $dep = ' (requires ProtocolGen)'
            }
            Write-Host "    [$($i + 1)] $name$dep" -ForegroundColor White
        }

        Write-Host ""
        Write-Host "  Enter agent numbers separated by commas (e.g., 1,3,5)" -ForegroundColor DarkGray
        Write-Host "  The orchestrator (CopilotHLS) is always included." -ForegroundColor DarkGray
        Write-Host ""

        $selection = Read-Host "  Select agents"
        $selectedIndices = $selection -split ',' | ForEach-Object { ($_.Trim() -as [int]) - 1 } | Where-Object { $_ -ge 0 -and $_ -lt $workerList.Count }

        $selectedWorkers = @()
        foreach ($idx in $selectedIndices) {
            $selectedWorkers += $workerList[$idx]
        }

        # Auto-resolve dependencies: RegCompliance needs ProtocolGen
        $selectedNames = $selectedWorkers | ForEach-Object { $_.Name }
        if ('CopilotHLS-RegCompliance' -in $selectedNames -and 'CopilotHLS-ProtocolGen' -notin $selectedNames) {
            $protocolGen = $workerList | Where-Object { $_.Name -eq 'CopilotHLS-ProtocolGen' }
            $selectedWorkers += $protocolGen
            Write-Host "  ℹ️  Auto-included ProtocolGen (required by RegCompliance)" -ForegroundColor DarkGray
        }
    }

    # Veeva agent selection
    Write-Host ""
    Write-Host ("━" * 60) -ForegroundColor DarkCyan
    Write-Host "  Veeva Connector Agents" -ForegroundColor DarkCyan
    Write-Host ("━" * 60) -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Veeva agents provide dedicated access to Veeva Vault content" -ForegroundColor White
    Write-Host "  via Microsoft Graph Connectors (PromoMats, QualityDocs, RIM)." -ForegroundColor White
    Write-Host "  These require Veeva Graph Connectors deployed in M365 Admin Center." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "    [1] Skip          - Don't install Veeva agents" -ForegroundColor White
    Write-Host "    [2] All           - Install all 3 Veeva agents" -ForegroundColor White
    Write-Host "    [3] Select        - Choose which Veeva agents to install" -ForegroundColor White
    Write-Host ""

    do {
        $veevaChoice = Read-Host "  Select an option (1, 2, or 3)"
    } while ($veevaChoice -ne '1' -and $veevaChoice -ne '2' -and $veevaChoice -ne '3')

    $selectedVeeva = @()

    if ($veevaChoice -eq '2') {
        $selectedVeeva = @($veevaAgents)
    }
    elseif ($veevaChoice -eq '3') {
        Write-Host ""
        $veevaList = @($veevaAgents)
        for ($i = 0; $i -lt $veevaList.Count; $i++) {
            $name = $veevaList[$i].Name -replace 'CopilotHLS-', ''
            Write-Host "    [$($i + 1)] $name" -ForegroundColor White
        }
        Write-Host ""
        $veevaSelection = Read-Host "  Select Veeva agents (e.g., 1,3)"
        $veevaIndices = $veevaSelection -split ',' | ForEach-Object { ($_.Trim() -as [int]) - 1 } | Where-Object { $_ -ge 0 -and $_ -lt $veevaList.Count }
        foreach ($idx in $veevaIndices) {
            $selectedVeeva += $veevaList[$idx]
        }
    }

    $selectedProjects = @($selectedWorkers) + @($selectedVeeva) + @($orchestrator)
}

# Sort by install order
$selectedProjects = $selectedProjects | Sort-Object InstallOrder

# Display selection summary
Write-Host ""
Write-Host "  Selected $($selectedProjects.Count) agent(s):" -ForegroundColor Green
foreach ($proj in $selectedProjects) {
    $displayName = $proj.Name -replace 'CopilotHLS-', ''
    if ($proj.Name -eq 'CopilotHLS') { $displayName = 'CopilotHLS (Orchestrator)' }
    if ($proj.Category -eq 'veeva') {
        Write-Host "    🏥 $displayName" -ForegroundColor Magenta
    }
    else {
        Write-Host "    ✅ $displayName" -ForegroundColor Green
    }
}

# ─────────────────────────────────────────────────────────────────────
# Step 4: Veeva Connector Setup (optional)
# ─────────────────────────────────────────────────────────────────────
$hasVeeva = ($selectedVeeva.Count -gt 0)

if ($hasVeeva -and -not $PackageOnly) {
    Write-StepHeader "4" "Veeva Connector Setup"

    Write-Host ""
    Write-Host "  Veeva agents require Graph Connectors deployed in M365 Admin Center." -ForegroundColor White
    Write-Host "  If you haven't set up the Entra ID app registrations yet, you can do so now." -ForegroundColor White
    Write-Host ""
    Write-Host "    [1] Skip          - Connectors are already configured" -ForegroundColor White
    Write-Host "    [2] Run Setup     - Create Entra ID app registrations (Setup-VeevaConnectors.ps1)" -ForegroundColor White
    Write-Host "    [3] Full Setup    - Create app registrations AND configure Vault OAuth" -ForegroundColor White
    Write-Host ""

    do {
        $veevaSetupChoice = Read-Host "  Select an option (1, 2, or 3)"
    } while ($veevaSetupChoice -ne '1' -and $veevaSetupChoice -ne '2' -and $veevaSetupChoice -ne '3')

    if ($veevaSetupChoice -ne '1') {
        $tenantId = Read-Host "  Enter your Entra Tenant ID"

        if ($veevaSetupChoice -eq '2' -or $veevaSetupChoice -eq '3') {
            Write-Host "  Running Setup-VeevaConnectors.ps1..." -ForegroundColor Yellow
            if (-not $DryRun) {
                & (Join-Path $PSScriptRoot 'Setup-VeevaConnectors.ps1') -TenantId $tenantId
            }
            else {
                Write-Host "  [DRY RUN] Would run Setup-VeevaConnectors.ps1 -TenantId $tenantId" -ForegroundColor Yellow
            }
        }

        if ($veevaSetupChoice -eq '3') {
            Write-Host ""
            Write-Host "  Configuring Veeva Vault OAuth..." -ForegroundColor Yellow
            $connectorAdminUpn = Read-Host "  Enter connector admin UPN (e.g., admin@contoso.com)"
            $vaultCred = Get-Credential -Message "Veeva Vault admin credentials"
            $promoMatsUrl = Read-Host "  Enter PromoMats Vault URL (e.g., https://promomats.veevavault.com)"
            $qualityDocsUrl = Read-Host "  Enter QualityDocs Vault URL"
            $rimUrl = Read-Host "  Enter RIM Vault URL"

            if (-not $DryRun) {
                & (Join-Path $PSScriptRoot 'Configure-VeevaOAuth.ps1') `
                    -TenantId $tenantId `
                    -ConnectorAdminUpn $connectorAdminUpn `
                    -VaultCredential $vaultCred `
                    -PromoMatsVaultUrl $promoMatsUrl `
                    -QualityDocsVaultUrl $qualityDocsUrl `
                    -RimVaultUrl $rimUrl
            }
            else {
                Write-Host "  [DRY RUN] Would run Configure-VeevaOAuth.ps1" -ForegroundColor Yellow
            }
        }

        Write-Host ""
        Write-Host "  ✅ Veeva connector setup complete" -ForegroundColor Green
        Write-Host "  📋 Remember to deploy connectors in M365 Admin Center (see docs/veeva-admin-center-setup.md)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "  ⏭️  Skipped — using existing connector configuration" -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────────────────────────────
# Step 5: Agent Provisioning
# ─────────────────────────────────────────────────────────────────────
$provisionStep = if ($hasVeeva -and -not $PackageOnly) { "5" } else { "4" }
Write-StepHeader $provisionStep "Agent Provisioning"

Confirm-CopilotHlsCommands -Commands @('atk')

$results = New-Object System.Collections.Generic.List[object]
$succeeded = 0
$failed = 0
$totalAgents = $selectedProjects.Count
$currentAgent = 0

foreach ($projectDefinition in $selectedProjects) {
    $currentAgent++
    $displayName = $projectDefinition.Name -replace 'CopilotHLS-', ''
    if ($projectDefinition.Name -eq 'CopilotHLS') { $displayName = 'CopilotHLS (Orchestrator)' }

    Write-Host ""
    Write-Host "  [$currentAgent/$totalAgents] $displayName" -ForegroundColor White

    try {
        # Sync worker title IDs into orchestrator before provisioning it
        if ($projectDefinition.Name -eq 'CopilotHLS') {
            $titleUpdates = Update-CopilotHlsWorkerTitleIds -Environment $Environment -RepositoryRoot $repoRoot
            if ($titleUpdates.Count -gt 0) {
                Write-Host "    ↳ Synchronized $($titleUpdates.Count) worker title ID(s)" -ForegroundColor DarkGray
            }
        }

        if (-not $SkipProvision) {
            if (-not $ReuseExistingIds) {
                Clear-CopilotHlsGeneratedEnvValues -ProjectDefinition $projectDefinition -Environment $Environment
            }

            if ($DryRun) {
                Write-Host "    [DRY RUN] Would run atk provision" -ForegroundColor Yellow
            }
            else {
                Write-Host "    ↳ Running atk provision..." -ForegroundColor DarkGray
                Invoke-CopilotHlsCli -Command 'atk' -Arguments @(
                    'provision',
                    '-i', 'false',
                    '--env', $Environment,
                    '--folder', $projectDefinition.RootPath
                ) -WorkingDirectory $repoRoot
            }
        }
        else {
            if ($DryRun) {
                Write-Host "    [DRY RUN] Would run atk package" -ForegroundColor Yellow
            }
            else {
                Write-Host "    ↳ Running atk package..." -ForegroundColor DarkGray
                Invoke-CopilotHlsCli -Command 'atk' -Arguments @(
                    'package',
                    '--env', $Environment,
                    '--folder', $projectDefinition.RootPath
                ) -WorkingDirectory $repoRoot
            }
        }

        if (-not $DryRun) {
            $packagePath = Get-CopilotHlsPackagePath -ProjectDefinition $projectDefinition -Environment $Environment
            if (-not (Test-Path -LiteralPath $packagePath)) {
                throw "Expected package was not created: $packagePath"
            }

            if (-not $SkipInstall) {
                Write-Host "    ↳ Sideloading package..." -ForegroundColor DarkGray
                Invoke-CopilotHlsCli -Command 'teamsapp' -Arguments @(
                    'install',
                    '--file-path', $packagePath,
                    '--scope', $Scope
                ) -WorkingDirectory $repoRoot
            }
        }

        $envPath = Get-CopilotHlsEnvPath -ProjectDefinition $projectDefinition -Environment $Environment
        $envValues = Get-CopilotHlsEnvValues -Path $envPath
        $results.Add([pscustomobject]@{
            Agent       = $displayName
            Status      = '✅'
            TeamsAppId  = $envValues['TEAMS_APP_ID']
            M365TitleId = $envValues['M365_TITLE_ID']
            ShareLink   = $envValues['SHARE_LINK']
        })
        $succeeded++
        Write-Host "    ✅ $displayName deployed" -ForegroundColor Green
    }
    catch {
        $results.Add([pscustomobject]@{
            Agent       = $displayName
            Status      = '❌'
            TeamsAppId  = ''
            M365TitleId = ''
            ShareLink   = ''
        })
        $failed++
        Write-Host "    ❌ $displayName failed: $_" -ForegroundColor Red
    }
}

# ─────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────
$summaryStep = ([int]$provisionStep + 1).ToString()
Write-StepHeader $summaryStep "Deployment Summary"

$elapsed = (Get-Date) - $startTime
$elapsedFormatted = "{0:mm\:ss}" -f $elapsed

Write-Host ""
if ($failed -eq 0) {
    Write-Host "  ✅ All $succeeded agent(s) deployed successfully!" -ForegroundColor Green
}
else {
    Write-Host "  ⚠️  $succeeded succeeded, $failed failed" -ForegroundColor Yellow
}

Write-Host ""
$results | Format-Table -Property Agent, Status, M365TitleId, ShareLink -AutoSize

if ($DryRun) {
    Write-Host "  ⚠️  DRY RUN — no actual changes were made" -ForegroundColor Yellow
}

Write-Host "  ⏱️  Total time: $elapsedFormatted" -ForegroundColor DarkGray

if ($hasVeeva) {
    Write-Host ""
    Write-Host "  📋 Veeva Reminders:" -ForegroundColor Magenta
    Write-Host "     • Ensure Veeva Graph Connectors are deployed in M365 Admin Center" -ForegroundColor DarkGray
    Write-Host "     • See docs/veeva-admin-center-setup.md for step-by-step instructions" -ForegroundColor DarkGray
}

Write-Host ""
