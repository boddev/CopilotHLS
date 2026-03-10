# Agent Communication Matrix

## Orchestrator Agent (Tier 3)

| Agent | Capabilities | MCP Data Sources | Agent Dependencies |
|---|---|---|---|
| **CopilotHLS Primary** | WebSearch, CodeInterpreter, OneDrive/SP, GraphConnectors, GraphicArt, People, Email | PubMed, ClinicalTrials.gov | LitReview, BioAnalysis, RegCompliance, ProtocolGen, SciKnowledge |

## Specialist Agents (Tier 2)

| Agent | Capabilities | MCP Data Sources | Agent Dependencies |
|---|---|---|---|
| **LitReview** | WebSearch, OneDrive/SP, CodeInterpreter | PubMed, Semantic Scholar | *none* |
| **BioAnalysis** | WebSearch, OneDrive/SP, CodeInterpreter | NCBI Reference | *none* |
| **RegCompliance** | WebSearch, OneDrive/SP, GraphConnectors, CodeInterpreter, Email | openFDA, ClinicalTrials.gov | ProtocolGen |
| **ProtocolGen** | OneDrive/SP, GraphConnectors, Email | *none* | *none* |
| **SciKnowledge** | WebSearch, OneDrive/SP, GraphConnectors, CodeInterpreter | Databricks, Snowflake | *none* |

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

## Graph Connectors

| Connector | Used By |
|---|---|
| **PromoMats** | CopilotHLS Primary, SciKnowledge |
| **QualityDocs** | ProtocolGen, SciKnowledge |
| **Veeva RIM** | RegCompliance, SciKnowledge |

## Agent Routing

```
┌──────────────────────────────────────────────────────────┐
│            CopilotHLS (Orchestrator)                     │
│  Routes to 5 specialist agents based on query type       │
└──────────┬───────┬───────────┬───────────┬───────────────┘
           │       │           │           │
     ┌─────┘   ┌───┘     ┌─────┘     ┌─────┘
     ▼         ▼         ▼           ▼           ▼
 LitReview  BioAnalysis  RegCompliance  ProtocolGen  SciKnowledge
                              │
                              ▼
                         ProtocolGen
```

RegCompliance can hand off protocol-drafting tasks to ProtocolGen.

## Data Source Priority

All agents follow this priority order:
1. **MCP data connectors & plugins** — ALWAYS try these first
2. **SharePoint & Graph Connectors** — Enterprise grounded content
3. **WebSearch fallback** — LAST RESORT only, after grounded sources have been tried

## WebSearch Grounded Sites

| Agent | Allowed Sites |
|---|---|
| **CopilotHLS Primary** | pubmed.ncbi.nlm.nih.gov, scholar.google.com, clinicaltrials.gov |
| **LitReview** | pubmed.ncbi.nlm.nih.gov, scholar.google.com, biorxiv.org, medrxiv.org |
| **BioAnalysis** | ncbi.nlm.nih.gov, uniprot.org, ensembl.org |
| **RegCompliance** | fda.gov, ema.europa.eu, ich.org |
| **SciKnowledge** | learn.microsoft.com, pubmed.ncbi.nlm.nih.gov |
