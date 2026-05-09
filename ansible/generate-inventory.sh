#!/bin/bash
set -e

cd ../proxmox
terraform output -json vm_ips | jq -r '
  "[k3s_cluster:children]\nk3s_cp\nk3s_workers\n\n" +
  "[k3s_cp]\n" +
  ([to_entries[] | select(.key == "k3s-cp") | "\(.key) ansible_host=\(.value)"] | join("\n")) +
  "\n\n[k3s_workers]\n" +
  ([to_entries[] | select(.key | startswith("k3s-w")) | "\(.key) ansible_host=\(.value)"] | join("\n")) +
  "\n\n[k3s_cluster:vars]\n" +
  "ansible_user=mik\n" +
  "ansible_ssh_private_key_file=~/.ssh/id_ed25519\n" +
  "ansible_python_interpreter=/usr/bin/python3"
' > ../ansible/inventory.ini

echo "Inventory generated:"
cat ../ansible/inventory.ini
