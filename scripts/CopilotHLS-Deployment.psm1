Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Get-CopilotHlsRepositoryRoot {
    param(
        [string]$RepositoryRoot
    )

    if ($RepositoryRoot) {
        return (Resolve-Path -LiteralPath $RepositoryRoot).Path
    }

    return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
}

function Get-CopilotHlsProjectDefinitions {
    param(
        [string]$RepositoryRoot
    )

    $root = Get-CopilotHlsRepositoryRoot -RepositoryRoot $RepositoryRoot

    return @(
        [pscustomobject]@{
            Name                 = 'CopilotHLS-LitReview'
            RootPath             = Join-Path $root 'CopilotHLS-LitReview'
            RootWorkerTitleEnvKey = 'LITREVIEW_TITLE_ID'
            InstallOrder         = 10
            UninstallOrder       = 20
            Category             = 'core'
        },
        [pscustomobject]@{
            Name                 = 'CopilotHLS-BioAnalysis'
            RootPath             = Join-Path $root 'CopilotHLS-BioAnalysis'
            RootWorkerTitleEnvKey = 'BIOANALYSIS_TITLE_ID'
            InstallOrder         = 20
            UninstallOrder       = 30
            Category             = 'core'
        },
        [pscustomobject]@{
            Name                 = 'CopilotHLS-RegCompliance'
            RootPath             = Join-Path $root 'CopilotHLS-RegCompliance'
            RootWorkerTitleEnvKey = 'REGCOMPLIANCE_TITLE_ID'
            InstallOrder         = 30
            UninstallOrder       = 40
            Category             = 'core'
        },
        [pscustomobject]@{
            Name                 = 'CopilotHLS-ProtocolGen'
            RootPath             = Join-Path $root 'CopilotHLS-ProtocolGen'
            RootWorkerTitleEnvKey = 'PROTOCOLGEN_TITLE_ID'
            InstallOrder         = 40
            UninstallOrder       = 50
            Category             = 'core'
        },
        [pscustomobject]@{
            Name                 = 'CopilotHLS-SciKnowledge'
            RootPath             = Join-Path $root 'CopilotHLS-SciKnowledge'
            RootWorkerTitleEnvKey = 'SCIKNOWLEDGE_TITLE_ID'
            InstallOrder         = 50
            UninstallOrder       = 60
            Category             = 'core'
        },
        [pscustomobject]@{
            Name                 = 'CopilotHLS-VeevaPromoMats'
            RootPath             = Join-Path $root 'CopilotHLS-VeevaPromoMats'
            RootWorkerTitleEnvKey = 'VEEVA_PROMOMATS_TITLE_ID'
            InstallOrder         = 55
            UninstallOrder       = 55
            Category             = 'veeva'
        },
        [pscustomobject]@{
            Name                 = 'CopilotHLS-VeevaQualityDocs'
            RootPath             = Join-Path $root 'CopilotHLS-VeevaQualityDocs'
            RootWorkerTitleEnvKey = 'VEEVA_QUALITYDOCS_TITLE_ID'
            InstallOrder         = 60
            UninstallOrder       = 60
            Category             = 'veeva'
        },
        [pscustomobject]@{
            Name                 = 'CopilotHLS-VeevaRIM'
            RootPath             = Join-Path $root 'CopilotHLS-VeevaRIM'
            RootWorkerTitleEnvKey = 'VEEVA_RIM_TITLE_ID'
            InstallOrder         = 65
            UninstallOrder       = 65
            Category             = 'veeva'
        },
        [pscustomobject]@{
            Name                 = 'CopilotHLS'
            RootPath             = $root
            RootWorkerTitleEnvKey = $null
            InstallOrder         = 90
            UninstallOrder       = 10
            Category             = 'orchestrator'
        }
    )
}

function Resolve-CopilotHlsProjects {
    param(
        [string[]]$Project,

        [ValidateSet('Install', 'Uninstall', 'Any')]
        [string]$Operation = 'Any',

        [string]$RepositoryRoot
    )

    $definitions = Get-CopilotHlsProjectDefinitions -RepositoryRoot $RepositoryRoot
    $selected = @()

    if (-not $Project -or $Project.Count -eq 0 -or ($Project.Count -eq 1 -and $Project[0] -ieq 'All')) {
        $selected = $definitions
    }
    else {
        foreach ($name in $Project) {
            $match = $definitions | Where-Object { $_.Name -ieq $name }
            if (-not $match) {
                throw "Unknown project '$name'. Valid values are: $($definitions.Name -join ', ')."
            }

            $selected += $match
        }
    }

    $selected = $selected | Sort-Object -Property Name -Unique

    switch ($Operation) {
        'Install' {
            return @($selected | Sort-Object InstallOrder, Name)
        }
        'Uninstall' {
            return @($selected | Sort-Object UninstallOrder, Name)
        }
        default {
            return @($selected)
        }
    }
}

function Confirm-CopilotHlsCommands {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Commands
    )

    foreach ($name in $Commands) {
        if (-not (Get-Command -Name $name -ErrorAction SilentlyContinue)) {
            throw "Required command '$name' was not found in PATH."
        }
    }
}

function Get-CopilotHlsEnvPath {
    param(
        [Parameter(Mandatory = $true)]
        $ProjectDefinition,

        [Parameter(Mandatory = $true)]
        [ValidateSet('dev', 'local')]
        [string]$Environment
    )

    return Join-Path $ProjectDefinition.RootPath (Join-Path 'env' ".env.$Environment")
}

function Get-CopilotHlsEnvValues {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Environment file not found: $Path"
    }

    $values = [ordered]@{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $trimmed = $line.Trim()
        if ($trimmed.StartsWith('#')) {
            continue
        }

        $parts = $line -split '=', 2
        if ($parts.Count -eq 2) {
            $values[$parts[0]] = $parts[1]
        }
        elseif ($parts[0]) {
            $values[$parts[0]] = ''
        }
    }

    return $values
}

function Set-CopilotHlsEnvValues {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Values
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Environment file not found: $Path"
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in Get-Content -LiteralPath $Path) {
        $lines.Add($line)
    }

    foreach ($entry in $Values.GetEnumerator()) {
        $key = [string]$entry.Key
        $value = [string]$entry.Value
        $pattern = '^' + [regex]::Escape($key) + '='
        $updated = $false

        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match $pattern) {
                $lines[$index] = "$key=$value"
                $updated = $true
                break
            }
        }

        if (-not $updated) {
            $lines.Add("$key=$value")
        }
    }

    Set-Content -LiteralPath $Path -Value $lines -Encoding utf8
}

function Clear-CopilotHlsGeneratedEnvValues {
    param(
        [Parameter(Mandatory = $true)]
        $ProjectDefinition,

        [Parameter(Mandatory = $true)]
        [ValidateSet('dev', 'local')]
        [string]$Environment
    )

    $envPath = Get-CopilotHlsEnvPath -ProjectDefinition $ProjectDefinition -Environment $Environment
    Set-CopilotHlsEnvValues -Path $envPath -Values ([ordered]@{
        TEAMS_APP_ID            = ''
        M365_TITLE_ID           = ''
        M365_APP_ID             = ''
        SHARE_LINK              = ''
        TEAMS_APP_PUBLISHED_APP_ID = ''
    })
}

function Update-CopilotHlsWorkerTitleIds {
    param(
        [ValidateSet('dev', 'local')]
        [string]$Environment = 'dev',

        [string]$RepositoryRoot
    )

    $definitions = Get-CopilotHlsProjectDefinitions -RepositoryRoot $RepositoryRoot
    $rootProject = $definitions | Where-Object { $_.Name -eq 'CopilotHLS' }
    $updates = [ordered]@{}

    foreach ($worker in $definitions | Where-Object { $_.RootWorkerTitleEnvKey }) {
        $workerEnvPath = Get-CopilotHlsEnvPath -ProjectDefinition $worker -Environment $Environment
        if (-not (Test-Path -LiteralPath $workerEnvPath)) {
            continue
        }

        $workerEnv = Get-CopilotHlsEnvValues -Path $workerEnvPath
        $workerTitleId = $workerEnv['M365_TITLE_ID']
        if ([string]::IsNullOrWhiteSpace($workerTitleId)) {
            continue
        }

        $updates[$worker.RootWorkerTitleEnvKey] = $workerTitleId
    }

    if ($updates.Count -gt 0) {
        $rootEnvPath = Get-CopilotHlsEnvPath -ProjectDefinition $rootProject -Environment $Environment
        Set-CopilotHlsEnvValues -Path $rootEnvPath -Values $updates
    }

    return $updates
}

function Get-CopilotHlsPackagePath {
    param(
        [Parameter(Mandatory = $true)]
        $ProjectDefinition,

        [ValidateSet('dev', 'local')]
        [string]$Environment = 'dev'
    )

    return Join-Path $ProjectDefinition.RootPath (Join-Path 'appPackage\build' "appPackage.$Environment.zip")
}

function Invoke-CopilotHlsCli {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory
    )

    $commandInfo = Get-Command -Name $Command -ErrorAction Stop

    Push-Location -LiteralPath $WorkingDirectory
    try {
        & $commandInfo.Source @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "$Command failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

Export-ModuleMember -Function `
    Clear-CopilotHlsGeneratedEnvValues, `
    Confirm-CopilotHlsCommands, `
    Get-CopilotHlsEnvPath, `
    Get-CopilotHlsPackagePath, `
    Get-CopilotHlsProjectDefinitions, `
    Get-CopilotHlsRepositoryRoot, `
    Get-CopilotHlsEnvValues, `
    Invoke-CopilotHlsCli, `
    Resolve-CopilotHlsProjects, `
    Set-CopilotHlsEnvValues, `
    Update-CopilotHlsWorkerTitleIds
