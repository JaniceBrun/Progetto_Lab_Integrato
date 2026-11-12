output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_id" {
  value = module.network.public_subnet_id
}

output "private_subnet_id" {
  value = module.network.private_subnet_id
}

output "juice_public_ip" {
  description = "Elastic IP fisso Juice Shop - http://<ip>:3000"
  value       = aws_eip.juice.public_ip
}

output "waf_public_ip" {
  description = "Elastic IP fisso WAF"
  value       = aws_eip.waf.public_ip
}

output "bastion_public_ip" {
  description = "Elastic IP fisso bastion - ssh -i miaokey.pem ubuntu@<ip>"
  value       = aws_eip.bastion.public_ip
}

output "wazuh_private_ip" {
  description = "IP privato Wazuh - raggiungibile via bastion"
  value       = module.wazuh.private_ip
}

output "ssh_wazuh" {
  description = "Comando SSH per raggiungere Wazuh tramite bastion"
  value       = "ssh -i miaokey.pem -J ubuntu@${aws_eip.bastion.public_ip} ubuntu@${module.wazuh.private_ip}"
}
