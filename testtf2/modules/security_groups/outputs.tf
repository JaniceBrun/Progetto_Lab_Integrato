output "juice_sg_id" {
  value = aws_security_group.juice.id
}

output "waf_sg_id" {
  value = aws_security_group.waf.id
}

output "wazuh_sg_id" {
  value = aws_security_group.wazuh.id
}

output "bastion_sg_id" {
  value = aws_security_group.bastion.id
}
