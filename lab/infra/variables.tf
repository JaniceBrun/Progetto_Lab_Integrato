variable "region" { 
    default = "eu-south-1" 
}
variable "team_cidrs" {
  type        = list(string)
  description = "IP pubblici del team in formato x.x.x.x/32"
}
variable "bootstrap_pubkey" {
  default = "../ssh_keys/nome.pub"
}