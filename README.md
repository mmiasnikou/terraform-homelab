# terraform-homelab

Personal homelab infrastructure as code.

## Stack

- **Terraform** — infrastructure provisioning
- **Ansible** — configuration management
- **Docker / k3s** — container workloads
- **Prometheus + Grafana + Loki** — observability

## Structure

```
.
├── docker/         # Terraform configs for Docker workloads
├── proxmox/        # VM provisioning on Proxmox
├── ansible/        # Configuration playbooks
└── README.md
```

## Status

Work in progress.
