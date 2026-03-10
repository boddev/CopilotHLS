<#
.SYNOPSIS
    Creates Entra ID app registrations for Veeva Vault Graph Connectors (PromoMats, QualityDocs, RIM).

.DESCRIPTION
    Registers 3 Microsoft Entra ID applications with the correct redirect URIs and client secrets
    required by the Veeva Vault M365 Copilot connectors. Outputs the client IDs and secrets needed
    for both the Veeva Vault OAuth configuration and the M365 Admin Center connector deployment.

.PARAMETER TenantId
    The Microsoft Entra tenant ID.

.PARAMETER Environment
    Target environment: 'Enterprise' (default) or 'Government' (GCC).

.EXAMPLE
    .\Setup-VeevaConnectors.ps1 -TenantId "your-tenant-id"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Enterprise', 'Government')]
    [string]$Environment = 'Enterprise'
)

$ErrorActionPreference = 'Stop'

# Redirect URI based on environment
$RedirectUri = switch ($Environment) {
    'Enterprise'  { 'https://gcs.office.com/v1.0/admin/oauth/callback' }
    'Government'  { 'https://gcsgcc.office.com/v1.0/admin/oauth/callback' }
}

# Connector definitions
$Connectors = @(
    @{ Name = 'CopilotHLS-Veeva-PromoMats';   DisplayName = 'Veeva PromoMats Connector for CopilotHLS' }
    @{ Name = 'CopilotHLS-Veeva-QualityDocs'; DisplayName = 'Veeva QualityDocs Connector for CopilotHLS' }
    @{ Name = 'CopilotHLS-Veeva-RIM';         DisplayName = 'Veeva Vault RIM Connector for CopilotHLS' }
)

# Ensure Microsoft.Graph module is available
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Applications)) {
    Write-Host "Installing Microsoft.Graph.Applications module..."
    Install-Module Microsoft.Graph.Applications -Scope CurrentUser -Force
}

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph for tenant $TenantId..."
Connect-MgGraph -TenantId $TenantId -Scopes 'Application.ReadWrite.All' -NoWelcome

$Results = @()

foreach ($Connector in $Connectors) {
    Write-Host "`nCreating app registration: $($Connector.DisplayName)..."

    # Check if app already exists
    $ExistingApp = Get-MgApplication -Filter "displayName eq '$($Connector.Name)'" -ErrorAction SilentlyContinue
    if ($ExistingApp) {
        Write-Warning "App '$($Connector.Name)' already exists (AppId: $($ExistingApp.AppId)). Skipping creation."
        $Results += [PSCustomObject]@{
            Connector = $Connector.Name
            ClientId  = $ExistingApp.AppId
            Secret    = '(already exists - retrieve from Azure Portal)'
            Status    = 'Skipped'
        }
        continue
    }

    # Create the application
    $AppParams = @{
        DisplayName    = $Connector.Name
        Description    = $Connector.DisplayName
        SignInAudience = 'AzureADMyOrg'
        Web            = @{
            RedirectUris = @($RedirectUri)
        }
    }

    $App = New-MgApplication @AppParams

    # Create a client secret (2-year expiry)
    $SecretParams = @{
        PasswordCredential = @{
            DisplayName = "$($Connector.Name)-secret"
            EndDateTime = (Get-Date).AddYears(2)
        }
    }

    $Secret = Add-MgApplicationPassword -ApplicationId $App.Id -BodyParameter $SecretParams

    Write-Host "  App ID:     $($App.AppId)"
    Write-Host "  Object ID:  $($App.Id)"
    Write-Host "  Secret:     $($Secret.SecretText)"
    Write-Warning "  Store the secret securely — it cannot be retrieved again."

    $Results += [PSCustomObject]@{
        Connector = $Connector.Name
        ClientId  = $App.AppId
        ObjectId  = $App.Id
        Secret    = $Secret.SecretText
        Status    = 'Created'
    }
}

# Output summary
Write-Host "`n=========================================="
Write-Host "Veeva Connector App Registrations Summary"
Write-Host "=========================================="
$Results | Format-Table -AutoSize

# Export to JSON for use by Configure-VeevaOAuth.ps1
$OutputPath = Join-Path $PSScriptRoot 'veeva-connector-credentials.json'
$Results | Select-Object Connector, ClientId, Secret, Status |
    ConvertTo-Json -Depth 3 |
    Set-Content -Path $OutputPath -Encoding UTF8

Write-Host "`nCredentials exported to: $OutputPath"
Write-Warning "This file contains secrets. Add it to .gitignore and store securely."

# Disconnect
Disconnect-MgGraph | Out-Null
Write-Host "Done."
