variable "name" {
  description = "Nome del flow log"
  type        = string
}

variable "vpc_id" {
  description = "VPC da monitorare"
  type        = string
}

variable "iam_role_arn" {
  description = "Ruolo IAM usato dal servizio flow logs"
  type        = string
}

variable "log_group_arn" {
  description = "Log group di destinazione"
  type        = string
}
