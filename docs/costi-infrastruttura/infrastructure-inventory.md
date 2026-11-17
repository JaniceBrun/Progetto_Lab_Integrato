# Inventario dell'infrastruttura AWS

Fonte: branch `janice-synctest` (commit `e878082`, 15/11/2026). Sono elencate solo le risorse **effettivamente dichiarate** nel codice Terraform; nulla è stato dedotto dalla sola documentazione.

## Regione e zone

| Elemento | Valore | Fonte |
|---|---|---|
| Regione backend | `eu-south-1` | `Backendtf/terraform.tfvars.example`, `Mainterraform/backend.hcl.example` |
| Regione laboratorio | variabile `aws_region` (nessun default) | `Mainterraform/variables.tf` |
| Availability Zone | una sola, variabile `availability_zone` (es. `eu-south-1a`) | `Mainterraform/variables.tf` |

**Incongruenza da correggere:** `Mainterraform/terraform.tfvars.example` usa `us-east-1`/`us-east-1a` e i workflow `.github/workflows/cd.yml` e `ci.yml` usano `AWS_REGION: us-east-1`. La stima usa **eu-south-1**, regione scelta dal team e coerente con il backend.

## Stack `Infrastructure/Terraform/Mainterraform` (laboratorio)

### Compute (`modules/compute`, `for_each` su 4 ruoli)

Configurazione comune: AMI Ubuntu x86_64 (gratuita), Linux, tenancy condivisa, `monitoring = true` (monitoraggio dettagliato), `ebs_optimized = true`, IMDSv2 obbligatorio, volume root `gp3` cifrato con CMK, nessun instance profile, nessun `user_data` nel modulo.

| Ruolo | Subnet | Tipo istanza (default) | Volume root gp3 | IP pubblico |
|---|---|---|---|---|
| `waf` | pubblica `10.0.1.0/24` | `t3.small` | 30 GB | Elastic IP |
| `bastion` | pubblica | `t3.micro` | 10 GB | Elastic IP |
| `app` (Juice Shop) | privata `10.0.2.0/24` | `t3.small` | 20 GB | no |
| `wazuh` | privata | `t3.large` | 60 GB | no |

IOPS e throughput gp3 non specificati, quindi valgono i valori base inclusi (3.000 IOPS, 125 MB/s). Non sono definiti snapshot EBS.

### Rete

| Risorsa | Quantità | Fatturabile |
|---|---|---|
| VPC `10.0.0.0/16`, 2 subnet, 2 route table, Internet Gateway | 1 / 2 / 2 / 1 | No |
| Default SG bloccato e 4 security group per ruolo | 5 | No |
| NAT Gateway zonale (subnet pubblica) | 1 | **Sì** (orario + GB elaborati) |
| Elastic IP: NAT, waf, bastion | 3 | **Sì** (IPv4 pubblico, 0,005 USD/h ciascuno) |
| Traffico tra AZ | 0 (una sola AZ) | No |

### Logging e sicurezza

| Risorsa | Configurazione | Fatturabile |
|---|---|---|
| VPC Flow Log | `traffic_type = "ALL"`, destinazione CloudWatch Logs | **Sì** (ingestion vended logs) |
| CloudWatch Log Group `/aws/vpc/<prefix>-flow-logs` | retention 365 giorni, cifrato con CMK | **Sì** (storage) |
| Ruolo IAM per i Flow Logs | 1 | No |
| KMS CMK `<prefix>-lab` | rotazione annuale attiva, deletion window 30 gg | **Sì** |
| Key pair di bootstrap | 1 | No |

### Non presenti nel codice

CloudTrail, allarmi CloudWatch, dashboard, CloudWatch Agent, metriche custom, SNS, GuardDuty, Security Hub, AWS Config, Load Balancer, RDS, AWS Backup: **nessuno è definito**, quindi non sono inclusi nella stima base. Alcuni sono valutati come miglioramenti opzionali in [logging-monitoring.md](logging-monitoring.md).

## Stack `Infrastructure/Terraform/Backendtf` (state Terraform)

| Risorsa | Configurazione | Fatturabile |
|---|---|---|
| S3 bucket state | versioning, SSE-KMS con bucket key, access logging, versioni non correnti 90 gg | **Sì** (pochi MB) |
| S3 bucket log di accesso | SSE-S3, scadenza 365 gg | **Sì** (pochi MB) |
| KMS CMK `<prefix>-tfstate` | rotazione annuale attiva | **Sì** |
| Policy IAM di accesso allo state | 1 | No |

Il lock dello state usa `use_lockfile = true` (lock nativo S3): **nessuna tabella DynamoDB**. Il workflow CD cita ancora `dynamodb_table`, ma la tabella non esiste in Terraform e non è stimata.

## Esclusi dalla stima

- `lab/` e `testtf2/`: bozze e test precedenti, non usati dal flusso attuale (`to_do.md` indica `Mainterraform` come cartella di lavoro).
- GitHub Actions (CI/CD): costo GitHub, non AWS.
- Ansible (`Infrastructure/Ansible`): configura software sulle VM, nessuna risorsa AWS aggiuntiva.
