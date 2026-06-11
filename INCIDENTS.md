# Incidents & Troubleshooting

Postmortem-style writeups of real failures hit while running this homelab.
Format: symptom → diagnosis → root cause → fix → prevention.

---

## 1. Thin-pool overflow → I/O errors on all VMs

**Symptom.** All Proxmox VM disks went read-only with `io-error`; VMs became
unresponsive. Thin pool utilization at ~93.89%.

**Diagnosis.** `lvs` / `pvesm status` on the Proxmox host showed the LVM-thin
data pool nearly full. Traced back to a `terraform apply` that was meant to only
change VM memory but had spawned duplicate ("ghost") VMs 103/104/105.

**Root cause.** The VMs are managed with bpg/proxmox using a `clone {}` block.
Terraform reported "update in-place" in the plan but executed **destroy + recreate**
at apply time, because the clone block is effectively immutable. The recreate
duplicated disks and overflowed the thin pool.

**Fix.** Destroyed the ghost VMs; expanded the Proxmox VM disk 60 → 80 GB in
VMware (required deleting snapshots first); then on the host:
`growpart /dev/sda 3` → `pvresize /dev/sda3` → `lvextend -L +18G /dev/pve/data`.
Pool utilization dropped to ~56.42%. Stale VM IDs 103/104/105 had to be
cleaned from Terraform state before any future apply.

**Prevention.** Established a rule: **never `terraform apply` to change memory/CPU
on `clone {}`-managed Proxmox VMs** — use `qm set` directly. Added monitoring on
thin-pool utilization so it never silently approaches full again.

---

## 2. coredns / metrics-server CrashLoopBackOff (SIGSEGV, exit 139)

**Symptom.** coredns and metrics-server stuck in CrashLoopBackOff; containers
exiting with code 139 (SIGSEGV) right after start.

**Diagnosis.** `kubectl logs --previous` + `lastState` showed segfaults in the Go
runtime on startup, not application-level errors — pointing at the CPU/instruction
layer rather than the workloads.

**Root cause.** The Proxmox VMs were configured with CPU type `kvm64`, which lacks
the `GOAMD64=v2` instruction set that the Go binaries in these images require.

**Fix.** Changed the Proxmox VM CPU type from `kvm64` to `host`, exposing the real
CPU instruction set to the guests.

**Prevention.** Standardized CPU type `host` across all k3s VMs in the VM template,
so new nodes inherit it.

---

## 3. AppArmor profile blocking the Go runtime (recurring after reboot)

**Symptom.** After fixing the CPU issue, the same Go-runtime crashes returned
following reboots.

**Diagnosis.** Narrowed to the `cri-containerd.apparmor.d` profile running in
**enforce** mode, which blocked syscalls the Go runtime needs. Disabling via the
usual symlink-in-disable-dir trick had no effect.

**Root cause.** k3s loads its AppArmor profile directly from its **own bundled
data**, not from `/etc/apparmor.d/` — so symlinks in the disable directory are
ignored, which is why the problem survived reboots.

**Fix.** Masked `apparmor.service` on the k3s nodes (`systemctl mask apparmor.service`),
removed the ineffective symlinks from `/etc/apparmor.d/disable/`, and rebooted each
node so the profile unloaded from the kernel. The `config.toml.tmpl` route was
considered but rejected — the profile wasn't loaded via containerd config (no
AppArmor entry there); k3s loads it from its own binary, so masking the service was
the clean fix.

**Justification (worth stating in interview).** These are dedicated k3s VMs with no
other workload. Cluster security rests on namespace isolation + cgroups + seccomp +
RBAC; AppArmor is an extra layer here, not the base one — managed Kubernetes often
runs it permissive or off. The cost (three crash-looping system pods) outweighed the
marginal benefit on a single-purpose node.

**Prevention.** Codified the masking in the Ansible role so every node gets it on
provision.

---

## 4. Cluster-wide CrashLoopBackOff from host memory starvation

**Symptom.** coredns / argocd-server / others flapping in CrashLoopBackOff with
ever-growing restart counts, across multiple namespaces at once.

**Diagnosis.** The pattern — multiple unrelated pods failing simultaneously on
liveness/readiness timeouts — pointed away from the apps. `dmesg` on the nodes
showed OOM kills; the Windows host (16 GB) was ~93% memory-used, leaving VMware
no RAM to back the VMs.

**Root cause.** **Hypervisor starvation**, not a k3s problem. With the host
overcommitted, VMware swapped VM pages to disk, VMs got tens-to-hundreds-of-ms
I/O latency, and kubelet probes timed out → restart loops.

**Fix.** Freed host RAM; right-sized VM memory allocations (lab-control down to
2 GiB, Proxmox down to ~10 GiB) so the working set fits in physical RAM.

**Prevention.** Treat the 16 GB host as the real constraint; keep non-essential
VMs powered off when not needed (e.g. cluster off during the AWS/LocalStack work).

---

## 5. k3s rolling upgrade — flag loss across control-plane and workers

**Symptom.** During the k3s minor-version upgrade (1.31.4 → 1.32.11), nodes came
back mis-configured: the control plane lost its flags; one worker had a stray
server unit; another looped on `--server is required`.

**Diagnosis.** Reviewed each node's k3s service/unit and config after the
install-script run; found the install script was overwriting flags that had been
passed as CLI args.

**Root cause.** Passing config as install-script flags is fragile across upgrades —
the upgrade path didn't preserve them, so each node drifted differently.

**Fix.** Moved configuration into `/etc/rancher/k3s/config.yaml` (durable across
the install script), recovered the control plane from a snapshot, cleaned the
stray units. Decoupled k3s node identity from OS hostname via `node-name` in the
config.

**Prevention.** Codified the `config.yaml` approach in the Ansible role as the
source of truth; added `serial: 1` + drain/uncordon orchestration so the role
upgrades one node at a time with pod evacuation, instead of hitting all nodes at
once. This was later proven on the 1.35.5 → 1.36.1 upgrade, which ran clean
(`failed=0`) through the role.

---

## How to use these in an interview

Pick one, tell it in ~90 seconds: **what broke, how you found it, why it happened,
what you did, what you changed so it can't recur.** The last part (prevention) is
what separates SRE thinking from "I restarted it."
