# Costi di logging e monitoraggio

Prezzi `eu-south-1` letti dall'AWS Pricing Calculator il 17/11/2026 (piano gratuito escluso).

## Configurazione attuale nel codice

| Componente | Dove | Configurazione | Costo |
|---|---|---|---|
| VPC Flow Logs | `modules/vpc_flow_log` | `traffic_type = "ALL"`, verso CloudWatch Logs | ingestion vended logs 0,60 USD/GB |
| Log group dei Flow Logs | `modules/cloudwatch_log_group` | retention 365 giorni, cifrato KMS | storage 0,032 USD/GB-mese (compresso) |
| Monitoraggio dettagliato EC2 | `modules/compute` (`monitoring = true`) | 4 istanze, metriche a 1 minuto | 2,10 USD/istanza-mese = **8,40 USD/mese** |
| Metriche base EC2, status check | automatiche | – | gratuite |
| Log di accesso S3 dello state | `Backendtf` | bucket dedicato, scadenza 365 gg | trascurabile (compreso nella voce S3) |
| CloudTrail, allarmi, dashboard, CloudWatch Agent | – | **non configurati** | 0 |

I log applicativi (nginx, ModSecurity, Juice Shop) sono inviati a **Wazuh**, che li conserva sul proprio volume EBS da 60 GB: il loro costo è già compreso nella voce EC2 `wazuh`, non in CloudWatch.

## Tre scenari per i costi esistenti

Il volume dei Flow Logs dipende soprattutto dalle attività del red team (scansioni e attacchi generano molti flussi).

| Scenario | Ipotesi | Flow Logs ingestion | Storage (1° mese) | Monitoraggio dettagliato | **Totale mensile** | Annuale |
|---|---|---:|---:|---:|---:|---:|
| Basso | 1 GB/mese: traffico di laboratorio minimo | 0,60 | 0,00 | 8,40 | **9,00** | 108,00 |
| Medio (usato nella stima) | 5 GB/mese: uso quotidiano + test periodici | 3,00 | 0,02 | 8,40 | **11,42** | 137,04 |
| Alto | 25 GB/mese: scansioni frequenti, attacchi automatizzati | 15,00 | 0,12 | 8,40 | **23,52** | 282,24 |

Calcoli del Calculator: `GB x 0,60 USD` per l'ingestion; `GB x 0,15 (compressione) x 0,032 USD` per lo storage.

### Effetto della retention a 365 giorni

Il Calculator considera un solo mese di dati conservati. A regime (dopo 12 mesi) lo storage diventa 12 volte maggiore:

| Scenario | Storage a regime | Costo storage a regime |
|---|---:|---:|
| Basso | 1,8 GB | 0,06 USD/mese |
| Medio | 9 GB | 0,29 USD/mese |
| Alto | 45 GB | 1,44 USD/mese |

L'impatto è trascurabile: **il costo dei log dipende dall'ingestion, non dalla retention**.

## Miglioramenti opzionali (non presenti nel codice)

Valori calcolati nel Calculator, voce CloudWatch, poi rimessi a zero per non alterare la stima base.

| Miglioramento | Ipotesi | Mensile | Fonte |
|---|---|---:|---|
| Allarmi CloudWatch | 10 allarmi a risoluzione standard (CPU, status check, disco per 4 VM) | 1,00 | Calculator: 10 x 0,10 USD |
| Dashboard CloudWatch | 1 dashboard | 0,00 | Calculator: rientra nelle 3 dashboard gratuite |
| CloudWatch Agent: metriche | 40 metriche custom (memoria, disco, ecc. su 4 VM) | 12,00 | Calculator: 40 x 0,30 USD |
| CloudWatch Agent: log | 5 GB/mese di syslog/nginx in CloudWatch Logs | 3,02 | Calculator: 5 x 0,60 USD + storage |
| CloudTrail | 1 trail, solo eventi di gestione, verso S3 | ≈ 0,00 | La prima copia degli eventi di gestione è gratuita; resta solo lo storage S3 di pochi MB. https://aws.amazon.com/cloudtrail/pricing/ |
| CloudTrail data events | non consigliato per il lab | 0,10 USD ogni 100.000 eventi | https://aws.amazon.com/cloudtrail/pricing/ |

Pacchetti suggeriti:

| Pacchetto | Contenuto | Costo aggiuntivo |
|---|---|---:|
| Minimo | CloudTrail eventi di gestione + 10 allarmi | ≈ 1,00 USD/mese |
| Completo | Minimo + CloudWatch Agent (metriche e log) | ≈ 16,02 USD/mese |

CloudTrail non è oggi definito in Terraform: va aggiunto solo se il team lo richiede (utile per il blue team come fonte di audit degli accessi all'account).

## Riepilogo logging

- **Esistente, scenario medio:** 11,42 USD/mese (137,04 USD/anno), di cui 8,40 USD per il monitoraggio dettagliato EC2.
- **Range esistente:** da 9,00 a 23,52 USD/mese secondo il traffico.
- **Opzionale consigliato:** circa 1,00 USD/mese (CloudTrail + allarmi).
