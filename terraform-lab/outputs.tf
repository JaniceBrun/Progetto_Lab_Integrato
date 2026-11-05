output "vpc_id" {
  description = "ID della VPC"
  value       = module.vpc.vpc_id
}

output "instance_ids" {
  description = "ID delle EC2 per ruolo"
  value       = { for k, m in module.compute : k => m.instance_id }
}

output "private_ips" {
  description = "IP privati per ruolo"
  value       = { for k, m in module.compute : k => m.private_ip }
}

output "bastion_public_ip" {
  description = "Elastic IP del bastion"
  value       = module.vm_eips["bastion"].public_ip
}

output "waf_public_ip" {
  description = "Elastic IP del WAF (unico ingresso pubblico)"
  value       = module.vm_eips["waf"].public_ip
}

output "ansible_inventory" {
  description = "Inventory YAML per Ansible (VM private via ProxyJump sul bastion)"
  value = yamlencode({
    all = {
      vars = {
        ansible_user = var.ansible_user
      }
      children = {
        bastion = {
          hosts = {
            bastion = { ansible_host = module.vm_eips["bastion"].public_ip }
          }
        }
        managed = {
          vars = {
            ansible_ssh_common_args = "-o ProxyJump=${var.ansible_user}@${module.vm_eips["bastion"].public_ip}"
          }
          children = {
            waf = {
              hosts = { waf = { ansible_host = module.compute["waf"].private_ip } }
            }
            juiceshop = {
              hosts = { juiceshop = { ansible_host = module.compute["app"].private_ip } }
            }
            wazuh = {
              hosts = { wazuh = { ansible_host = module.compute["wazuh"].private_ip } }
            }
          }
        }
      }
    }
  })
}
