output "instance_id" {
  description = "ID dell'istanza"
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "IP privato dell'istanza"
  value       = aws_instance.this.private_ip
}
