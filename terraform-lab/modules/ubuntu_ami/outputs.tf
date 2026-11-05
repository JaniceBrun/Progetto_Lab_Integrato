output "ami_id" {
  description = "ID dell'AMI Ubuntu selezionata"
  value       = data.aws_ami.this.id
}
