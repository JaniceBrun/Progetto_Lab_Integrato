data "aws_ami" "this" {
  most_recent = true
  owners      = [var.owner_id]

  filter {
    name   = "name"
    values = [var.name_pattern]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
