# Analisi dei costi AWS – Progetto Lab Integrato (Vanguard)

Data analisi: 17 novembre 2026 · Regione: **eu-south-1 (Europa – Milano)** · Valuta: USD, tasse escluse

> **Importante:** tutti gli importi di questa cartella sono **stime** calcolate con l'AWS Pricing Calculator ufficiale.
> L'infrastruttura **non è ancora stata deployata** (nessun `terraform apply`), quindi non esistono addebiti reali in AWS Billing da confrontare.
> Quando sarà disponibile il Cost Explorer dell'account, i dati reali andranno usati solo come confronto con queste stime.

## Stima ufficiale (AWS Pricing Calculator)

- **Link pubblico della stima:** https://calculator.aws/#/estimate?id=ef836fcf0185d05366126fc600b21a586f6a0ee7
  (nome: *Vanguard Lab Integrato - eu-south-1 (24x7 on-demand)*; il link scade dopo 1 anno, a novembre 2027)
- Screenshot: [`screenshots/`](screenshots/)

## Risultato in sintesi

| Scenario | Costo mensile | Costo annuale |
|---|---:|---:|
| **Base: 24x7, on-demand (Calculator)** | **191,30 USD** | **2.295,60 USD** |
| Dev/test: EC2 spente fuori orario (220 h/mese), resto sempre attivo | 105,99 USD | 1.271,83 USD |
| Dev/test: stack `Mainterraform` distrutto fuori orario (220 h/mese) | 65,09 USD | 781,07 USD |
| Solo sessioni di laboratorio: stack distrutto (80 h/mese) | 30,44 USD | 365,28 USD |

Su 3 anni (vedi [costo-3-anni.md](costo-3-anni.md)): **6.887,16 USD** On-Demand 24x7; **4.330,26 USD** con EC2 Instance Savings Plan 3 anni ad anticipo totale (−37%); **2.343,24 USD** distruggendo lo stack fuori orario (−66%).

Costo medio orario dello scenario base: circa **0,26 USD/h**.

Costo di logging e monitoraggio già previsto dal codice (scenario medio): **11,42 USD/mese**
(VPC Flow Logs su CloudWatch Logs 3,02 USD + monitoraggio dettagliato EC2 8,40 USD, quest'ultimo incluso nelle voci EC2).

Prime 3 voci di costo: EC2 Wazuh `t3.large` (77,57 USD, 41%), NAT Gateway (37,50 USD, 20%), IPv4 pubblici (10,95 USD, 6%).

## Base di codice analizzata

- Branch di partenza: `janice-synctest` (ultimo commit 15/11/2026, `e878082`), il più aggiornato: consolida il codice Terraform di `sara/infrastruttura` in `Infrastructure/Terraform/`.
- Stack analizzati: `Infrastructure/Terraform/Mainterraform` (laboratorio) e `Infrastructure/Terraform/Backendtf` (backend dello state).
- Cartelle `lab/` e `testtf2/` considerate bozze/test e **escluse** dalla stima (vedi inventario).

## Documenti

| File | Contenuto |
|---|---|
| [infrastructure-inventory.md](infrastructure-inventory.md) | Inventario delle risorse AWS realmente definite in Terraform |
| [aws-pricing-calculator.md](aws-pricing-calculator.md) | Parametri inseriti nel Calculator, prezzi unitari, procedura per riprodurre la stima |
| [cost-breakdown.md](cost-breakdown.md) | Tabella costi per servizio (orario, mensile, annuale) e confronto 24x7 vs dev/test |
| [logging-monitoring.md](logging-monitoring.md) | CloudWatch Logs, metriche, allarmi, CloudTrail: scenari basso/medio/alto |
| [costo-3-anni.md](costo-3-anni.md) | Costo su 36 mesi, Savings Plans 1 e 3 anni, confronto con gli orari dev/test |
| [optimization-recommendations.md](optimization-recommendations.md) | Opportunità di risparmio senza modificare l'architettura |

## Limiti principali

- Volumi di traffico e di log sono ipotesi (nessun dato reale): sono dichiarati in ogni documento.
- I prezzi del Calculator **escludono il piano gratuito** AWS (100 GB/mese di uscita dati, 5 GB di log, 20.000 richieste KMS, ecc.) e gli eventuali crediti AWS Educate/Academy.
- Nel repository ci sono incongruenze di regione (`terraform.tfvars.example` e workflow CD usano `us-east-1`): la stima usa `eu-south-1`, regione decisa dal team e usata dal backend.
