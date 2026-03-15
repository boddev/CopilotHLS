# Agent Communication Matrix

> 100% M365 Copilot native — all agents are declarative, no backend code required.

## Orchestrator Agent (Tier 3)

| Agent | Capabilities | MCP Data Sources | Agent Dependencies |
|---|---|---|---|
| **CopilotHLS Primary** | WebSearch, CodeInterpreter, OneDrive/SP, GraphConnectors, GraphicArt, People, Email | PubMed, ClinicalTrials.gov | LitReview, BioAnalysis, RegCompliance, ProtocolGen, SciKnowledge, VeevaPromoMats, VeevaQualityDocs, VeevaRIM |

## Specialist Agents (Tier 2)

| Agent | Capabilities | MCP Data Sources | Agent Dependencies |
|---|---|---|---|
| **LitReview** | WebSearch, OneDrive/SP, CodeInterpreter | PubMed, Semantic Scholar | *none* |
| **BioAnalysis** | WebSearch, OneDrive/SP, CodeInterpreter | NCBI Reference | *none* |
| **RegCompliance** | WebSearch, OneDrive/SP, GraphConnectors, CodeInterpreter, Email | openFDA, ClinicalTrials.gov | ProtocolGen |
| **ProtocolGen** | OneDrive/SP, GraphConnectors, Email | *none* | *none* |
| **SciKnowledge** | WebSearch, OneDrive/SP, GraphConnectors, CodeInterpreter | Databricks, Snowflake | *none* |
| **VeevaPromoMats** | GraphConnectors, OneDrive/SP, WebSearch, CodeInterpreter | *none (uses PromoMats Graph Connector)* | *none* |
| **VeevaQualityDocs** | GraphConnectors, OneDrive/SP, WebSearch, CodeInterpreter | *none (uses QualityDocs Graph Connector)* | *none* |
| **VeevaRIM** | GraphConnectors, OneDrive/SP, WebSearch, CodeInterpreter | *none (uses RIM Graph Connector)* | *none* |

## MCP Data Sources (Tier 0)

| MCP Connector | Used By |
|---|---|
| **PubMed** | CopilotHLS Primary, LitReview |
| **ClinicalTrials.gov** | CopilotHLS Primary, RegCompliance |
| **Semantic Scholar** | LitReview |
| **NCBI Reference** | BioAnalysis |
| **openFDA** | RegCompliance |
| **Databricks** | SciKnowledge |
| **Snowflake** | SciKnowledge |

## Veeva Graph Connectors

| Connector | Graph Connection ID | Used By | Content |
|---|---|---|---|
| **PromoMats** | PROMOMATS_CONNECTION_ID | VeevaPromoMats, CopilotHLS Primary | Marketing compliance materials, MLR review packages |
| **QualityDocs** | QUALITYDOCS_CONNECTION_ID | VeevaQualityDocs, ProtocolGen, SciKnowledge | SOPs, CAPAs, GxP quality documents |
| **Veeva RIM** | RIM_CONNECTION_ID | VeevaRIM, RegCompliance, SciKnowledge | Regulatory submissions, dossier tracking |

## Agent Routing

```
┌──────────────────────────────────────────────────────────────────────────┐
│                     CopilotHLS (Orchestrator)                            │
│  Routes to 8 specialist agents based on query type                       │
└──┬──────┬──────┬───────────┬──────────┬──────────┬──────┬──────┬────────┘
   │      │      │           │          │          │      │      │
   ▼      ▼      ▼           ▼          ▼          ▼      ▼      ▼
 Lit    Bio    Reg      Protocol   Sci      Veeva   Veeva  Veeva
Review Analysis Compliance  Gen    Knowledge PromoMats Quality RIM
                    │                              Docs
                    ▼
               ProtocolGen
```

- RegCompliance can hand off protocol-drafting tasks to ProtocolGen.
- Veeva agents access Veeva Vault data via Microsoft Graph Connectors (not MCP).
- All 8 specialist agents are orchestrated by the CopilotHLS Primary agent.

## Data Source Priority

All agents follow this priority order:
1. **MCP data connectors & plugins** — ALWAYS try these first
2. **Veeva Graph Connectors & SharePoint** — Enterprise grounded content
3. **WebSearch fallback** — LAST RESORT only, after grounded sources have been tried

## WebSearch Grounded Sites

| Agent | Allowed Sites |
|---|---|
| **CopilotHLS Primary** | pubmed.ncbi.nlm.nih.gov, scholar.google.com, clinicaltrials.gov |
| **LitReview** | pubmed.ncbi.nlm.nih.gov, scholar.google.com, biorxiv.org, medrxiv.org |
| **BioAnalysis** | ncbi.nlm.nih.gov, uniprot.org, ensembl.org |
| **RegCompliance** | fda.gov, ema.europa.eu, ich.org |
| **SciKnowledge** | learn.microsoft.com, pubmed.ncbi.nlm.nih.gov |
| **VeevaPromoMats** | *(general — regulatory marketing sites)* |
| **VeevaQualityDocs** | *(general — GxP compliance sites)* |
| **VeevaRIM** | *(general — regulatory authority sites)* |
