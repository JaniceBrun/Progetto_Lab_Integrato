Ecco tutti i file. Rispetto alla versione precedente ho fatto tre correzioni:

- **`modules/kms`:** il blocco condizionale della policy usa ora un'espressione `for` con `range()` invece del ternario `? [..] : []`, per evitare ambiguità di tipo.
- **`iam_state_access`:** `s3:ListBucket` non ha più la condizione sul prefisso, che poteva rompere comandi Terraform che elencano il bucket. `Get`, `Put` e `Delete` restano limitati al prefisso dello state.
- **`terraform-lab/main.tf`:** allineamento corretto per `terraform fmt`.

I `# checkov:skip` nel modulo `s3_bucket` valgono per entrambi i bucket, anche per quello dello state, dove i check passerebbero comunque.

---

# REPO `terraform-backend`

### terraform-backend/providers.tf
```hcl
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(var.tags, {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Component   = "tfstate-backend"
    })
  }
}
```

### terraform-backend/variables.tf
```hcl
variable "aws_region" {
  description = "Regione AWS del backend"
  type        = string
}

variable "project" {
  description = "Nome progetto"
  type        = string
}

variable "environment" {
  description = "Ambiente"
  type        = string
}

variable "tags" {
  description = "Tag aggiuntivi"
  type        = map(string)
  default     = {}
}

variable "state_bucket_name" {
  description = "Nome globalmente univoco del bucket tfstate"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket_name))
    error_message = "Nome bucket S3 non valido."
  }
}

variable "state_key_prefix" {
  description = "Prefisso delle chiavi di state nel bucket (es. lab)"
  type        = string
  default     = "lab"
}

variable "allowed_principal_arns" {
  description = "ARN (anche con wildcard) dei principal autorizzati al bucket. Deve includere chi esegue l'apply."
  type        = list(string)

  validation {
    condition     = length(var.allowed_principal_arns) > 0
    error_message = "Indicare almeno un principal autorizzato."
  }
}

variable "kms_deletion_window_days" {
  description = "Finestra di cancellazione della CMK (7-30)"
  type        = number
  default     = 30
}

variable "noncurrent_version_retention_days" {
  description = "Giorni di conservazione delle versioni non correnti dello state"
  type        = number
  default     = 90
}

variable "log_retention_days" {
  description = "Giorni di conservazione dei log di accesso S3"
  type        = number
  default     = 365
}
```

### terraform-backend/main.tf
```hcl
locals {
  logs_bucket_name = "${var.state_bucket_name}-logs"
  state_bucket_arn = "arn:aws:s3:::${var.state_bucket_name}"
  logs_bucket_arn  = "arn:aws:s3:::${local.logs_bucket_name}"

  logs_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [local.logs_bucket_arn, "${local.logs_bucket_arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "AllowS3ServerAccessLogDelivery"
        Effect    = "Allow"
        Principal = { Service = "logging.s3.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${local.logs_bucket_arn}/*"
        Condition = { ArnLike = { "aws:SourceArn" = local.state_bucket_arn } }
      }
    ]
  })

  state_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [local.state_bucket_arn, "${local.state_bucket_arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "DenyBucketDeletion"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:DeleteBucket"
        Resource  = local.state_bucket_arn
      },
      {
        Sid       = "DenyUnlistedPrincipals"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [local.state_bucket_arn, "${local.state_bucket_arn}/*"]
        Condition = { StringNotLike = { "aws:PrincipalArn" = var.allowed_principal_arns } }
      }
    ]
  })
}

module "kms" {
  source = "./modules/kms"

  name                    = "${var.project}-${var.environment}-tfstate"
  description             = "CMK per la cifratura del tfstate di ${var.project}-${var.environment}"
  deletion_window_in_days = var.kms_deletion_window_days
}

module "logs_bucket" {
  source = "./modules/s3_bucket"

  bucket_name                       = local.logs_bucket_name
  noncurrent_version_retention_days = 30
  expiration_days                   = var.log_retention_days
}

module "logs_bucket_policy" {
  source = "./modules/s3_bucket_policy"

  bucket_id   = module.logs_bucket.bucket_id
  policy_json = local.logs_policy

  depends_on = [module.logs_bucket]
}

module "state_bucket" {
  source = "./modules/s3_bucket"

  bucket_name                       = var.state_bucket_name
  kms_key_arn                       = module.kms.key_arn
  logging_target_bucket             = module.logs_bucket.bucket_id
  logging_target_prefix             = "state-access/"
  noncurrent_version_retention_days = var.noncurrent_version_retention_days

  depends_on = [module.logs_bucket_policy]
}

# Applicata per ultima: evita il lock-out durante l'apply
module "state_bucket_policy" {
  source = "./modules/s3_bucket_policy"

  bucket_id   = module.state_bucket.bucket_id
  policy_json = local.state_policy

  depends_on = [module.state_bucket]
}

module "iam_state_access" {
  source = "./modules/iam_state_access"

  policy_name      = "${var.project}-${var.environment}-tfstate-access"
  bucket_arn       = module.state_bucket.bucket_arn
  kms_key_arn      = module.kms.key_arn
  state_key_prefix = var.state_key_prefix
}
```

### terraform-backend/outputs.tf
```hcl
output "state_bucket_name" {
  description = "Bucket S3 del tfstate"
  value       = module.state_bucket.bucket_id
}

output "state_kms_key_arn" {
  description = "ARN della chiave KMS del tfstate"
  value       = module.kms.key_arn
}

output "state_access_policy_arn" {
  description = "Policy IAM least-privilege da allegare ai ruoli del team"
  value       = module.iam_state_access.policy_arn
}

output "backend_config" {
  description = "Contenuto per backend.hcl della repo principale"
  value       = <<-EOT
    bucket       = "${module.state_bucket.bucket_id}"
    key          = "${var.state_key_prefix}/terraform.tfstate"
    region       = "${var.aws_region}"
    encrypt      = true
    kms_key_id   = "${module.kms.key_arn}"
    use_lockfile = true
  EOT
}
```

### terraform-backend/terraform.tfvars.example
```hcl
aws_region             = "eu-south-1"
project                = "its-lab"
environment            = "lab"
state_bucket_name      = "its-lab-tfstate-CAMBIAMI-univoco"
state_key_prefix       = "lab"
allowed_principal_arns = ["arn:aws:iam::111122223333:role/terraform-admin"]
```

### terraform-backend/.gitignore
```
.terraform/
*.tfstate
*.tfstate.*
terraform.tfvars
*.auto.tfvars
backend.hcl
crash.log
```

### terraform-backend/modules/kms/variables.tf
```hcl
variable "name" {
  description = "Nome della chiave (alias: alias/<name>)"
  type        = string
}

variable "description" {
  description = "Descrizione della chiave"
  type        = string
}

variable "deletion_window_in_days" {
  description = "Finestra di cancellazione (7-30 giorni)"
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "La finestra deve essere tra 7 e 30 giorni."
  }
}

variable "allow_cloudwatch_logs" {
  description = "Se true, consente a CloudWatch Logs di usare la chiave"
  type        = bool
  default     = false
}
```

### terraform-backend/modules/kms/main.tf
```hcl
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  base_statements = [
    {
      Sid       = "EnableIAMPolicies"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }
  ]

  logs_statements = [
    for i in range(var.allow_cloudwatch_logs ? 1 : 0) : {
      Sid       = "AllowCloudWatchLogs"
      Effect    = "Allow"
      Principal = { Service = "logs.${data.aws_region.current.name}.amazonaws.com" }
      Action = [
        "kms:Encrypt*",
        "kms:Decrypt*",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:Describe*"
      ]
      Resource = "*"
      Condition = {
        ArnLike = {
          "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:*"
        }
      }
    }
  ]
}

resource "aws_kms_key" "this" {
  description             = var.description
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = concat(local.base_statements, local.logs_statements)
  })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.this.key_id
}
```

### terraform-backend/modules/kms/outputs.tf
```hcl
output "key_arn" {
  description = "ARN della chiave KMS"
  value       = aws_kms_key.this.arn
}

output "key_id" {
  description = "ID della chiave KMS"
  value       = aws_kms_key.this.key_id
}
```

### terraform-backend/modules/s3_bucket/variables.tf
```hcl
variable "bucket_name" {
  description = "Nome del bucket"
  type        = string
}

variable "kms_key_arn" {
  description = "CMK per SSE-KMS; se null usa SSE-S3 (AES256)"
  type        = string
  default     = null
}

variable "logging_target_bucket" {
  description = "Bucket di destinazione dei log di accesso; se null il logging è disattivato"
  type        = string
  default     = null
}

variable "logging_target_prefix" {
  description = "Prefisso dei log di accesso"
  type        = string
  default     = ""
}

variable "noncurrent_version_retention_days" {
  description = "Giorni di conservazione delle versioni non correnti"
  type        = number
  default     = 90
}

variable "expiration_days" {
  description = "Scadenza degli oggetti correnti; se null non scadono"
  type        = number
  default     = null
}
```

### terraform-backend/modules/s3_bucket/main.tf
```hcl
resource "aws_s3_bucket" "this" {
  # checkov:skip=CKV_AWS_144:Replica cross-region fuori scope del laboratorio
  # checkov:skip=CKV2_AWS_62:Notifiche eventi non richieste
  # checkov:skip=CKV_AWS_18:Il bucket dei log è il target del logging e non si logga su se stesso
  # checkov:skip=CKV_AWS_145:Il bucket dei log usa SSE-S3 perché il server access logging non supporta SSE-KMS sul target
  bucket        = var.bucket_name
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    bucket_key_enabled = var.kms_key_arn != null

    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_logging" "this" {
  count = var.logging_target_bucket == null ? 0 : 1

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.logging_target_bucket
  target_prefix = var.logging_target_prefix
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "retention"
    status = "Enabled"

    filter {}

    dynamic "expiration" {
      for_each = var.expiration_days == null ? [] : [var.expiration_days]

      content {
        days = expiration.value
      }
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}
```

### terraform-backend/modules/s3_bucket/outputs.tf
```hcl
output "bucket_id" {
  description = "Nome del bucket"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "ARN del bucket"
  value       = aws_s3_bucket.this.arn
}
```

### terraform-backend/modules/s3_bucket_policy/variables.tf
```hcl
variable "bucket_id" {
  description = "Bucket a cui applicare la policy"
  type        = string
}

variable "policy_json" {
  description = "Policy in formato JSON"
  type        = string
}
```

### terraform-backend/modules/s3_bucket_policy/main.tf
```hcl
resource "aws_s3_bucket_policy" "this" {
  bucket = var.bucket_id
  policy = var.policy_json
}
```

### terraform-backend/modules/s3_bucket_policy/outputs.tf
```hcl
output "bucket_id" {
  description = "Bucket a cui è applicata la policy"
  value       = aws_s3_bucket_policy.this.bucket
}
```

### terraform-backend/modules/iam_state_access/variables.tf
```hcl
variable "policy_name" {
  description = "Nome della policy IAM"
  type        = string
}

variable "bucket_arn" {
  description = "ARN del bucket tfstate"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN della CMK del tfstate"
  type        = string
}

variable "state_key_prefix" {
  description = "Prefisso delle chiavi di state accessibili"
  type        = string
}
```

### terraform-backend/modules/iam_state_access/main.tf
```hcl
data "aws_iam_policy_document" "this" {
  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [var.bucket_arn]
  }

  statement {
    sid       = "ReadWriteStateObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${var.bucket_arn}/${var.state_key_prefix}/*"]
  }

  statement {
    sid       = "UseStateKmsKey"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_policy" "this" {
  name        = var.policy_name
  description = "Accesso minimo al tfstate (prefisso ${var.state_key_prefix}) e alla relativa CMK"
  policy      = data.aws_iam_policy_document.this.json
}
```

### terraform-backend/modules/iam_state_access/outputs.tf
```hcl
output "policy_arn" {
  description = "ARN della policy IAM"
  value       = aws_iam_policy.this.arn
}
```

---

# REPO `terraform-lab`

### terraform-lab/providers.tf
```hcl
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }

  # Configurazione parziale: i valori arrivano da backend.hcl
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(var.tags, {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    })
  }
}
```

### terraform-lab/variables.tf
```hcl
variable "aws_region" {
  description = "Regione AWS"
  type        = string
}

variable "availability_zone" {
  description = "AZ delle subnet (es. eu-south-1a)"
  type        = string
}

variable "project" {
  description = "Nome progetto"
  type        = string
}

variable "environment" {
  description = "Ambiente"
  type        = string
}

variable "tags" {
  description = "Tag aggiuntivi"
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "CIDR della VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR subnet pubblica"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR subnet privata"
  type        = string
  default     = "10.0.2.0/24"
}

variable "team_ssh_cidrs" {
  description = "IP del team (solo /32) autorizzati a SSH sul bastion"
  type        = list(string)

  validation {
    condition     = length(var.team_ssh_cidrs) > 0 && alltrue([for c in var.team_ssh_cidrs : can(cidrhost(c, 0)) && endswith(c, "/32")])
    error_message = "team_ssh_cidrs deve contenere almeno un CIDR valido di tipo /32."
  }
}

variable "bootstrap_public_key" {
  description = "Chiave SSH PUBBLICA di bootstrap"
  type        = string

  validation {
    condition     = startswith(var.bootstrap_public_key, "ssh-")
    error_message = "Fornire una chiave pubblica SSH (ssh-ed25519 / ssh-rsa ...)."
  }
}

variable "instance_sizing" {
  description = "Tipo istanza e volume root per ruolo"
  type = object({
    waf = optional(object({
      instance_type = optional(string, "t3.small")
      volume_gb     = optional(number, 20)
    }), {})
    bastion = optional(object({
      instance_type = optional(string, "t3.micro")
      volume_gb     = optional(number, 10)
    }), {})
    app = optional(object({
      instance_type = optional(string, "t3.small")
      volume_gb     = optional(number, 20)
    }), {})
    wazuh = optional(object({
      instance_type = optional(string, "t3.large")
      volume_gb     = optional(number, 50)
    }), {})
  })
  default = {}
}

variable "flow_logs_retention_days" {
  description = "Retention dei VPC Flow Logs"
  type        = number
  default     = 365
}

variable "ansible_user" {
  description = "Utente SSH usato da Ansible"
  type        = string
  default     = "ubuntu"
}
```

### terraform-lab/main.tf
```hcl
locals {
  name_prefix = "${var.project}-${var.environment}"

  vms = {
    waf     = { subnet = "public", public_ip = true, sizing = var.instance_sizing.waf }
    bastion = { subnet = "public", public_ip = true, sizing = var.instance_sizing.bastion }
    app     = { subnet = "private", public_ip = false, sizing = var.instance_sizing.app }
    wazuh   = { subnet = "private", public_ip = false, sizing = var.instance_sizing.wazuh }
  }

  subnet_ids = {
    public  = module.subnet_public.subnet_id
    private = module.subnet_private.subnet_id
  }

  public_vms = { for k, v in local.vms : k => v if v.public_ip }
}

# ------------------------- Cifratura -------------------------
module "kms" {
  source = "./modules/kms"

  name                    = "${local.name_prefix}-lab"
  description             = "CMK per EBS e CloudWatch Logs di ${local.name_prefix}"
  allow_cloudwatch_logs   = true
  deletion_window_in_days = 30
}

# ------------------------- Networking -------------------------
module "vpc" {
  source = "./modules/vpc"

  name_prefix = local.name_prefix
  cidr_block  = var.vpc_cidr
}

module "internet_gateway" {
  source = "./modules/internet_gateway"

  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id
}

module "subnet_public" {
  source = "./modules/subnet"

  name              = "${local.name_prefix}-public"
  tier              = "public"
  vpc_id            = module.vpc.vpc_id
  cidr_block        = var.public_subnet_cidr
  availability_zone = var.availability_zone
}

module "subnet_private" {
  source = "./modules/subnet"

  name              = "${local.name_prefix}-private"
  tier              = "private"
  vpc_id            = module.vpc.vpc_id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone
}

module "nat_eip" {
  source = "./modules/elastic_ip"

  name = "${local.name_prefix}-nat-eip"

  depends_on = [module.internet_gateway]
}

module "nat_gateway" {
  source = "./modules/nat_gateway"

  name          = "${local.name_prefix}-nat"
  subnet_id     = module.subnet_public.subnet_id
  allocation_id = module.nat_eip.allocation_id

  depends_on = [module.internet_gateway]
}

module "route_table_public" {
  source = "./modules/route_table"

  name       = "${local.name_prefix}-rt-public"
  vpc_id     = module.vpc.vpc_id
  subnet_id  = module.subnet_public.subnet_id
  gateway_id = module.internet_gateway.internet_gateway_id
}

module "route_table_private" {
  source = "./modules/route_table"

  name           = "${local.name_prefix}-rt-private"
  vpc_id         = module.vpc.vpc_id
  subnet_id      = module.subnet_private.subnet_id
  nat_gateway_id = module.nat_gateway.nat_gateway_id
}

# ------------------------- VPC Flow Logs -------------------------
module "flow_log_group" {
  source = "./modules/cloudwatch_log_group"

  name              = "/aws/vpc/${local.name_prefix}-flow-logs"
  retention_in_days = var.flow_logs_retention_days
  kms_key_arn       = module.kms.key_arn
}

module "flow_log_role" {
  source = "./modules/iam_flow_logs_role"

  name          = "${local.name_prefix}-flow-logs"
  log_group_arn = module.flow_log_group.log_group_arn
}

module "vpc_flow_log" {
  source = "./modules/vpc_flow_log"

  name          = "${local.name_prefix}-flow-log"
  vpc_id        = module.vpc.vpc_id
  iam_role_arn  = module.flow_log_role.role_arn
  log_group_arn = module.flow_log_group.log_group_arn
}

# ------------------------- Security group -------------------------
module "security_groups" {
  source = "./modules/security_groups"

  name_prefix    = local.name_prefix
  vpc_id         = module.vpc.vpc_id
  team_ssh_cidrs = var.team_ssh_cidrs
}

# ------------------------- Compute -------------------------
module "ubuntu_ami" {
  source = "./modules/ubuntu_ami"
}

module "key_pair" {
  source = "./modules/key_pair"

  key_name   = "${local.name_prefix}-bootstrap"
  public_key = var.bootstrap_public_key
}

module "compute" {
  source   = "./modules/compute"
  for_each = local.vms

  name               = "${local.name_prefix}-${each.key}"
  role               = each.key
  ami_id             = module.ubuntu_ami.ami_id
  instance_type      = each.value.sizing.instance_type
  volume_gb          = each.value.sizing.volume_gb
  subnet_id          = local.subnet_ids[each.value.subnet]
  security_group_ids = [module.security_groups.security_group_ids[each.key]]
  key_name           = module.key_pair.key_name
  kms_key_arn        = module.kms.key_arn

  depends_on = [module.route_table_private]
}

module "vm_eips" {
  source   = "./modules/elastic_ip"
  for_each = local.public_vms

  name        = "${local.name_prefix}-${each.key}-eip"
  instance_id = module.compute[each.key].instance_id

  depends_on = [module.internet_gateway]
}
```

### terraform-lab/outputs.tf
```hcl
output "vpc_id" {
  description = "ID della VPC"
  value       = module.vpc.vpc_id
}

output "instance_ids" {
  description = "ID delle EC2 per ruolo"
  value       = { for k, m in module.compute : k => m.instance_id }
}

output "private_ips" {
  description = "IP privati per ruolo"
  value       = { for k, m in module.compute : k => m.private_ip }
}

output "bastion_public_ip" {
  description = "Elastic IP del bastion"
  value       = module.vm_eips["bastion"].public_ip
}

output "waf_public_ip" {
  description = "Elastic IP del WAF (unico ingresso pubblico)"
  value       = module.vm_eips["waf"].public_ip
}

output "ansible_inventory" {
  description = "Inventory YAML per Ansible (VM private via ProxyJump sul bastion)"
  value = yamlencode({
    all = {
      vars = {
        ansible_user = var.ansible_user
      }
      children = {
        bastion = {
          hosts = {
            bastion = { ansible_host = module.vm_eips["bastion"].public_ip }
          }
        }
        managed = {
          vars = {
            ansible_ssh_common_args = "-o ProxyJump=${var.ansible_user}@${module.vm_eips["bastion"].public_ip}"
          }
          children = {
            waf = {
              hosts = { waf = { ansible_host = module.compute["waf"].private_ip } }
            }
            juiceshop = {
              hosts = { juiceshop = { ansible_host = module.compute["app"].private_ip } }
            }
            wazuh = {
              hosts = { wazuh = { ansible_host = module.compute["wazuh"].private_ip } }
            }
          }
        }
      }
    }
  })
}
```

### terraform-lab/backend.hcl.example
```hcl
bucket       = "its-lab-tfstate-CAMBIAMI-univoco"
key          = "lab/terraform.tfstate"
region       = "eu-south-1"
encrypt      = true
kms_key_id   = "arn:aws:kms:eu-south-1:111122223333:key/XXXXXXXX"
use_lockfile = true
```

### terraform-lab/terraform.tfvars.example
```hcl
aws_region           = "eu-south-1"
availability_zone    = "eu-south-1a"
project              = "its-lab"
environment          = "lab"
team_ssh_cidrs       = ["203.0.113.10/32"]
bootstrap_public_key = "ssh-ed25519 AAAA... chiave-pubblica"
```

### terraform-lab/.gitignore
```
.terraform/
*.tfstate
*.tfstate.*
terraform.tfvars
*.auto.tfvars
backend.hcl
crash.log
```

### terraform-lab/modules/kms/ (variables.tf, main.tf, outputs.tf)
Identici ai file di `terraform-backend/modules/kms/` riportati sopra, da copiare senza modifiche.

### terraform-lab/modules/vpc/variables.tf
```hcl
variable "name_prefix" {
  description = "Prefisso di naming"
  type        = string
}

variable "cidr_block" {
  description = "CIDR della VPC"
  type        = string
}
```

### terraform-lab/modules/vpc/main.tf
```hcl
resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

# Il default SG viene svuotato: nessun traffico consentito
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name_prefix}-default-sg-locked" }
}
```

### terraform-lab/modules/vpc/outputs.tf
```hcl
output "vpc_id" {
  description = "ID della VPC"
  value       = aws_vpc.this.id
}
```

### terraform-lab/modules/internet_gateway/variables.tf
```hcl
variable "name_prefix" {
  description = "Prefisso di naming"
  type        = string
}

variable "vpc_id" {
  description = "VPC a cui collegare l'IGW"
  type        = string
}
```

### terraform-lab/modules/internet_gateway/main.tf
```hcl
resource "aws_internet_gateway" "this" {
  vpc_id = var.vpc_id

  tags = { Name = "${var.name_prefix}-igw" }
}
```

### terraform-lab/modules/internet_gateway/outputs.tf
```hcl
output "internet_gateway_id" {
  description = "ID dell'Internet Gateway"
  value       = aws_internet_gateway.this.id
}
```

### terraform-lab/modules/subnet/variables.tf
```hcl
variable "name" {
  description = "Nome completo della subnet"
  type        = string
}

variable "tier" {
  description = "Livello della subnet (public/private)"
  type        = string

  validation {
    condition     = contains(["public", "private"], var.tier)
    error_message = "tier deve essere public o private."
  }
}

variable "vpc_id" {
  description = "VPC della subnet"
  type        = string
}

variable "cidr_block" {
  description = "CIDR della subnet"
  type        = string
}

variable "availability_zone" {
  description = "Availability zone"
  type        = string
}
```

### terraform-lab/modules/subnet/main.tf
```hcl
resource "aws_subnet" "this" {
  vpc_id                  = var.vpc_id
  cidr_block              = var.cidr_block
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name = var.name
    Tier = var.tier
  }
}
```

### terraform-lab/modules/subnet/outputs.tf
```hcl
output "subnet_id" {
  description = "ID della subnet"
  value       = aws_subnet.this.id
}
```

### terraform-lab/modules/elastic_ip/variables.tf
```hcl
variable "name" {
  description = "Nome dell'Elastic IP"
  type        = string
}

variable "instance_id" {
  description = "Istanza a cui associare l'EIP; null per un EIP non associato (es. NAT)"
  type        = string
  default     = null
}
```

### terraform-lab/modules/elastic_ip/main.tf
```hcl
resource "aws_eip" "this" {
  domain   = "vpc"
  instance = var.instance_id

  tags = { Name = var.name }
}
```

### terraform-lab/modules/elastic_ip/outputs.tf
```hcl
output "allocation_id" {
  description = "Allocation ID dell'EIP"
  value       = aws_eip.this.id
}

output "public_ip" {
  description = "Indirizzo IP pubblico"
  value       = aws_eip.this.public_ip
}
```

### terraform-lab/modules/nat_gateway/variables.tf
```hcl
variable "name" {
  description = "Nome del NAT Gateway"
  type        = string
}

variable "subnet_id" {
  description = "Subnet pubblica che ospita il NAT"
  type        = string
}

variable "allocation_id" {
  description = "Allocation ID dell'Elastic IP del NAT"
  type        = string
}
```

### terraform-lab/modules/nat_gateway/main.tf
```hcl
resource "aws_nat_gateway" "this" {
  allocation_id = var.allocation_id
  subnet_id     = var.subnet_id

  tags = { Name = var.name }
}
```

### terraform-lab/modules/nat_gateway/outputs.tf
```hcl
output "nat_gateway_id" {
  description = "ID del NAT Gateway"
  value       = aws_nat_gateway.this.id
}
```

### terraform-lab/modules/route_table/variables.tf
```hcl
variable "name" {
  description = "Nome della route table"
  type        = string
}

variable "vpc_id" {
  description = "VPC della route table"
  type        = string
}

variable "subnet_id" {
  description = "Subnet da associare"
  type        = string
}

variable "gateway_id" {
  description = "Internet Gateway per la route 0.0.0.0/0 (alternativo a nat_gateway_id)"
  type        = string
  default     = null
}

variable "nat_gateway_id" {
  description = "NAT Gateway per la route 0.0.0.0/0 (alternativo a gateway_id)"
  type        = string
  default     = null
}
```

### terraform-lab/modules/route_table/main.tf
```hcl
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
```

### terraform-lab/modules/route_table/outputs.tf
```hcl
output "route_table_id" {
  description = "ID della route table"
  value       = aws_route_table.this.id
}
```

### terraform-lab/modules/cloudwatch_log_group/variables.tf
```hcl
variable "name" {
  description = "Nome del log group"
  type        = string
}

variable "retention_in_days" {
  description = "Retention in giorni"
  type        = number
}

variable "kms_key_arn" {
  description = "CMK per cifrare il log group"
  type        = string
}
```

### terraform-lab/modules/cloudwatch_log_group/main.tf
```hcl
resource "aws_cloudwatch_log_group" "this" {
  name              = var.name
  retention_in_days = var.retention_in_days
  kms_key_id        = var.kms_key_arn
}
```

### terraform-lab/modules/cloudwatch_log_group/outputs.tf
```hcl
output "log_group_arn" {
  description = "ARN del log group"
  value       = aws_cloudwatch_log_group.this.arn
}
```

### terraform-lab/modules/iam_flow_logs_role/variables.tf
```hcl
variable "name" {
  description = "Nome del ruolo IAM"
  type        = string
}

variable "log_group_arn" {
  description = "ARN del log group in cui il ruolo può scrivere"
  type        = string
}
```

### terraform-lab/modules/iam_flow_logs_role/main.tf
```hcl
data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "publish" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = [var.log_group_arn, "${var.log_group_arn}:*"]
  }
}

resource "aws_iam_role" "this" {
  name               = var.name
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy" "this" {
  name   = "${var.name}-publish"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.publish.json
}
```

### terraform-lab/modules/iam_flow_logs_role/outputs.tf
```hcl
output "role_arn" {
  description = "ARN del ruolo IAM"
  value       = aws_iam_role.this.arn
}
```

### terraform-lab/modules/vpc_flow_log/variables.tf
```hcl
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
```

### terraform-lab/modules/vpc_flow_log/main.tf
```hcl
resource "aws_flow_log" "this" {
  vpc_id          = var.vpc_id
  traffic_type    = "ALL"
  iam_role_arn    = var.iam_role_arn
  log_destination = var.log_group_arn

  tags = { Name = var.name }
}
```

### terraform-lab/modules/vpc_flow_log/outputs.tf
```hcl
output "flow_log_id" {
  description = "ID del flow log"
  value       = aws_flow_log.this.id
}
```

### terraform-lab/modules/security_groups/variables.tf
```hcl
variable "name_prefix" {
  description = "Prefisso di naming"
  type        = string
}

variable "vpc_id" {
  description = "VPC in cui creare i security group"
  type        = string
}

variable "team_ssh_cidrs" {
  description = "CIDR /32 del team autorizzati a SSH sul bastion"
  type        = list(string)
}
```

### terraform-lab/modules/security_groups/sg.tf
```hcl
# Solo definizione dei security group. Le regole sono in sg-rules.tf.

resource "aws_security_group" "waf" {
  name        = "${var.name_prefix}-sg-waf"
  description = "VM WAF: reverse proxy + ModSecurity, unico ingresso pubblico"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-sg-waf" }
}

resource "aws_security_group" "bastion" {
  name        = "${var.name_prefix}-sg-bastion"
  description = "VM bastion: unico accesso amministrativo"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-sg-bastion" }
}

resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-sg-app"
  description = "VM Juice Shop: raggiungibile solo dal WAF"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-sg-app" }
}

resource "aws_security_group" "wazuh" {
  name        = "${var.name_prefix}-sg-wazuh"
  description = "VM Wazuh SIEM: raccolta log centralizzata"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name_prefix}-sg-wazuh" }
}
```

### terraform-lab/modules/security_groups/sg-rules.tf
```hcl
locals {
  sg_ids = {
    waf     = aws_security_group.waf.id
    bastion = aws_security_group.bastion.id
    app     = aws_security_group.app.id
    wazuh   = aws_security_group.wazuh.id
  }

  # Ingress con sorgente = altro SG
  ingress_from_sg = {
    # ===================== sg-waf =====================
    waf_ssh_from_bastion = { sg = "waf", source = "bastion", port = 22, description = "Amministrazione via bastion" }

    # ===================== sg-app =====================
    app_3000_from_waf    = { sg = "app", source = "waf", port = 3000, description = "Richieste inoltrate dal reverse proxy" }
    app_ssh_from_bastion = { sg = "app", source = "bastion", port = 22, description = "Amministrazione via bastion" }

    # ===================== sg-wazuh =====================
    wazuh_1514_from_waf    = { sg = "wazuh", source = "waf", port = 1514, description = "Ricezione log dall'agent WAF" }
    wazuh_1514_from_app    = { sg = "wazuh", source = "app", port = 1514, description = "Ricezione log dall'agent Juice Shop" }
    wazuh_1515_from_waf    = { sg = "wazuh", source = "waf", port = 1515, description = "Registrazione agent WAF" }
    wazuh_1515_from_app    = { sg = "wazuh", source = "app", port = 1515, description = "Registrazione agent Juice Shop" }
    wazuh_ssh_from_bastion = { sg = "wazuh", source = "bastion", port = 22, description = "Amministrazione via bastion" }
    wazuh_443_from_bastion = { sg = "wazuh", source = "bastion", port = 443, description = "Dashboard Wazuh tramite tunnel dal bastion" }
  }

  # Ingress da Internet
  ingress_from_internet = {
    # ===================== sg-waf =====================
    waf_80  = { sg = "waf", port = 80, description = "Traffico HTTP di utenti e Red Team" }
    waf_443 = { sg = "waf", port = 443, description = "Traffico HTTPS di utenti e Red Team" }
  }

  # Egress verso altro SG
  egress_to_sg = {
    # ===================== sg-waf =====================
    waf_3000_to_app   = { sg = "waf", destination = "app", port = 3000, description = "Inoltro richieste a Juice Shop" }
    waf_1514_to_wazuh = { sg = "waf", destination = "wazuh", port = 1514, description = "Invio eventi/log dell'agent" }
    waf_1515_to_wazuh = { sg = "waf", destination = "wazuh", port = 1515, description = "Registrazione agent sul manager" }

    # ===================== sg-bastion =====================
    bastion_22_to_waf    = { sg = "bastion", destination = "waf", port = 22, description = "SSH ProxyJump verso WAF" }
    bastion_22_to_app    = { sg = "bastion", destination = "app", port = 22, description = "SSH ProxyJump verso Juice Shop" }
    bastion_22_to_wazuh  = { sg = "bastion", destination = "wazuh", port = 22, description = "SSH ProxyJump verso Wazuh" }
    bastion_443_to_wazuh = { sg = "bastion", destination = "wazuh", port = 443, description = "Dashboard Wazuh via forward dal bastion" }

    # ===================== sg-app =====================
    app_1514_to_wazuh = { sg = "app", destination = "wazuh", port = 1514, description = "Invio eventi/log dell'agent" }
    app_1515_to_wazuh = { sg = "app", destination = "wazuh", port = 1515, description = "Registrazione agent sul manager" }

    # ===================== sg-wazuh =====================
    # (solo egress verso Internet, vedi egress_to_internet)
  }

  # Egress HTTP/HTTPS verso Internet: WAF e bastion via IGW, app e wazuh via NAT
  egress_to_internet = {
    for p in setproduct(["waf", "bastion", "app", "wazuh"], [80, 443]) :
    "${p[0]}_${p[1]}" => {
      sg          = p[0]
      port        = p[1]
      description = "Aggiornamenti, pacchetti e immagini (HTTP/HTTPS)"
    }
  }
}

# ---------------- Ingress da altri SG ----------------
resource "aws_vpc_security_group_ingress_rule" "from_sg" {
  for_each = local.ingress_from_sg

  security_group_id            = local.sg_ids[each.value.sg]
  referenced_security_group_id = local.sg_ids[each.value.source]
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  description                  = each.value.description
}

# ---------------- Ingress da Internet (solo WAF) ----------------
resource "aws_vpc_security_group_ingress_rule" "from_internet" {
  for_each = local.ingress_from_internet

  security_group_id = local.sg_ids[each.value.sg]
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  description       = each.value.description
}

# ---------------- Ingress SSH dal team (solo bastion) ----------------
# ===================== sg-bastion =====================
resource "aws_vpc_security_group_ingress_rule" "bastion_ssh_from_team" {
  for_each = toset(var.team_ssh_cidrs)

  security_group_id = aws_security_group.bastion.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  description       = "Accesso SSH dal team"
}

# ---------------- Egress verso altri SG ----------------
resource "aws_vpc_security_group_egress_rule" "to_sg" {
  for_each = local.egress_to_sg

  security_group_id            = local.sg_ids[each.value.sg]
  referenced_security_group_id = local.sg_ids[each.value.destination]
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  description                  = each.value.description
}

# ---------------- Egress verso Internet ----------------
resource "aws_vpc_security_group_egress_rule" "to_internet" {
  for_each = local.egress_to_internet

  security_group_id = local.sg_ids[each.value.sg]
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  description       = each.value.description
}
```

### terraform-lab/modules/security_groups/outputs.tf
```hcl
output "security_group_ids" {
  description = "ID dei security group per ruolo"
  value = {
    waf     = aws_security_group.waf.id
    bastion = aws_security_group.bastion.id
    app     = aws_security_group.app.id
    wazuh   = aws_security_group.wazuh.id
  }
}
```

### terraform-lab/modules/ubuntu_ami/variables.tf
```hcl
variable "owner_id" {
  description = "Owner ID pubblico dell'AMI (Canonical)"
  type        = string
  default     = "099720109477"
}

variable "name_pattern" {
  description = "Pattern del nome AMI Ubuntu"
  type        = string
  default     = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
}
```

### terraform-lab/modules/ubuntu_ami/main.tf
```hcl
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
```

### terraform-lab/modules/ubuntu_ami/outputs.tf
```hcl
output "ami_id" {
  description = "ID dell'AMI Ubuntu selezionata"
  value       = data.aws_ami.this.id
}
```

### terraform-lab/modules/key_pair/variables.tf
```hcl
variable "key_name" {
  description = "Nome della key pair"
  type        = string
}

variable "public_key" {
  description = "Chiave SSH pubblica"
  type        = string
}
```

### terraform-lab/modules/key_pair/main.tf
```hcl
resource "aws_key_pair" "this" {
  key_name   = var.key_name
  public_key = var.public_key
}
```

### terraform-lab/modules/key_pair/outputs.tf
```hcl
output "key_name" {
  description = "Nome della key pair"
  value       = aws_key_pair.this.key_name
}
```

### terraform-lab/modules/compute/variables.tf
```hcl
variable "name" {
  description = "Nome completo dell'istanza"
  type        = string
}

variable "role" {
  description = "Ruolo della VM (waf, bastion, app, wazuh)"
  type        = string
}

variable "ami_id" {
  description = "AMI da usare"
  type        = string
}

variable "instance_type" {
  description = "Tipo di istanza"
  type        = string
}

variable "volume_gb" {
  description = "Dimensione del volume root in GB"
  type        = number
}

variable "subnet_id" {
  description = "Subnet dell'istanza"
  type        = string
}

variable "security_group_ids" {
  description = "Security group associati"
  type        = list(string)
}

variable "key_name" {
  description = "Key pair di bootstrap"
  type        = string
}

variable "kms_key_arn" {
  description = "CMK per cifrare il volume root"
  type        = string
}
```

### terraform-lab/modules/compute/main.tf
```hcl
resource "aws_instance" "this" {
  # checkov:skip=CKV2_AWS_41:Nessun accesso alle API AWS richiesto dalle VM (least privilege): nessun instance profile
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.security_group_ids
  key_name                    = var.key_name
  associate_public_ip_address = false
  monitoring                  = true
  ebs_optimized               = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.volume_gb
    encrypted             = true
    kms_key_id            = var.kms_key_arn
    delete_on_termination = true
  }

  tags = {
    Name = var.name
    Role = var.role
  }

  lifecycle {
    ignore_changes = [ami]
  }
}
```

### terraform-lab/modules/compute/outputs.tf
```hcl
output "instance_id" {
  description = "ID dell'istanza"
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "IP privato dell'istanza"
  value       = aws_instance.this.private_ip
}
```

---

**Prima dell'uso:** lancia `terraform fmt -recursive` e `terraform validate` in entrambe le repo. Non ho potuto eseguirli qui.