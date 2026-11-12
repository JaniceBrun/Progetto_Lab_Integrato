output "allocation_id" {
  description = "Allocation ID dell'EIP"
  value       = aws_eip.this.id
}

output "public_ip" {
  description = "Indirizzo IP pubblico"
  value       = aws_eip.this.public_ip
}
