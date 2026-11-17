# Raccomandazioni di ottimizzazione

Obiettivo: ridurre il costo **senza cambiare l'architettura** (stesse 4 VM, stessa rete, stesso logging). Importi calcolati sui prezzi del Calculator per `eu-south-1`.

## Priorità

| # | Azione | Risparmio stimato | Sforzo | Cambia l'architettura? |
|---|---|---:|---|---|
| 1 | Ricreare lo stack `Mainterraform` solo durante le sessioni (`terraform apply` all'inizio, `terraform destroy` alla fine), lasciando sempre attivo `Backendtf` | da 126 USD/mese (220 h) a 161 USD/mese (80 h) | basso: c'è già il workflow CD con `apply`/`destroy` | No |
| 2 | Se lo stack deve restare in piedi: fermare le 4 EC2 fuori orario (10 h x 22 giorni) | 85 USD/mese | basso: AWS Instance Scheduler, cron o workflow GitHub | No |
| 3 | Configurare **AWS Budgets** con soglia mensile (es. 100 USD) e avvisi al 50/80/100% | evita sorprese | molto basso, i primi 2 budget sono gratuiti | No |
| 4 | Usare il **piano gratuito / crediti** AWS Educate o Academy dell'ITS, se disponibili | fino a ~6 USD/mese di uscita dati, KMS e log, più eventuali crediti | basso | No |
| 5 | Ridurre i Flow Logs nello scenario alto: `traffic_type = "REJECT"` invece di `ALL` durante le campagne di attacco | fino a ~12 USD/mese | basso | No (stessa risorsa, filtro diverso) |
| 6 | Monitoraggio dettagliato solo su `waf` e `wazuh` | 4,20 USD/mese | basso | No, ma va annotato lo skip di Checkov `CKV_AWS_126` |

Il punto 1 è il più efficace: elimina insieme le due voci che restano a pagamento anche con le VM spente (NAT Gateway 37,50 USD e IPv4 pubblici 10,95 USD).

## Dettaglio

### 1. Stack effimero con Terraform
- Il codice separa già backend (`Backendtf`, sempre attivo, ≈ 1,06 USD/mese tra CMK e S3) e laboratorio (`Mainterraform`).
- Con 220 h/mese: **65,09 USD/mese** (781 USD/anno) contro 191,30. Con 80 h/mese: **30,44 USD/mese**.
- Attenzione: i dati su disco (es. indici Wazuh) si perdono con il `destroy`. Se servono, aggiungere uno snapshot EBS prima del destroy (gp3 snapshot circa 0,05 USD/GB-mese, da verificare nel Calculator) o accettare che il lab riparta pulito, come previsto dal bootstrap con Ansible.
- Il KMS del lab entra in cancellazione programmata (30 giorni) a ogni destroy: valutare di spostare la CMK del lab nello stack backend per evitare una nuova chiave a ogni ciclo.

### 2. Spegnimento programmato
- Con EC2 ferme 510 h/mese si paga solo l'EBS (11,09 USD) e restano NAT ed EIP: **105,99 USD/mese**.
- Gli Elastic IP associati a istanze ferme restano fatturati (0,005 USD/h ciascuno).

### 3. Budget e controllo
- Attivare Cost Explorer e filtrare per i tag `Project` ed `Environment`, già applicati a tutte le risorse da `default_tags`.
- Aggiungere un tag `Owner` o `Team` per distinguere i costi tra team cloud e cyber.

### 4. Cose da **non** fare per questo progetto
- **Savings Plans / Reserved Instances insieme allo spegnimento:** l'impegno si paga 24x7 anche a istanze spente. Un EC2 Instance Savings Plan a 3 anni conviene solo se l'ambiente resta acceso 24x7 per tutto il periodo (risparmio fino a 2.557 USD su 3 anni, dettagli in [costo-3-anni.md](costo-3-anni.md)); distruggere lo stack fuori orario fa risparmiare di più (4.544 USD su 3 anni) senza impegno.
- **Spot:** le VM non sono tolleranti alle interruzioni (Wazuh e WAF perderebbero stato durante le demo).
- **Ridurre `t3.large` di Wazuh:** il requisito minimo dell'all-in-one Wazuh è 4 vCPU / 8 GB secondo la documentazione Wazuh; scendere a `t3.medium` (4 GB) rischia instabilità. Da valutare solo dopo aver misurato l'uso reale.
- **Passare a Graviton (`t4g`)**: costa meno ma cambia architettura CPU (AMI arm64, compatibilità di immagini e pacchetti), quindi esce dal perimetro di questa analisi.

## Correzioni nel repository che influenzano i costi

1. `Mainterraform/terraform.tfvars.example` usa `us-east-1`: allinearlo a `eu-south-1`, altrimenti l'infrastruttura verrebbe creata in un'altra regione con prezzi diversi.
2. `.github/workflows/cd.yml` e `ci.yml` usano `us-east-1` e una tabella DynamoDB che il backend non prevede (`use_lockfile = true`): allineare regione e backend.
3. Il workflow CD esegue `apply -auto-approve`: aggiungere un `plan` con approvazione evita deploy accidentali che generano costi.
