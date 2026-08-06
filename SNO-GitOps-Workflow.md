# SNO (ACP) ArgoCD Application Workflow

How changes to the SNO cluster's GitOps-managed services (storage, virtualization, IT automation, pipelines, network interfaces, etc.) actually get applied, what's tracked by git vs. not, and the durable way to make changes so they survive a reinstall.

> This is a focused deep-dive on the ArgoCD Application/umbrella-chart mechanics specifically. For the full end-to-end picture (IPC4 build → MicroShift → Gitea mirror behavior → ArgoCD sync → lab customization branch workflow), see [HOW_IT_WORKS.md](HOW_IT_WORKS.md) §3–5, which supersedes/expands on this doc for anything about the Gitea mirror itself (pull-mirror sync interval, `enable_prune`, and the dedicated-branch pattern for lab customizations — none of which is covered below).

## The structure

There is exactly **one** ArgoCD Application created directly on the cluster: `acp-standard-services` (namespace `openshift-gitops`). Its Helm chart (`charts/acp-standard-services` in the [acp-standard-services-public](http://code-gitea.apps.ipc4.sps2025.com/admin/acp-standard-services-public.git) repo) is an **umbrella/app-of-apps chart** — each template under `charts/acp-standard-services/templates/` (`local-storage.yaml`, `virtualization.yaml`, `it-automation.yaml`, `pipelines.yaml`, `network-interface-management.yaml`, etc.) renders a **child** `Application` object, gated behind a `{{- with .Values.<key> }}` block. If the corresponding key isn't set in the parent's values, that child Application simply never gets created.

```
acp-standard-services (the only Application created directly)
├─ values.localStorage            → renders child Application "local-storage"
├─ values.virtualization          → renders child Application "virtualization"
├─ values.itAutomation            → renders child Application "it-automation"
├─ values.pipelines               → renders child Application "pipelines"
└─ values.networkInterfaceManagement → renders child Application "network-interface-management"
```

Confirmed via `oc get application -n openshift-gitops -o custom-columns=NAME:.metadata.name,OWNERS:.metadata.ownerReferences` — none of the 5 Applications have `ownerReferences`, and there is no `ApplicationSet` on the cluster. ArgoCD itself doesn't track or revert the parent Application's own spec.

## What's git-tracked, and what isn't

- **Git-tracked (auto-syncs normally)**: everything under `charts/*/templates/` in the repo — the actual resource definitions (Subscriptions, OperatorGroups, CRs, NetworkAttachmentDefinitions, etc.). Push a change to the `dev` branch, ArgoCD's `selfHeal: true` picks it up.
- **NOT git-tracked**: the root `acp-standard-services` Application's own `spec.source.helm.values` block — the actual YAML values that decide which child Applications exist and how they're configured. This is **inline** on the Application object itself, not a file ArgoCD reads from the repo on every sync.

That values block only exists in two places:

1. **Live on the cluster** — `oc get application acp-standard-services -n openshift-gitops -o jsonpath='{.spec.source.helm.values}'`. Editing this directly (`oc patch`) takes effect immediately.
2. **Baked into the SNO install ISO** — a one-shot bootstrap `Job` (`apply-acp-standard-services`, namespace `bootstrap-gitops`) that runs once during initial cluster install, defined in `images/ipc4/ocp-agent-install/configmap.yaml` (the `additional-manifests` ConfigMap's `job.yaml` key) in **this** repo. It waits for cluster operators to be healthy, then `oc apply`s the Application object with values baked into a heredoc.

## The catch

The bootstrap Job is a plain `batch/v1 Job` (`restartPolicy: Never`, `backoffLimit: 0`) — it runs once at install time and is done. It does **not** continuously reconcile. So:

- A live `oc patch application acp-standard-services ...` takes effect immediately and is safe from ArgoCD's own reconciliation (nothing owns/reverts the parent Application).
- But it is **not** safe from a future cluster reinstall (disaster recovery, re-running the agent ISO) — that would recreate the bootstrap Job fresh, which re-applies the Application with whatever values were baked into `images/ipc4/ocp-agent-install/configmap.yaml` **at the time that install ISO was built** — silently reverting any live-only changes.

This was confirmed directly: the bootstrap job.yaml's baked-in values are missing `pipelines`, `networkInterfaceManagement`, and — as an aside, unrelated to anything we've been changing — have `virtualization.commonBootImageImport: true`, while the **live** cluster currently has it set to `false` (pre-existing drift, not something introduced by this work; flagged here, not fixed, since the reason for the live change isn't known).

## Durable workflow for changing what's enabled

To make a change (e.g., enabling a new service like `pipelines` or `networkInterfaceManagement`) that survives a future reinstall, **do both**:

1. **Live**: `oc patch application acp-standard-services -n openshift-gitops --type=merge` with the updated `spec.source.helm.values`, for immediate effect on the running cluster.
2. **Bootstrap source**: update the same values block inside `images/ipc4/ocp-agent-install/configmap.yaml` in this repo (the `job.yaml` heredoc), and sync it to the live IPC4 manifest too (`/etc/microshift/manifests.d/ocp-agent-install/configmap.yaml`) — matching the same repo/live sync discipline used elsewhere in this repo (see `Troubleshoot-July2026.md` for the recurring pattern of live/repo drift on IPC4). This doesn't affect the *currently running* SNO cluster (the bootstrap Job only runs once, already ran months ago) — it only matters for the **next** install ISO generated from IPC4.

Changes to chart **templates** (not the root values) — e.g., editing `charts/virtualization/templates/networkattachmentdefinition.yaml` — go through git normally: push to the `dev` branch of the Gitea-mirrored repo, ArgoCD syncs automatically.
