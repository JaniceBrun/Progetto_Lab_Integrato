variable "name" {
  type = string
}

variable "role" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "volume_gb" {
  type = number
}

variable "subnet_id" {
  type = string
}

variable "security_group_ids" {
  type = list(string)
}

variable "key_name" {
  type    = string
  default = ""
}

variable "lab_role_name" {
  type = string
}

variable "associate_public_ip" {
  type    = bool
  default = false
}

variable "user_data" {
  description = "Script cloud-init da eseguire al primo avvio"
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
