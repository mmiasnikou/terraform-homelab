#!/bin/bash
set -e

cd ../proxmox
terraform output -json vm_ips | jq -r '
  "[lab_vms]\n" +
  ([to_entries[] | "\(.key) ansible_host=\(.value)"] | join("\n")) +
  "\n\n[lab_vms:vars]\n" +
  "ansible_user=mik\n" +
  "ansible_ssh_private_key_file=~/.ssh/id_ed25519\n" +
  "ansible_python_interpreter=/usr/bin/python3"
' > ../ansible/inventory.ini

echo "Inventory generated:"
cat ../ansible/inventory.ini
