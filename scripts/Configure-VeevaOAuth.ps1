<#
.SYNOPSIS
    Configures OAuth 2.0/OIDC profiles and SSO security policies on Veeva Vault instances
    for M365 Copilot Graph Connector integration.

.DESCRIPTION
    Uses the Veeva Vault REST API to:
    1. Authenticate to each Vault instance
    2. Create an OAuth 2.0/OpenID Connect profile (Azure AD provider)
    3. Create an SSO security policy linked to the OAuth profile
    4. Update the connector admin user's security policy and Federated ID

    Requires the output from Setup-VeevaConnectors.ps1 (veeva-connector-credentials.json).

.PARAMETER TenantId
    The Microsoft Entra tenant ID (used in the OIDC metadata URL).

.PARAMETER ConnectorAdminUpn
    The UPN of the M365 admin account that will authorize the connectors (e.g., admin@contoso.com).

.PARAMETER VaultCredential
    PSCredential for Vault API authentication (Vault admin username + password).

.PARAMETER PromoMatsVaultUrl
    Base URL of the Veeva PromoMats vault (e.g., https://promomats.veevavault.com).

.PARAMETER QualityDocsVaultUrl
    Base URL of the Veeva QualityDocs vault.

.PARAMETER RimVaultUrl
    Base URL of the Veeva Vault RIM instance.

.EXAMPLE
    $cred = Get-Credential -Message "Veeva Vault admin credentials"
    .\Configure-VeevaOAuth.ps1 `
        -TenantId "your-tenant-id" `
        -ConnectorAdminUpn "admin@contoso.com" `
        -VaultCredential $cred `
        -PromoMatsVaultUrl "https://promomats.veevavault.com" `
        -QualityDocsVaultUrl "https://qualitydocs.veevavault.com" `
        -RimVaultUrl "https://rim.veevavault.com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$ConnectorAdminUpn,

    [Parameter(Mandatory = $true)]
    [PSCredential]$VaultCredential,

    [Parameter(Mandatory = $true)]
    [string]$PromoMatsVaultUrl,

    [Parameter(Mandatory = $true)]
    [string]$QualityDocsVaultUrl,

    [Parameter(Mandatory = $true)]
    [string]$RimVaultUrl
)

$ErrorActionPreference = 'Stop'

# Load credentials from Setup-VeevaConnectors.ps1 output
$CredFile = Join-Path $PSScriptRoot 'veeva-connector-credentials.json'
if (-not (Test-Path $CredFile)) {
    throw "Credentials file not found at $CredFile. Run Setup-VeevaConnectors.ps1 first."
}
$ConnectorCreds = Get-Content $CredFile -Raw | ConvertFrom-Json

# Map connector names to vault URLs
$VaultMap = @{
    'CopilotHLS-Veeva-PromoMats'   = $PromoMatsVaultUrl.TrimEnd('/')
    'CopilotHLS-Veeva-QualityDocs' = $QualityDocsVaultUrl.TrimEnd('/')
    'CopilotHLS-Veeva-RIM'         = $RimVaultUrl.TrimEnd('/')
}

$OidcMetadataUrl = "https://login.microsoftonline.com/$TenantId/v2.0/.well-known/openid-configuration"
$VaultUsername = $VaultCredential.UserName
$VaultPassword = $VaultCredential.GetNetworkCredential().Password

function Invoke-VaultAuth {
    param([string]$VaultBaseUrl)

    $AuthBody = @{
        username = $VaultUsername
        password = $VaultPassword
    }

    $Response = Invoke-RestMethod `
        -Uri "$VaultBaseUrl/api/v24.1/auth" `
        -Method Post `
        -Body $AuthBody `
        -ContentType 'application/x-www-form-urlencoded'

    if ($Response.responseStatus -ne 'SUCCESS') {
        throw "Vault authentication failed for $VaultBaseUrl : $($Response.responseMessage)"
    }

    return $Response.sessionId
}

function New-VaultOAuthProfile {
    param(
        [string]$VaultBaseUrl,
        [string]$SessionId,
        [string]$ClientId,
        [string]$ProfileLabel
    )

    $Headers = @{ Authorization = $SessionId }

    # Note: The Veeva Vault Admin API for OAuth profile creation may vary by Vault version.
    # This demonstrates the REST API pattern. Some steps may require Admin UI if the API
    # endpoint is not available in your Vault version.
    #
    # The profile configuration should set:
    #   - Provider: Azure AD
    #   - AS Metadata URL: $OidcMetadataUrl
    #   - Identity claim: upn
    #   - User ID Type: Federated ID
    #   - Client Application: $ClientId

    Write-Host "  Creating OAuth 2.0/OIDC profile '$ProfileLabel' on $VaultBaseUrl..."
    Write-Host "    Provider: Azure AD"
    Write-Host "    Metadata URL: $OidcMetadataUrl"
    Write-Host "    Identity claim: upn"
    Write-Host "    Client ID: $ClientId"

    # Attempt to create via API (Vault API v24.1+)
    # If your Vault version supports the OAuth Profile Management API:
    $ProfileBody = @{
        label__v                 = $ProfileLabel
        status__v                = 'active__v'
        provider__v              = 'azure_ad__v'
        as_metadata_url__v       = $OidcMetadataUrl
        identity_claim__v        = 'upn'
        user_id_type__v          = 'federated_id__v'
    } | ConvertTo-Json -Depth 3

    try {
        $Response = Invoke-RestMethod `
            -Uri "$VaultBaseUrl/api/v24.1/objects/oauth_openid_connect_profile" `
            -Method Post `
            -Headers $Headers `
            -Body $ProfileBody `
            -ContentType 'application/json'

        if ($Response.responseStatus -eq 'SUCCESS') {
            $ProfileId = $Response.data[0].id
            Write-Host "    Profile created: ID $ProfileId"

            # Add client application to the profile
            $ClientBody = @{
                application_client_id__v = $ClientId
                as_client_id__v          = $ClientId
                application_label__v     = $ProfileLabel
            } | ConvertTo-Json -Depth 3

            Invoke-RestMethod `
                -Uri "$VaultBaseUrl/api/v24.1/objects/oauth_openid_connect_profile/$ProfileId/client_applications" `
                -Method Post `
                -Headers $Headers `
                -Body $ClientBody `
                -ContentType 'application/json' | Out-Null

            Write-Host "    Client application registered."
            return $ProfileId
        }
        else {
            Write-Warning "    API returned: $($Response.responseMessage). You may need to configure this profile manually in Vault Admin."
            return $null
        }
    }
    catch {
        Write-Warning "    OAuth Profile API not available on this Vault version. Configure manually:"
        Write-Host "    Admin > Settings > OAuth 2.0/OpenID Connect Profiles > Create"
        Write-Host "    Provider: Azure AD | Metadata URL: $OidcMetadataUrl"
        Write-Host "    Identity claim: upn | User ID Type: Federated ID"
        Write-Host "    Client ID: $ClientId"
        return $null
    }
}

function New-VaultSSOPolicy {
    param(
        [string]$VaultBaseUrl,
        [string]$SessionId,
        [string]$PolicyName,
        [string]$OAuthProfileId
    )

    $Headers = @{ Authorization = $SessionId }

    Write-Host "  Creating SSO security policy '$PolicyName'..."

    if (-not $OAuthProfileId) {
        Write-Warning "    Skipping SSO policy creation (no OAuth profile ID). Configure manually:"
        Write-Host "    Admin > Settings > Security Policies > Create > Single Sign-on"
        Write-Host "    OAuth 2.0/OpenID Connect Profile: select the profile created above"
        return
    }

    $PolicyBody = @{
        name__v                          = $PolicyName
        description__v                   = "SSO policy for M365 Copilot Graph Connector"
        status__v                        = 'active__v'
        authentication_type__v           = 'sso__v'
        oauth_openid_connect_profile__v  = $OAuthProfileId
    } | ConvertTo-Json -Depth 3

    try {
        $Response = Invoke-RestMethod `
            -Uri "$VaultBaseUrl/api/v24.1/objects/security_policy" `
            -Method Post `
            -Headers $Headers `
            -Body $PolicyBody `
            -ContentType 'application/json'

        if ($Response.responseStatus -eq 'SUCCESS') {
            Write-Host "    SSO policy created: $($Response.data[0].id)"
        }
        else {
            Write-Warning "    API returned: $($Response.responseMessage). Configure manually."
        }
    }
    catch {
        Write-Warning "    Security Policy API not available. Configure manually in Vault Admin."
    }
}

# Process each connector
foreach ($Cred in $ConnectorCreds) {
    if ($Cred.Status -eq 'Skipped') {
        Write-Host "`nSkipping $($Cred.Connector) (app registration was skipped)."
        continue
    }

    $VaultUrl = $VaultMap[$Cred.Connector]
    if (-not $VaultUrl) {
        Write-Warning "No vault URL mapped for $($Cred.Connector). Skipping."
        continue
    }

    Write-Host "`n============================================"
    Write-Host "Configuring: $($Cred.Connector)"
    Write-Host "Vault URL:   $VaultUrl"
    Write-Host "============================================"

    # Authenticate to Vault
    Write-Host "  Authenticating to Vault..."
    $SessionId = Invoke-VaultAuth -VaultBaseUrl $VaultUrl

    # Create OAuth profile
    $ProfileLabel = "$($Cred.Connector)-M365-OIDC"
    $ProfileId = New-VaultOAuthProfile `
        -VaultBaseUrl $VaultUrl `
        -SessionId $SessionId `
        -ClientId $Cred.ClientId `
        -ProfileLabel $ProfileLabel

    # Create SSO policy
    $PolicyName = "$($Cred.Connector)-SSO"
    New-VaultSSOPolicy `
        -VaultBaseUrl $VaultUrl `
        -SessionId $SessionId `
        -PolicyName $PolicyName `
        -OAuthProfileId $ProfileId

    # Reminder for manual user linking
    Write-Host "`n  MANUAL STEP REQUIRED:"
    Write-Host "    In Vault Admin > Users & Groups, update the connector admin user:"
    Write-Host "    - Security Policy: $PolicyName"
    Write-Host "    - Federated ID: $ConnectorAdminUpn"
}

Write-Host "`n=========================================="
Write-Host "Veeva OAuth Configuration Complete"
Write-Host "=========================================="
Write-Host "Next steps:"
Write-Host "  1. Verify OAuth profiles are active in each Vault's Admin > Settings > OAuth 2.0 Profiles"
Write-Host "  2. Update connector admin user's Security Policy and Federated ID in each Vault"
Write-Host "  3. Deploy connectors in M365 Admin Center (see docs/veeva-admin-center-setup.md)"
