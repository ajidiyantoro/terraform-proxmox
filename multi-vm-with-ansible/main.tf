terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "2.9.14"
    }
  }
}

provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure     = true
}

resource "proxmox_vm_qemu" "vm" {
  count       = var.vm_count
  vmid        = 200 + (count.index + 1)
  name        = "vm-demo-${count.index + 1}"
  target_node = "pve"

  clone      = "ubuntu-jammy"
  full_clone = true

  os_type                 = "cloud-init"
  cloudinit_cdrom_storage = "local-lvm"

  ciuser     = var.ci_user
  cipassword = var.ci_password
  sshkeys    = file(var.ci_ssh_public_key)

  cores  = 1
  memory = 1024
  agent  = 1

  bootdisk  = "scsi0"
  scsihw    = "virtio-scsi-pci"
  ipconfig0 = "ip=dhcp"

  disk {
    size    = "10G"
    type    = "scsi"
    storage = "local-lvm"
  }

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }

  lifecycle {
    ignore_changes = [
      network
    ]
  }
}

resource "null_resource" "create_ansible_inventory" {
  provisioner "local-exec" {
    command = <<-EOT
      cat <<EOL > inventory.ini
      [vms]
      ${join("\n", formatlist("%s ansible_host=%s", proxmox_vm_qemu.vm.*.name, proxmox_vm_qemu.vm.*.default_ipv4_address))}
      EOL
    EOT
  }

  depends_on = [proxmox_vm_qemu.vm]
}

resource "null_resource" "ansible" {
  provisioner "local-exec" {
    command = "sleep 180; ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory.ini example-playbook.yml -u ${var.ci_user} --private-key ${var.ci_ssh_private_key}"
  }

  depends_on = [
    null_resource.create_ansible_inventory
  ]
}


output "vm_info" {
  value = [
    for vm in proxmox_vm_qemu.vm : {
      hostname = vm.name
      ip-addr  = vm.default_ipv4_address
    }
  ]
}
