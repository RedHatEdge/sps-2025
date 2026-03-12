# How the SPS-2025 demo setup works

This document explains the end-to-end flow: building the IPC4 boot image, what the image places into MicroShift on IPC4, how the local mirror and Gitea/GitOps are wired, and what the ACP Single Node receives when installed with the generated agent ISO.

## 1) Build the IPC4 boot image

- Build example (from repo):

```bash
podman build images/ipc4/ --tag localhost/ipc4:latest --build-arg-file=build-args.txt
```

- The build uses the Containerfile at [images/ipc4/Containerfile](images/ipc4/Containerfile) which is based on a MicroShift bootc image. During the image build the Containerfile:
  - Registers RHEL subscription (build args `RHSM_ORG`, `RHSM_AK`).
  - Installs required tools (`podman`, `oc` clients, `microshift-olm`, `skopeo`, `nmstate`, etc.).
  - Copies MicroShift configuration files and assets into the image (`/etc/microshift/config.yaml`, `/etc/microshift/ovn.yaml`, storage config).
  - Adds a set of prepared Kubernetes manifests into `/etc/microshift/manifests.d/<component>` using `ADD` (see next section). These manifests are applied automatically by MicroShift at startup.
  - Adds helper scripts such as `get-microshift-kubeconfig.sh` and network/storage setup systemd units executed at first boot.

## 2) What runs on IPC4 MicroShift after boot

MicroShift watches `/etc/microshift/manifests.d/` and will create the resources found in each subdirectory.

Key manifest groups added by the Containerfile:

- DHCP: [images/ipc4/dhcp](images/ipc4/dhcp)
  - ConfigMap with `dnsmasq` configuration and a DaemonSet that runs dnsmasq on the host network to serve `192.168.100.0/24` addresses.

- DNS: [images/ipc4/dns](images/ipc4/dns)
  - ConfigMap with `named` configuration (forward/reverse zones) and a DaemonSet running `named` on the host network.

- NTP: [images/ipc4/ntp](images/ipc4/ntp)
  - Namespace, ServiceAccount, SCC/ClusterRole/RoleBinding, a ConfigMap with `chrony` config and a DaemonSet that runs `chronyd` on host network so hosts on the demo LAN can sync time.

- Gitea and Gitea Operator: [images/ipc4/gitea](images/ipc4/gitea) and [images/ipc4/gitea-operator](images/ipc4/gitea-operator)
  - `gitea-operator` is installed via an Operator `CatalogSource` and `Subscription` so the operator will manage `Gitea` CRs.
  - There is a `Job` (`deploy-gitea`) which applies a `Gitea` CR from a ConfigMap; a follow-up job sets up the admin user; another job (`mirror-repo`) creates a mirror of `https://github.com/RedHatEdge/acp-standard-services-public.git` into the local Gitea instance. See [images/ipc4/gitea/job.yaml](images/ipc4/gitea/job.yaml) and [images/ipc4/gitea/configmap.yaml](images/ipc4/gitea/configmap.yaml).

- oc-mirror / local mirror: [images/ipc4/oc-mirror](images/ipc4/oc-mirror)
  - A ConfigMap contains an `ImageSetConfiguration` (see [images/ipc4/oc-mirror/configmap.yaml](images/ipc4/oc-mirror/configmap.yaml)) which instructs `oc-mirror` to mirror operators catalogs (including the RedHat catalog and the local `gitea-catalog`) and additional images into the local registry `registry.oc-mirror.svc.cluster.local:5000` on IPC4.
  - A Job runs `oc-mirror` to populate the local mirror. This makes operator catalog images and container images available offline for the ACP install process.

- OCP agent install generator: [images/ipc4/ocp-agent-install](images/ipc4/ocp-agent-install)
  - Contains a ConfigMap with files used to generate an agent ISO for installing ACP.
  - The job in this manifest generates an agent installation ISO and serves it from IPC4 so you can download and use it to install ACP on target hardware. See [images/ipc4/ocp-agent-install/configmap.yaml](images/ipc4/ocp-agent-install/configmap.yaml).

Other helpers placed by the image include networking and storage setup systemd units and a `get-microshift-kubeconfig.sh` helper to extract the MicroShift kubeconfig.

## 3) GitOps wiring: Gitea → ArgoCD → ACP services

- After MicroShift brings up `gitea` and the `mirror-repo` job runs, the repository `acp-standard-services-public` is mirrored into the Gitea instance (`http://code.gitea.apps.ipc4.sps2025.com/admin/acp-standard-services-public.git`). This is the same upstream repository used to define the ACP services and charts.

- The OCP agent install process (created by the `ocp-agent-install` manifests) creates an ArgoCD `Application` on the ACP cluster once the ACP is installed. See the `apply-acp-standard-services` job embedded in [images/ipc4/ocp-agent-install/configmap.yaml](images/ipc4/ocp-agent-install/configmap.yaml). That job creates:
  - A repository secret for ArgoCD pointing to the local Gitea repo.
  - An ArgoCD `Application` named `acp-standard-services` which points at `charts/acp-standard-services` in the mirrored repo and syncs the `dev` branch.

- The `acp-standard-services` Application installs a set of operators and charts on ACP. The `ImageSetConfiguration` and `oc-mirror` ensure required operator catalogs and images are available from the IPC4 mirror so the ACP installation and subsequent ArgoCD sync can use them offline.

Key operator/components included by the chart (see the rendered manifest in the ConfigMap):

- `ansible-automation-platform-operator` (stable-2.6)
- `kubernetes-nmstate-operator`
- `kubevirt-hyperconverged`
- `lvms-operator`
- `openshift-gitops-operator` (ArgoCD)

The `acp-standard-services` app also sets local storage configuration (device classes, force-wipe options), virtualization flags, and other values that control how services are deployed on the ACP nodes. Refer to the `apply-acp-standard-services` job in [images/ipc4/ocp-agent-install/configmap.yaml](images/ipc4/ocp-agent-install/configmap.yaml) for the exact applied YAML fragment.

## 4) Typical run sequence (high level)

1. Build `images/ipc4` image and create an ISO from it (script `scripts/create-iso.sh` is provided).
2. Boot the target machine from the generated ISO (this becomes IPC4). MicroShift starts and applies manifests from `/etc/microshift/manifests.d`.
3. MicroShift brings up DHCP/DNS/NTP/Gitea and the oc-mirror/local registry. `oc-mirror` job mirrors operator catalogs/images into the local registry.
4. Gitea is created and the `acp-standard-services-public` repository is mirrored from GitHub into the local Gitea instance.
5. The ocp-agent-install manifests generate and serve an agent ISO that you download and use to install ACP on target hardware. When ACP finishes installing and ArgoCD becomes available, the `apply-acp-standard-services` job creates an ArgoCD Application pointing at the mirrored repo.
6. ArgoCD syncs `acp-standard-services` and deploys the operators/services (ansible AAP, kubevirt, LVMS, etc.) onto the ACP cluster.

## 5) Where to look in this repo

- Boot image Containerfile: [images/ipc4/Containerfile](images/ipc4/Containerfile)
- MicroShift manifests placed into the image:
  - DHCP: [images/ipc4/dhcp](images/ipc4/dhcp)
  - DNS: [images/ipc4/dns](images/ipc4/dns)
  - NTP: [images/ipc4/ntp](images/ipc4/ntp)
  - Gitea: [images/ipc4/gitea](images/ipc4/gitea)
  - Gitea operator: [images/ipc4/gitea-operator](images/ipc4/gitea-operator)
  - oc-mirror: [images/ipc4/oc-mirror](images/ipc4/oc-mirror)
  - ocp-agent-install: [images/ipc4/ocp-agent-install](images/ipc4/ocp-agent-install)

## 6) Troubleshooting tips

- If `oc-mirror` fails while pinning manifests (for example due to a missing `gcr.io/kubebuilder/kube-rbac-proxy` manifest), you can either:
  - Patch the operator catalog bundle to replace the broken image reference with a maintained image (rebuild/push the catalog and point your `ImageSetConfiguration` at it), or
  - Mirror a compatible `kube-rbac-proxy` image into the local registry and edit the CSV references to use the local registry path.

- Check MicroShift-managed pods and static manifests with `oc get pods -A` (after extracting kubeconfig with `get-microshift-kubeconfig.sh`).
- To inspect what `oc-mirror` will mirror, read [images/ipc4/oc-mirror/configmap.yaml](images/ipc4/oc-mirror/configmap.yaml).

## Checklist — step by step

1. Build the IPC4 image:

```bash
podman build images/ipc4/ --tag localhost/ipc4:latest --build-arg-file=build-args.txt
```

2. Create the installation ISO (example):

```bash
scripts/create-iso.sh localhost/ipc4:latest $(pwd)/kickstarts/example.ks ~/Downloads/rhel-9.6-x86_64-boot.iso ./ipc4.iso
```

3. Boot the target machine with the ISO (becomes IPC4). Wait for MicroShift to start.

4. Extract MicroShift kubeconfig on IPC4 (or locally after mounting):

```bash
get-microshift-kubeconfig.sh
oc --kubeconfig ~/.kube/microshift-config get pods -A
```

5. Verify core services on MicroShift:
- `oc get pods -A` — check `dhcp`, `dns`, `oc-mirror`, `gitea`, `ocp-agent-install` namespaces.

6. Run or verify the `oc-mirror` Job completes and the local registry at `registry.oc-mirror.svc.cluster.local:5000` is populated.

7. Confirm Gitea repo exists and is mirrored (the `mirror-repo` Job creates `acp-standard-services-public`).

8. Download the generated agent ISO from IPC4 (URL served by ocp-agent-install) and use it to install ACP on target hardware.

9. After ACP install, ArgoCD and the `apply-acp-standard-services` Job (run on MicroShift or in ACP, depending on flow) will create an ArgoCD Application that points to `http://code-gitea.apps.ipc4.sps2025.com/admin/acp-standard-services-public.git`.

10. Verify ArgoCD syncs `acp-standard-services` and the listed operators (AAP, kubevirt, LVMS, openshift-gitops) get installed on ACP.

## Architecture diagram

```mermaid
flowchart LR
  subgraph User
    Dev[Operator / Builder]
  end

  subgraph IPC4[IPC4 (MicroShift)]
    MS(MicroShift)
    REG[Local Registry\nregistry.oc-mirror.svc.cluster.local:5000]
    GITEA[Gitea]
    OC_MIRROR[oc-mirror Job]
    AGENT_GEN[ocp-agent-install]
  end

  subgraph ACP[ACP Cluster]
    ARGO(ArgoCD)
    ACP_SERVERS[acp-standard-services]
  end

  Dev -->|build ISO| IPC4
  MS -->|applies manifests| DHCP[DHCP/DNS/NTP/Services]
  OC_MIRROR --> REG
  GITEA -->|mirrors repo| MS
  AGENT_GEN -->|serves agent ISO| Dev
  Dev -->|install from agent ISO| ACP
  REG -->|provides operator images| ACP
  GITEA -->|repo for GitOps| ARGO
  ARGO -->|syncs| ACP_SERVERS

  classDef infra fill:#e8f5e9,stroke:#2e7d32;
  classDef control fill:#e3f2fd,stroke:#1565c0;
  class IPC4,REG,GITEA,OC_MIRROR,AGENT_GEN infra;
  class ARGO,ACP_SERVERS control;
```

