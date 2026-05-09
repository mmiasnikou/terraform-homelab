resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.vms

  name      = each.key
  node_name = var.proxmox_node
  pool_id   = "lab"

  clone {
    vm_id = var.template_id
    full  = true
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
  }

  agent {
    enabled = true
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = each.value.disk
  }

  initialization {
    datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_data_file_id = "local:snippets/qemu-guest-agent.yaml"
  }

  network_device {
    bridge = "vmbr0"
    mac_address = format("BC:24:11:%02X:%02X:%02X", index(keys(var.vms), each.key) + 1, 0, 0)

  }
}
