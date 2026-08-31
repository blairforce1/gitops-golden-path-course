# 0035. Bicep owns the substrate; Azure Service Operator owns application-adjacent resources

- **Status:** accepted
- **Date:** 2026-08-04
- **Deciders:** blairforce1, with Claude Code
- **Supersedes:** none

## Context

Once reconciliation reaches beyond the cluster, two tools can both claim the same Azure resource: an infrastructure-as-code deployment run from CI, and an in-cluster operator reconciling CRs from git. Without one rule stated once, the two fight over ownership, and a resource edited in the portal drifts from both. The cluster itself, its registry, its vault and the identities that federate against its issuer are also the things a cluster rebuild must not destroy.

## Decision

The platform substrate stays in Bicep, bootstrapped from CI with OIDC federation: the cluster, the container registry, Key Vault, the managed identities, and the federated credentials, which live in the same Bicep as the cluster because the issuer URL is per cluster and a rebuild elsewhere orphans every identity. Application-adjacent resources (a tenant's storage account, service bus, database) move to Azure Service Operator, owned declaratively from the tenant's namespace, with the credential-scoping ladder (global → per namespace → per resource) mapped onto the tenancy model so each tenant's identity is RBAC-scoped to its own resource group. ASO's sharp edges are taught rather than hidden: install only the needed CRD groups, the deletion semantics annotation, and drift when someone edits in the portal.

## Considered options

- **Everything in Bicep.** Tenant resources become a CI pipeline concern, outside the loop that owns the tenant.
- **Everything in ASO.** The cluster cannot own the cluster; identity trust must survive the cluster.
- **Terraform for the substrate.** Equivalent; Bicep is the Azure-native choice and the course leans Azure.

## Consequences

- Easier: provisioning a tenant's storage becomes a PR; tenant onboarding reaches from the namespace to the cloud; the ASO workloads migrate unchanged when the cluster becomes managed.
- Harder: "scratch" narrows to the cluster once ASO reconciles resources that hold data; the drill tears the cluster down and watches ASO re-adopt.
- Follow-up: the ownership rule is stated once so the two stages never fight over the same resource.

## Where it is taught or enforced

Stage 32 (ASO on kind), stage 33 (the cluster via Bicep), stage 35 (identity absorbed); the Act VII checkpoint.
