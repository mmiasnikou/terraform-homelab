output "vm_ips" {
  description = "Map of VM names to their LAN IPv4 addresses"
  value = {
    for name, vm in proxmox_virtual_environment_vm.vm :
    name => try(
      [
        for ip in flatten(vm.ipv4_addresses) :
        ip if startswith(ip, "192.168.188.")
      ][0],
      "unknown"
    )
  }
}

output "vm_count" {
  description = "Number of VMs created"
  value       = length(proxmox_virtual_environment_vm.vm)
}
