# Ripartizione dei costi

Regione `eu-south-1`, prezzi On-Demand, USD, tasse escluse. Fonte: AWS Pricing Calculator (link nel [README](README.md)).
Annuale = mensile x 12. Orario indicato solo dove il servizio è fatturato a ore.

## Scenario base: 24x7

| Servizio AWS | Configurazione attuale | Costo orario | Mensile | Annuale | Ipotesi d'uso | Possibile ottimizzazione |
|---|---|---:|---:|---:|---|---|
| EC2 `waf` | `t3.small`, gp3 30 GB, monitoraggio dettagliato | 0,024 | 22,39 | 268,68 | 24x7 | spegnimento fuori orario |
| EC2 `bastion` | `t3.micro`, gp3 10 GB, monitoraggio dettagliato | 0,012 | 11,78 | 141,36 | 24x7 | accenderlo solo quando serve |
| EC2 `app` (Juice Shop) | `t3.small`, gp3 20 GB, monitoraggio dettagliato | 0,024 | 21,47 | 257,64 | 24x7 | spegnimento fuori orario |
| EC2 `wazuh` | `t3.large`, gp3 60 GB, monitoraggio dettagliato | 0,0958 | 77,57 | 930,84 | 24x7 | spegnimento fuori orario (voce più costosa) |
| NAT Gateway | 1 zonale, 20 GB/mese | 0,05 | 37,50 | 450,00 | sempre attivo | distruggere lo stack fuori orario |
| IPv4 pubblici | 3 EIP (NAT, waf, bastion) | 0,015 | 10,95 | 131,40 | fatturati anche con VM spente | distruggere lo stack fuori orario |
| Data transfer out | 50 GB/mese verso Internet | – | 4,50 | 54,00 | piano gratuito escluso | coperto dai 100 GB gratuiti |
| CloudWatch Logs | VPC Flow Logs 5 GB/mese, retention 365 gg | – | 3,02 | 36,24 | scenario medio | vedi logging-monitoring.md |
| KMS | 2 CMK, 20.000 richieste | – | 2,06 | 24,72 | – | nessuna (sicurezza) |
| S3 | 2 bucket, 1 GB | – | 0,06 | 0,72 | – | nessuna |
| **Totale** | | **≈ 0,26 medio** | **191,30** | **2.295,60** | | |

Dettaglio delle voci EC2 (dal Calculator):

| Ruolo | Istanza | EBS gp3 | Monitoraggio dettagliato | Totale |
|---|---:|---:|---:|---:|
| waf | 17,52 | 2,77 | 2,10 | 22,39 |
| bastion | 8,76 | 0,92 | 2,10 | 11,78 |
| app | 17,52 | 1,85 | 2,10 | 21,47 |
| wazuh | 69,93 | 5,54 | 2,10 | 77,57 |
| **Totale EC2** | **113,73** | **11,09** | **8,40** | **133,21** |

Composizione: EC2 70%, rete (NAT + IPv4 + uscita dati) 28%, logging/KMS/S3 3%.

## 24x7 contro orari realistici di sviluppo e test

Gli scenari sono calcolati con i **prezzi unitari del Calculator** (tabella in `aws-pricing-calculator.md`), applicando le ore indicate.

| Scenario | Cosa resta acceso fuori orario | Mensile | Annuale | Risparmio vs 24x7 |
|---|---|---:|---:|---:|
| A. 24x7 (base) | tutto | 191,30 | 2.295,60 | – |
| B. EC2 ferme fuori orario, 220 h/mese (10 h x 22 giorni) | NAT, EIP, volumi EBS, log | 105,99 | 1.271,83 | −45% |
| C. `terraform destroy` di `Mainterraform` fuori orario, 220 h/mese | solo backend S3/KMS | 65,09 | 781,07 | −66% |
| D. Come C, solo sessioni di laboratorio (80 h/mese) | solo backend S3/KMS | 30,44 | 365,28 | −84% |

Come sono costruiti:

- **B:** istanze x ore + EBS sempre fatturato (11,09) + monitoraggio dettagliato proporzionale + NAT 24x7 (37,50) + 3 IPv4 24x7 (10,95) + dati, log, KMS, S3 invariati. Gli IPv4 e il NAT restano a pagamento perché non dipendono dallo stato delle VM.
- **C/D:** tutte le voci orarie (istanze, EBS, NAT, IPv4, monitoraggio) proporzionali alle ore; dati, log, KMS e S3 mantenuti invariati per prudenza.

Il risultato chiave: **fermare solo le VM dimezza il costo, ma NAT Gateway ed Elastic IP valgono da soli 48,45 USD/mese**. Per scendere sotto i 70 USD/mese serve ricreare lo stack con Terraform solo quando si lavora, cosa che il progetto IaC permette già.

## Stime e addebiti reali

Nessun addebito reale è disponibile: lo stack non è stato ancora applicato. Dopo il primo deploy, confrontare questa tabella con **Cost Explorer** (filtro per tag `Project = its-lab`, già applicato da `default_tags`) e annotare le differenze qui sotto.

| Mese | Stima | Addebito reale | Differenza | Note |
|---|---:|---:|---:|---|
| (da compilare) | | | | |
