# Stima con AWS Pricing Calculator

- **Strumento:** AWS Pricing Calculator ufficiale, https://calculator.aws/, usato tramite browser (Claude in Chrome) il 17/11/2026.
- **Link pubblico della stima:** https://calculator.aws/#/estimate?id=ef836fcf0185d05366126fc600b21a586f6a0ee7
- **Nome stima:** *Vanguard Lab Integrato - eu-south-1 (24x7 on-demand)*
- **Regione impostata in ogni voce:** Europa (Milano), `eu-south-1`
- **Totale Calculator:** 191,30 USD/mese, 2.295,60 USD per 12 mesi, 0,00 USD anticipati

## Screenshot

| File | Contenuto |
|---|---|
| [screenshots/01-riepilogo-stima.jpg](screenshots/01-riepilogo-stima.jpg) | Riepilogo: costo mensile e totale 12 mesi |
| [screenshots/02-dettaglio-servizi-1.jpg](screenshots/02-dettaglio-servizi-1.jpg) | Voci EC2, VPC, CloudWatch, KMS |
| [screenshots/03-dettaglio-servizi-2.jpg](screenshots/03-dettaglio-servizi-2.jpg) | Voci VPC, CloudWatch, KMS, S3 |

## Voci inserite e parametri

| # | Servizio Calculator | Descrizione nella stima | Parametri inseriti | Mensile |
|---|---|---|---|---:|
| 1 | Amazon EC2 | EC2 waf | Linux, tenancy condivisa, 1 istanza `t3.small`, On-Demand 100%, EBS gp3 30 GB (IOPS/throughput base), monitoraggio dettagliato attivo, nessuno snapshot | 22,39 USD |
| 2 | Amazon EC2 | EC2 bastion | come sopra, `t3.micro`, gp3 10 GB | 11,78 USD |
| 3 | Amazon EC2 | EC2 app Juice Shop | come sopra, `t3.small`, gp3 20 GB | 21,47 USD |
| 4 | Amazon EC2 | EC2 wazuh SIEM | come sopra, `t3.large`, gp3 60 GB | 77,57 USD |
| 5 | Amazon VPC | NAT + IPv4 + data transfer | 1 NAT Gateway, 20 GB/mese elaborati; 3 IPv4 pubblici in uso, 0 inattivi; uscita verso Internet 50 GB/mese | 52,95 USD |
| 6 | Amazon CloudWatch | CloudWatch Logs: VPC Flow Logs | Log forniti (vended) a CloudWatch Logs 5 GB/mese, archiviazione attiva; nessun allarme, dashboard o metrica custom | 3,02 USD |
| 7 | AWS KMS | 2 CMK | 2 chiavi gestite dal cliente, 20.000 richieste simmetriche/mese | 2,06 USD |
| 8 | Amazon S3 | bucket tfstate + log | S3 Standard 1 GB, 5.000 PUT/LIST, 20.000 GET | 0,06 USD |
| | | | **Totale** | **191,30 USD** |

## Prezzi unitari letti dal Calculator (eu-south-1)

| Voce | Prezzo |
|---|---|
| `t3.micro` / `t3.small` / `t3.large` On-Demand Linux | 0,012 / 0,024 / 0,0958 USD/h |
| EBS gp3 | 0,0924 USD/GB-mese |
| Monitoraggio dettagliato EC2 | 7 metriche x 0,30 USD = 2,10 USD/istanza-mese |
| NAT Gateway | 0,05 USD/h + 0,05 USD/GB elaborato |
| IPv4 pubblico | 0,005 USD/h per indirizzo |
| Uscita dati verso Internet | 0,09 USD/GB (primo scaglione, piano gratuito escluso) |
| CloudWatch Logs vended e standard (ingestion) | 0,60 USD/GB |
| CloudWatch Logs storage | 0,032 USD/GB-mese (compressione stimata 0,15) |
| Metriche custom / allarmi standard | 0,30 USD/metrica-mese / 0,10 USD/allarme-mese |
| KMS | 1,00 USD/CMK-mese, 0,000003 USD/richiesta |
| S3 Standard | 0,024 USD/GB-mese; PUT 0,0000053 USD; GET 0,0000004 USD |

## Ipotesi d'uso (dati reali non disponibili)

| Ipotesi | Valore | Motivazione |
|---|---|---|
| Ore di funzionamento | 730 h/mese (24x7) | scenario base richiesto; gli scenari dev/test sono in `cost-breakdown.md` |
| Dati elaborati dal NAT | 20 GB/mese | aggiornamenti apt, immagine Docker Juice Shop, pacchetti Wazuh, CRS da GitHub |
| Uscita verso Internet | 50 GB/mese | traffico web verso WAF, accessi SSH, dashboard Wazuh, test del red team |
| VPC Flow Logs | 5 GB/mese | 4 VM, traffico `ALL`, scenario medio (vedi `logging-monitoring.md`) |
| Richieste KMS | 20.000/mese | cifratura CloudWatch Logs, EBS all'avvio, S3 con bucket key |
| Storage S3 | 1 GB | state Terraform con versioni + log di accesso |

## Limiti e scelte di modellazione

1. **NAT Gateway regionale.** Il modulo VPC del Calculator rende obbligatori i campi del "Gateway NAT regionale" (minimo 1). Sono stati compilati con 1 gateway, 1 AZ, 0 GB; il Calculator mostra per quella sezione **0,00 USD** e il totale VPC (52,95 USD) contiene solo il NAT zonale definito in Terraform. Il riepilogo della stima riporta comunque la dicitura "Numero di Gateway NAT regionali (1)": è solo un effetto della validazione del form.
2. **Storage dei log.** Il Calculator considera 1 mese di conservazione. Con retention a 365 giorni lo storage cresce nel tempo: il calcolo a regime è in `logging-monitoring.md` (impatto massimo circa 0,29 USD/mese nello scenario medio).
3. **Rotazione KMS.** Ogni rotazione automatica aggiunge 1 USD/mese per chiave (fino a un massimo di 2 rotazioni fatturate), quindi dal 13° mese il costo KMS sale di circa 2 USD/mese. Fonte: https://aws.amazon.com/kms/pricing/
4. **Piano gratuito escluso.** Con il piano gratuito l'uscita dati (100 GB/mese gratuiti), le prime 20.000 richieste KMS e i primi 5 GB di log CloudWatch sarebbero gratuiti: la stima è quindi prudente.
5. **Servizi senza costo** (VPC, subnet, IGW, route table, security group, IAM, key pair, AMI Ubuntu) non sono stati aggiunti al Calculator.

## Come riprodurre o modificare la stima

1. Aprire il link pubblico e scegliere **Modifica** (o *Duplica* per creare una variante).
2. Verificare che ogni voce sia su **Europa (Milano)**.
3. Per uno scenario dev/test: nelle voci EC2 impostare *Utilizzo* in percentuale (es. 30% = circa 220 h/mese). Attenzione: con utilizzo inferiore al 100% il Calculator presuppone che il volume EBS sia eliminato, cosa vera solo con `terraform destroy`.
4. Se cambiano i `instance_sizing` in `terraform.tfvars`, aggiornare tipo istanza e GB EBS nella voce corrispondente.
5. Condividere di nuovo la stima e aggiornare il link in questa pagina e nel README.
