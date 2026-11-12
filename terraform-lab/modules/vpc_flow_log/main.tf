resource "aws_flow_log" "this" {
  vpc_id          = var.vpc_id
  traffic_type    = "ALL"
  iam_role_arn    = var.iam_role_arn
  log_destination = var.log_group_arn

  tags = { Name = var.name }
}
