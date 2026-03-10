# CopilotHLS

CopilotHLS is a Microsoft 365 Copilot multi-agent solution for regulated life sciences teams. The repository now contains a primary orchestration agent plus five specialist worker agents, along with packaging, deployment, and removal scripts for rapid testing-environment rollout.

## Solution architecture

| Project | Role | Grounding and actions |
| --- | --- | --- |
| `CopilotHLS` | Primary orchestrator that triages requests and routes to specialists | SharePoint, Graph connectors, email, PubMed MCP, ClinicalTrials MCP, connected agents |
| `CopilotHLS-LitReview` | Biomedical literature review specialist | PubMed MCP, Semantic Scholar MCP, SharePoint, Code Interpreter |
| `CopilotHLS-BioAnalysis` | Bioinformatics reference and lightweight assay analysis specialist | NCBI MCP, SharePoint, Code Interpreter |
| `CopilotHLS-RegCompliance` | Regulatory and compliance specialist | openFDA MCP, ClinicalTrials MCP, SharePoint, Graph connectors, email |
| `CopilotHLS-ProtocolGen` | Protocol and SOP drafting specialist | SharePoint, Graph connectors, email |
| `CopilotHLS-SciKnowledge` | Enterprise knowledge synthesis specialist | Databricks MCP, Snowflake MCP, SharePoint, Graph connectors, Code Interpreter |

The root agent is wired for connected-agent routing through `worker_agents`. The install script provisions worker agents first, reads their generated `M365_TITLE_ID` values, and then updates the root environment file before provisioning the orchestrator.

## Repository layout

```text
CopilotHLS\
|-- appPackage\                 Root orchestrator manifest, instructions, and MCP plugins
|-- CopilotHLS-LitReview\       Literature review worker project
|-- CopilotHLS-BioAnalysis\     Bioinformatics worker project
|-- CopilotHLS-RegCompliance\   Regulatory worker project
|-- CopilotHLS-ProtocolGen\     Protocol drafting worker project
|-- CopilotHLS-SciKnowledge\    Scientific knowledge worker project
|-- env\                        Root environment configuration
|-- scripts\
|   |-- CopilotHLS-Deployment.psm1
|   |-- Install-CopilotHLS.ps1
|   |-- Uninstall-CopilotHLS.ps1
|   |-- Setup-VeevaConnectors.ps1
|   `-- Configure-VeevaOAuth.ps1
`-- docs\                       Supporting documentation
```

Every project contains its own:

- `appPackage\manifest.json`
- `appPackage\declarativeAgent.json`
- `appPackage\instruction.txt`
- project-specific plugin manifests where applicable
- `m365agents.yml`
- `m365agents.local.yml`
- `env\.env.dev`
- `env\.env.local`

## Configuration checklist

Before provisioning beyond local packaging, replace the placeholder values in each project's environment files:

1. **Remote MCP endpoints**
   - `PUBMED_MCP_URL`
   - `CLINICALTRIALS_MCP_URL`
   - `SEMANTICSCHOLAR_MCP_URL`
   - `NCBI_MCP_URL`
   - `OPENFDA_MCP_URL`
   - `DATABRICKS_MCP_URL`
   - `SNOWFLAKE_MCP_URL`
2. **Connector and knowledge-source IDs**
   - `PROMOMATS_CONNECTION_ID`
   - `QUALITYDOCS_CONNECTION_ID`
   - `RIM_CONNECTION_ID`
3. **SharePoint and mailbox references**
   - `*_SITE_URL`
   - `*_EMAIL_SHARED_MAILBOX`
   - `*_EMAIL_FOLDER_ID`
4. **OAuth vault references for protected MCP servers**
   - `DATABRICKS_MCP_AUTH_REFERENCE_ID`
   - `SNOWFLAKE_MCP_AUTH_REFERENCE_ID`
5. **Developer metadata**
   - `developer`, `privacyUrl`, `termsOfUseUrl`, and related placeholder URLs in each `manifest.json`
   - `contact_email`, `legal_info_url`, and `privacy_policy_url` in each plugin manifest

## Rapid deployment and removal

### Prerequisites

- Microsoft 365 Agents Toolkit CLI installed (`atk`)
- Microsoft 365 sign-in available in the current shell/session
- Custom app upload enabled for the test tenant
- Microsoft 365 Copilot access for the deployment account
- Remote MCP endpoints reachable over HTTPS

### Install script

Use `scripts\Install-CopilotHLS.ps1` to provision, package, and optionally sideload the solution.

```powershell
# Provision every worker, sync worker title IDs into the root agent, then sideload all packages
.\scripts\Install-CopilotHLS.ps1

# Package all projects without provisioning or sideloading
.\scripts\Install-CopilotHLS.ps1 -PackageOnly

# Update an existing test deployment without clearing current IDs first
.\scripts\Install-CopilotHLS.ps1 -ReuseExistingIds

# Provision and sideload only a subset
.\scripts\Install-CopilotHLS.ps1 -Project CopilotHLS-LitReview, CopilotHLS-RegCompliance -Scope Personal

# Build packages from existing environment state without running provision
.\scripts\Install-CopilotHLS.ps1 -SkipProvision
```

Key behaviors:

- Workers are processed before the root orchestrator.
- Fresh installs clear the generated `TEAMS_APP_ID`, `M365_TITLE_ID`, `M365_APP_ID`, and `SHARE_LINK` fields before provisioning.
- If the root project is selected, worker `M365_TITLE_ID` values are synchronized into the root environment file before the orchestrator is provisioned or packaged.
- Sideloading uses `teamsapp install` against the generated `appPackage\build\appPackage.<env>.zip` artifact.

### Uninstall script

Use `scripts\Uninstall-CopilotHLS.ps1` to remove the deployed Microsoft 365 app resources for test environments.

```powershell
# Remove all installed CopilotHLS apps from the dev environment and clear generated IDs
.\scripts\Uninstall-CopilotHLS.ps1

# Remove only the root agent and leave generated IDs in place
.\scripts\Uninstall-CopilotHLS.ps1 -Project CopilotHLS -KeepGeneratedIds

# Also request cleanup of app registrations tracked by Agents Toolkit
.\scripts\Uninstall-CopilotHLS.ps1 -AlsoRemoveAppRegistrations
```

By default the uninstall script calls:

```text
teamsapp uninstall -i false --mode env --env <env> --folder <project> --options m365-app
```

If `-AlsoRemoveAppRegistrations` is supplied, the script expands the options to `m365-app,app-registration`.

## Validation and packaging

The repository packages successfully with `atk package` for all six projects. Current Agents Toolkit preview validation rejects `RemoteMCPServer` plugin manifests that otherwise package correctly, so the repo's `m365agents*.yml` workflows omit the `teamsApp/validateAppPackage` step.

Recommended preflight checks:

```powershell
atk package --env dev --folder .
atk package --env dev --folder .\CopilotHLS-LitReview
atk package --env dev --folder .\CopilotHLS-BioAnalysis
atk package --env dev --folder .\CopilotHLS-RegCompliance
atk package --env dev --folder .\CopilotHLS-ProtocolGen
atk package --env dev --folder .\CopilotHLS-SciKnowledge
```

## Veeva-related setup

The repo keeps the existing helper scripts for optional Veeva connector setup:

- `scripts\Setup-VeevaConnectors.ps1`
- `scripts\Configure-VeevaOAuth.ps1`
- `docs\veeva-admin-center-setup.md`

Those assets are used to bootstrap Entra app registrations and Veeva Vault OAuth/SSO configuration for connector-backed grounding scenarios.
