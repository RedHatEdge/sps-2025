# IPC4 MicroShift Crashloop — Troubleshooting Summary (July 2026)

Host: IPC4 (`ssh admin@100.121.77.69`) — hosts MicroShift, DNS, DHCP, NTP, etc.

## Summary

The IPC4 microshift crashloop had **three independent, stacked root causes**, each masking the next:

1. **etcd data bloat (3.8 GB, no compaction)** — `auto-compaction` was disabled, so etcd never trimmed history. The DB had to defragment on every boot (~30s, fully blocking reads/health checks), and 533K of the 1M+ keys were stale `Event` objects that had accumulated because the crashloop never let MicroShift's own garbage-collection controllers run long enough to expire them. **Fixed**: compacted, purged events, defragged → 84 MB.

2. **Corrupted raft/WAL state** — after ~101,000 historical restarts, etcd's raft log itself was pathological: even as sole leader of its own single-node cluster, it couldn't commit its own membership record, spinning at 100–300% CPU indefinitely. **Fixed**: rebuilt a clean data directory via `etcdutl snapshot restore` from the (healthy) key-value snapshot, discarding the entire corrupted log history — raft term dropped from 101,437 back to 1.

3. **The actual dominant, deterministic cause**: `/var/lib/microshift/lvms/lvmd.yaml` (a config file MicroShift regenerates from detected volume groups on every boot) was corrupted on disk — two different writes smashed together with no separator, causing a YAML parse failure that made `infrastructure-services-manager` intentionally stop MicroShift, every single time (194/194 occurrences in the final hour). **Fixed**: removed the corrupted file and let MicroShift regenerate it fresh.

Also added a systemd drop-in (`TimeoutStartSec=900`, `RestartSec=10`) as a safety margin. Full backups of every prior state (original 3.8GB etcd data, corrupted WAL, corrupted lvmd.yaml) are saved under `/var/lib/microshift-etcd-backup/` and `/var/lib/microshift/etcd-old-corrupted-wal`.

## Result

MicroShift stabilized to `active (running)` with 0 restarts and a `Ready` node after the fixes above.

## Follow-up: storage/PV recovery and root cause (same day)

Several application pods (flightctl, gitea, oc-mirror, ocp-agent-install) were still crashlooping/pending after the node stabilized, with very high restart counts (1000+).

**Root cause of the storage layer**: `setup-storage.service` (`Type=oneshot`, runs on every boot, not just first boot) never checked whether its target disk already held LVM data. On every reboot it re-selected `/dev/nvme0n1` (still "unpartitioned" by its own check) and destructively re-ran `sgdisk -Z` + `pvcreate` + `vgcreate`, wiping the entire `microshift-storage` volume group — thin-pool and every logical volume — even though it was already correctly provisioned. Confirmed directly from the boot journal at 08:01:12 CEST the same day:
```
Found unpartitioned disk: /dev/nvme0n1
GPT data structures destroyed!
Physical volume "/dev/nvme0n1" successfully created.
Volume group "microshift-storage" successfully created
```
This is what destroyed the underlying data behind every existing PVC (Kubernetes PV/PVC *records* survived in etcd; the real volumes did not). It also never tagged the VG `@lvms`, so LVMS refused to adopt/manage it (`VolumeGroupsReady: False, reason: VGsFailed`).

**Fixed**:
- Tagged the VG live (`vgchange --addtag @lvms microshift-storage`) so LVMS adopts it.
- Deleted and recreated every broken PVC so each provisioned a fresh, real volume: `flightctl-alertmanager-data` (StatefulSet scale 0→1), `oc-mirror` `registry-pvc`/`oc-mirror-scratch-pvc` and `ocp-agent-install` `installer-iso` (reapplied from their `manifests.d/` source files), `gitea` `code-pvc`/`postgresql-code-pvc` (recreated by restarting `gitea-operator`, which owns them), and the orphaned `default/lvms-smoke` health-check PVC.
- Found and fixed the missing `flightctl-db` PVC (60Gi, never recreated after the wipe since it's a plain Helm-deployed `Deployment`, not something continuously reconciled) — extracted its exact spec from `helm get manifest flightctl -n flightctl` and applied it directly. This single fix cascade-recovered 7 other flightctl pods that were blocked on their `wait-for-database-app` init container.
- **Patched `images/ipc4/setup-storage.sh`** in this repo: added a guard that skips disk selection/zap/create entirely if `microshift-storage` already exists (just ensures the `@lvms` tag), and added `--addtag @lvms` to the `vgcreate` call for genuinely fresh disks. This only takes effect on the *next image rebuild/redeploy* of IPC4.
- **Stop-gap on the live host**: `/usr/local/bin/setup-storage.sh` can't be edited directly (bootc/ostree read-only `/usr`), so `storage-setup.service` was disabled (`systemctl disable`) on IPC4 to prevent the destructive wipe on any reboot before the rebuilt image is deployed. **Re-enable this service once the rebuilt IPC4 image (with the idempotent script) is deployed.**

**Note**: `VolumeGroupsReady` still reports `VGsDegraded` — LVMS still expects a thin-pool (`thin-pool-1`) that was lost in the same wipe and hasn't been recreated. This doesn't block current workloads since they use the `topolvm-provisioner` storage class (plain LVs, not the thin-pool path), but would matter if anything targets the `lvms-default`/`lvms-microshift-storage` storage classes.

Clarification: `ocp-agent-install` has no `Job` resource — `install-iso` is a plain `Pod` (`images/ipc4/ocp-agent-install/pod.yaml`). It was deleted/recreated directly from `persistentvolumeclaim.yaml` + `pod.yaml` in that manifests directory, not via a Job.

## Follow-up: install-iso still failing — invalid/expired quay.io credentials (unrelated to storage)

After the storage recovery, `install-iso`'s init container (`create-installer-iso`, an Ansible playbook running `openshift-install agent create image`) still failed. Root cause turned out to be unrelated to anything fixed above:

- `oc-mirror/registry`'s storage is genuinely empty (`du -sh /var/lib/registry` → 0) — the mirrored OCP release content was lost in the same disk wipe, not just the PVC.
- Re-running the `run-oc-mirror` Job (deleted + reapplied `images/ipc4/oc-mirror/job.yaml`) to repopulate it failed immediately with: `unable to read image quay.io/openshift-release-dev/ocp-release@...: unauthorized: Could not find robot with specified username`.
- This is a **quay.io credential problem**, not a data/storage problem: `run-oc-mirror-configjson-secret` does have a `quay.io` auth entry, but the token is invalid or expired. This blocks oc-mirror from populating the registry at all, and (as a side effect) blocks `install-iso` from generating an ISO, since it needs the same release images.
- Stopped the failing Job (it would otherwise keep retrying up to `backoffLimit: 25` uselessly). **Needs a fresh/valid quay.io pull-secret credential from the account owner before oc-mirror (and install-iso) can work again** — this isn't something fixable from the cluster side.
