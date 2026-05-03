resource "proxmox_virtual_environment_vm" "test_vm" {
  name      = "tf-test-01"
  node_name = "pve"
  pool_id   = "lab"

  clone {
    vm_id = 9000
    full  = true
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  agent {
    enabled = true
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 20
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
  }
}

output "vm_ip" {
  value = proxmox_virtual_environment_vm.test_vm.ipv4_addresses
}
