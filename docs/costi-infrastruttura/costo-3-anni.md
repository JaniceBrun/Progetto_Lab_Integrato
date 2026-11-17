# Costo su 3 anni e Savings Plans

Regione `eu-south-1`, USD, tasse escluse. I prezzi dei Savings Plans sono stati letti il 17/11/2026 dalla sezione *Opzioni di pagamento* della voce Amazon EC2 dell'AWS Pricing Calculator, Linux, tenancy condivisa, 1 istanza (screenshot: [screenshots/04-savings-plans-t3large.jpg](screenshots/04-savings-plans-t3large.jpg)).

## Prezzi Savings Plans dal Calculator (per istanza)

Formato: anticipo una tantum + quota mensile.

| Istanza | On-Demand | Compute SP 3 anni: nessun anticipo / parziale / totale | EC2 Instance SP 3 anni: nessun anticipo / parziale / totale | EC2 Instance SP 1 anno, nessun anticipo |
|---|---:|---|---|---:|
| `t3.micro` (bastion) | 8,76/mese | 0 + 5,04 / 84,10 + 2,34 / 165,56 + 0 | 0 + 3,80 / 63,07 + 1,75 / 118,26 + 0 | 5,48 |
| `t3.small` (waf, app) | 17,52/mese | 0 + 10,15 / 168,19 + 4,67 / 331,13 + 0 | 0 + 7,59 / 126,14 + 3,50 / 236,52 + 0 | 11,02 |
| `t3.large` (wazuh) | 69,93/mese | 0 + 40,52 / 675,40 + 18,76 / 1.321,88 + 0 | 0 + 30,22 / 503,26 + 13,98 / 946,08 + 0 | 44,09 |

I Savings Plans scontano **solo il calcolo EC2** (113,73 USD/mese On-Demand). Le altre voci restano a prezzo pieno: EBS 11,09, monitoraggio dettagliato 8,40, NAT + IPv4 + uscita dati 52,95, CloudWatch 3,02, KMS 2,06, S3 0,06, in totale **77,58 USD/mese**.

## Totale su 36 mesi, infrastruttura 24x7

| Opzione | Anticipo | Mensile medio | Totale 3 anni | Risparmio vs On-Demand |
|---|---:|---:|---:|---:|
| On-Demand (base) | 0 | 191,30 | 6.887,16 | – |
| Compute SP 3 anni, nessun anticipo | 0 | 143,44 | 5.163,84 | 1.723,32 (−25,0%) |
| Compute SP 3 anni, anticipo parziale | 1.095,88 | 138,46 | 4.984,60 | 1.902,56 (−27,6%) |
| Compute SP 3 anni, anticipo totale | 2.149,70 | 137,29 | 4.942,58 | 1.944,58 (−28,2%) |
| EC2 Instance SP 3 anni, nessun anticipo | 0 | 126,78 | 4.564,08 | 2.323,08 (−33,7%) |
| EC2 Instance SP 3 anni, anticipo parziale | 818,61 | 123,05 | 4.429,77 | 2.457,39 (−35,7%) |
| **EC2 Instance SP 3 anni, anticipo totale** | **1.537,38** | **120,29** | **4.330,26** | **2.556,90 (−37,1%)** |

Mensile medio = (anticipo + quote mensili x 36 + 77,58 x 36) / 36.
Da aggiungere a tutte le opzioni: circa 48 USD su 3 anni per la rotazione delle 2 chiavi KMS (+1 USD/mese per chiave dal 13° mese).

## Confronto con gli orari dev/test

| Strategia | Totale 3 anni |
|---|---:|
| On-Demand 24x7 | 6.887,16 |
| Miglior Savings Plan (EC2 Instance, 3 anni, anticipo totale), 24x7 | 4.330,26 |
| EC2 ferme fuori orario, 220 h/mese, On-Demand | 3.815,64 |
| **Stack `Mainterraform` distrutto fuori orario, 220 h/mese, On-Demand** | **2.343,24** |
| Stack distrutto, solo sessioni (80 h/mese), On-Demand | 1.095,84 |

## Raccomandazione

- **Il risparmio maggiore su 3 anni non viene dai Savings Plans ma dagli orari:** distruggere lo stack fuori orario costa 2.343 USD contro i 4.330 USD del miglior Savings Plan, senza nessun impegno.
- **Non combinare Savings Plans e spegnimento:** il Savings Plan è un impegno orario in USD da pagare 24 ore su 24 per 3 anni, anche quando le istanze sono spente o distrutte. Con 220 h/mese di utilizzo l'impegno resterebbe in gran parte inutilizzato.
- **Quando conviene il Savings Plan:** solo se l'ambiente deve davvero restare acceso 24x7 per 3 anni (es. un laboratorio permanente per più edizioni del corso) e l'account è nostro per tutto il periodo. In quel caso scegliere **EC2 Instance Savings Plan 3 anni** (famiglia `t3` in eu-south-1): con anticipo totale si risparmiano 2.557 USD, senza anticipo 2.323 USD.
