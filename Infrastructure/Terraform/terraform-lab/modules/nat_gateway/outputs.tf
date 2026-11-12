output "nat_gateway_id" {
  description = "ID del NAT Gateway"
  value       = aws_nat_gateway.this.id
}
