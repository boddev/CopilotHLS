# Veeva Connector Deployment — M365 Admin Center

Manual steps to deploy the three Veeva Vault Graph Connectors after running the setup scripts.

**Prerequisites**: Complete `scripts/Setup-VeevaConnectors.ps1` and `scripts/Configure-VeevaOAuth.ps1` first.

---

## 1. Deploy Veeva PromoMats Connector

**Agent**: @CopilotHLS (primary) — promotional materials, marketing compliance docs

1. Go to [M365 Admin Center](https://admin.microsoft.com) → **Copilot** → **Connectors** → **Gallery**
2. Select **Veeva PromoMats**
3. **Display name**: `Veeva PromoMats` (or customize for your org)
4. **Instance URL**: Enter your PromoMats vault URL (e.g., `https://promomats.veevavault.com`)
5. **Authentication type**: Microsoft Entra ID OIDC
   - **Vault Session ID URL**: Copy from Veeva Admin > Settings > OAuth 2.0 Profiles > your profile
   - **Client ID**: Use the `CopilotHLS-Veeva-PromoMats` Client ID from `veeva-connector-credentials.json`
   - **Client secret**: Use the corresponding secret
6. Click **Authorize** → sign in with your Entra ID account → **Consent on behalf of your organization** → **Accept**
7. **Rollout**: Choose full rollout or staged rollout to specific users/groups
8. Click **Create**

**Default sync**: Full crawl daily. Customize under Custom Setup if needed.

---

## 2. Deploy Veeva QualityDocs Connector

**Agent**: @ProtocolGen — SOPs, work instructions, CAPAs, batch records, policies

1. M365 Admin Center → **Copilot** → **Connectors** → **Gallery** → **Veeva QualityDocs**
2. **Display name**: `Veeva QualityDocs`
3. **Instance URL**: Enter your QualityDocs vault URL
4. **Authentication**: Microsoft Entra ID OIDC
   - **Vault Session ID URL**: From QualityDocs Vault Admin
   - **Client ID**: `CopilotHLS-Veeva-QualityDocs` Client ID
   - **Client secret**: Corresponding secret
5. **Authorize** → consent → **Accept**
6. Click **Create**

---

## 3. Deploy Veeva Vault RIM Connector

**Agent**: @RegCompliance — regulatory submissions, compliance documents, health authority versions

1. M365 Admin Center → **Copilot** → **Connectors** → **Gallery** → **Veeva Vault RIM**
2. **Display name**: `Veeva Vault RIM`
3. **Instance URL**: Enter your RIM vault URL
4. **Authentication**: Microsoft Entra ID OIDC
   - **Vault Session ID URL**: From RIM Vault Admin
   - **Client ID**: `CopilotHLS-Veeva-RIM` Client ID
   - **Client secret**: Corresponding secret
5. **Authorize** → consent → **Accept**
6. Click **Create**

---

## 4. Verify Indexing

After creating each connection:

1. In Admin Center → **Copilot** → **Connectors**, check the connection status shows **Ready** or **Indexing**
2. Wait for the initial full crawl to complete (may take several hours depending on vault size)
3. Test in Microsoft Search: search for a known Veeva document title → verify it appears in results
4. Verify ACL enforcement: a user WITHOUT Veeva view permissions should NOT see the document

---

## 5. Optional: Custom Properties

Each connector automatically indexes default properties (document name, type, status, product, etc.). To add custom Veeva fields:

1. On the connector page → **Custom Setup** → **Manage Properties**
2. The connector auto-discovers all queryable, non-disabled, non-hidden fields from your vault
3. Select additional properties to index
4. Enable **Search** and/or **Refine** as needed

### Key Properties by Connector

**PromoMats**: Brand, Key Messages, Tags, Secondary Brands
**QualityDocs**: Document lifecycle state, approval dates, CAPA references
**RIM**: Health Authority Version, IDMP Submission Date, Master File Code, RIM Auto-Classification

---

## 6. Link to Declarative Agents

After connectors are deployed and indexing, add `GraphConnectors` to each agent's `declarativeAgent.json`:

```json
{
  "capabilities": [
    { "name": "GraphConnectors" }
  ]
}
```

The Copilot orchestrator will automatically surface Veeva content when relevant to user queries. No additional configuration is needed — the Graph Connector content is available to any agent with the `GraphConnectors` capability enabled.

---

## Troubleshooting

| Issue | Resolution |
|---|---|
| Connector stuck on "Indexing" | Check Vault API connectivity; verify OAuth profile is active |
| No results in Search | Wait for full crawl; verify documents exist in the Vault with view permissions |
| ACL not enforced | Verify identity mapping: Entra user property → Veeva email/federated ID |
| Auth fails during setup | Verify client ID/secret match; check redirect URI is correct for your environment |

For RIM-specific troubleshooting, see [Microsoft Learn: Veeva RIM Troubleshooting](https://learn.microsoft.com/en-us/MicrosoftSearch/veeva-rim-troubleshooting).
