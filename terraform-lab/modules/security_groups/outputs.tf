output "security_group_ids" {
  description = "ID dei security group per ruolo"
  value = {
    waf     = aws_security_group.waf.id
    bastion = aws_security_group.bastion.id
    app     = aws_security_group.app.id
    wazuh   = aws_security_group.wazuh.id
  }
}
