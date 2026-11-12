resource "aws_route_table" "this" {
  vpc_id = var.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    gateway_id     = var.gateway_id
    nat_gateway_id = var.nat_gateway_id
  }

  tags = { Name = var.name }

  lifecycle {
    precondition {
      condition     = (var.gateway_id == null) != (var.nat_gateway_id == null)
      error_message = "Indicare esattamente uno tra gateway_id e nat_gateway_id."
    }
  }
}

resource "aws_route_table_association" "this" {
  subnet_id      = var.subnet_id
  route_table_id = aws_route_table.this.id
}
