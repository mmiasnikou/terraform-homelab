output "vm_ips" {
  description = "Map of VM names to their IPv4 addresses"
  value = {
    for name, vm in proxmox_virtual_environment_vm.vm :
    name => one([
      for ip in flatten(vm.ipv4_addresses) :
      ip if ip != "127.0.0.1" && !startswith(ip, "169.254")
    ])
  }
}

output "vm_count" {
  description = "Number of VMs created"
  value       = length(proxmox_virtual_environment_vm.vm)
}
