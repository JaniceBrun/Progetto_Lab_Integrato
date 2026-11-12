resource "aws_instance" "this" {
  # checkov:skip=CKV2_AWS_41:Nessun accesso alle API AWS richiesto dalle VM (least privilege): nessun instance profile
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.security_group_ids
  key_name                    = var.key_name
  associate_public_ip_address = false
  monitoring                  = true
  ebs_optimized               = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.volume_gb
    encrypted             = true
    kms_key_id            = var.kms_key_arn
    delete_on_termination = true
  }

  tags = {
    Name = var.name
    Role = var.role
  }

  lifecycle {
    ignore_changes = [ami]
  }
}
