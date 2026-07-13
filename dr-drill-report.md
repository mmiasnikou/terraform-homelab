# DR Drill Report — Velero + MinIO

Evidence log of a disaster-recovery drill on my homelab k3s cluster. Not a
runbook — just a record of what was done and what actually happened, with
real command output.

**Date:** 2026-06-11
**Cluster:** k3s v1.36.1 (k3s-cp, k3s-w1, k3s-w2)
**Tooling:** Velero v1.18.1 (client + server), MinIO (S3-compatible backend),
node-agent for filesystem-level PV backup. Installed imperatively, outside
GitOps: the recovery tooling should not depend on the thing it may have to
recover.

---

## 1. Setup

MinIO deployed via Helm (standalone, 1 replica, 5Gi PVC, bucket `velero`
auto-created) as the S3 backend. Velero server installed with the AWS plugin
(MinIO speaks S3) and `--use-node-agent` for pod-volume (filesystem)
backups. Without the node-agent, Velero backs up manifests only, not PV
contents.

```
$ velero backup-location get
NAME      PROVIDER   BUCKET/PREFIX   PHASE       LAST VALIDATED                  ACCESS MODE   DEFAULT
default   aws        velero          Available   2026-06-11 15:39:54 +0000 UTC   ReadWrite     true
```

## 2. Test workload

Spun up an isolated namespace `dr-test` with a pod + PVC and wrote a marker
file to the volume:

```
$ kubectl -n dr-test exec dr-app -- cat /data/important.txt
DR-drill data created at Thu Jun 11 15:43:48 UTC 2026
```

## 3. First backup attempt: `Completed`, but without the volume data

The first backup relied on the `backup.velero.io/backup-volumes` pod
annotation (the older opt-in method). It finished with a green status, but
the volume itself was skipped:

```
$ velero backup describe dr-backup-1 --details | grep 'File System Backup'
File System Backup (Default):  false
```

Switched to the explicit `--default-volumes-to-fs-backup` flag, which is the
right approach for the node-agent in this Velero version:

```
$ velero backup create dr-backup-2 --include-namespaces dr-test --default-volumes-to-fs-backup --wait
Backup completed with status: Completed.

$ velero backup describe dr-backup-2 --details | grep -iE 'phase|File System Backup'
Phase:  Completed
File System Backup (Default):  true
```

Then checked that the volume was actually captured. I had to go through the
`PodVolumeBackup` CRD, because `velero backup describe --details` couldn't
resolve the in-cluster MinIO DNS name from outside the cluster:

```
$ kubectl -n velero get podvolumebackups -o custom-columns='NAME:.metadata.name,POD:.spec.pod.name,VOLUME:.spec.volume,STATUS:.status.phase,BYTES:.status.progress.bytesDone'
NAME                POD      VOLUME   STATUS      BYTES
dr-backup-2-znlz6   dr-app   data     Completed   54
```

54 bytes is exactly the size of `important.txt`, so the file content itself
made it into the backup, not just the Kubernetes object manifests.

## 4. Disaster — full namespace deletion

```
$ kubectl delete namespace dr-test
namespace "dr-test" deleted

$ kubectl get namespace dr-test
Error from server (NotFound): namespaces "dr-test" not found
```

Pod, PVC, and the underlying local-path volume on disk were all destroyed.
At this point the data was genuinely gone from the cluster.

## 5. Restore — timed

```
$ echo "RESTORE START: $(date -u)"
RESTORE START: Thu Jun 11 15:55:39 UTC 2026

$ velero restore create dr-restore-1 --from-backup dr-backup-2 --wait
Restore completed with status: Completed.

$ echo "RESTORE END: $(date -u)"
RESTORE END: Thu Jun 11 15:55:57 UTC 2026
```

**RTO: ~18 seconds** (namespace + pod + PVC + file-level volume data,
restored from S3-backed storage).

## 6. Verification

```
$ kubectl -n dr-test exec dr-app -- cat /data/important.txt
DR-drill data created at Thu Jun 11 15:43:48 UTC 2026
```

Byte-for-byte identical to the marker written before the drill.

---

## What this proves

- A full backup → delete → restore → verify cycle was executed, not just
  configured.
- Volume *contents* are covered, not only Kubernetes manifests. The first
  attempt quietly skipped them while reporting `Completed` — the kind of gap
  you only find by actually deleting things.
- RTO was measured, not estimated.
- Velero and MinIO are deployed outside the GitOps flow on purpose: recovery
  tooling has to survive the scenarios where the GitOps control plane itself
  is what needs recovering.

## Known limitation

This drill covers Kubernetes objects and PV data (the Velero layer). The k3s
control-plane datastore (SQLite, via kine) is backed up separately with
`sqlite3 .backup` plus integrity verification. A destructive restore drill of
the datastore itself was not performed: the control plane is single-node, and
a failed restore would take the whole cluster down with no fast path back. I
judged that risk not worth it for a lab. The restore procedure is documented
and understood, but not exercised live.

Related: [INCIDENTS.md](INCIDENTS.md)
