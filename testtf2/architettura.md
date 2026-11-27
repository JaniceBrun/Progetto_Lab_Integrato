# Architettura AWS generata da Terraform

## 1. Sintesi

L'infrastruttura è dichiarata nella directory `testtf2` e viene creata nella regione AWS `us-east-1` (N. Virginia). Il progetto usa il prefisso `labtest-dev` e contiene **4 istanze EC2**, una rete privata/pubblica, un bastion host, un NAT Gateway e 3 Elastic IP associati alle istanze pubbliche.

```mermaidf
flowchart TB
    Internet((Internet))

    subgraph VPC["VPC 10.0.0.0/16"]
        IGW[Internet Gateway]

        subgraph PUB["Subnet pubblica 10.0.1.0/24 - us-east-1a"]
            Juice["Juice Shop<br/>t3.small<br/>20 GiB gp2<br/>Porta 3000"]
            WAF["WAF + ModSecurity<br/>t3.medium<br/>30 GiB gp2"]
            Bastion["Bastion<br/>t3.micro<br/>8 GiB gp2<br/>SSH:22"]
            NAT["NAT Gateway"]
        end

        subgraph PRIV["Subnet privata 10.0.2.0/24 - us-east-1a"]
            Wazuh["Wazuh SIEM<br/>t3.medium<br/>30 GiB gp2"]
        end

        JuiceRT[Route table pubblica]
        PrivateRT[Route table privata]
    end

    Internet --> IGW
    IGW --> JuiceRT
    IGW --> PrivateRT
    JuiceRT --> PUB
    PrivateRT --> NAT
    NAT --> IGW

    Internet -->|EIP| Juice
    Internet -->|EIP| WAF
    Internet -->|EIP| Bastion
    Bastion -->|SSH:22| Wazuh
    Wazuh -->|Usa NAT| NAT
    Juice --> Wazuh
    WAF --> Juice
```

## 2. Componenti AWS create da Terraform

### 2.1 Rete

| Componente | Quantità | Dettaglio | Possibili costi |
|---|---:|---|---|
| **VPC** | 1 | `10.0.0.0/16`, DNS support e DNS hostnames abilitati | **Nessun costo separato** |
| **Subnet pubblica** | 1 | `10.0.1.0/24`, AZ `us-east-1a`, assegnazione IP pubblico automatica | **Nessun costo separato** |
| **Subnet privata** | 1 | `10.0.2.0/24`, AZ `us-east-1a`, nessun IP pubblico automatico | **Nessun costo separato** |
| **Internet Gateway** | 1 | Collega la VPC alla rete Internet | **Nessun costo separato** |
| **Route table pubblica** | 1 | Rotta `0.0.0.0/0` verso l'Internet Gateway | **Nessun costo separato** |
| **Route table privata** | 1 | Rotta `0.0.0.0/0` verso il NAT Gateway | **Nessun costo separato** |
| Associazioni route table/subnet | 2 | Una per la subnet pubblica e una per la privata | **Nessun costo separato** |
| NAT Gateway | 1 | Permette a Wazuh e alle istanze private di iniziare connessioni verso Internet; è nella subnet pubblica | **Costo orario + costo per GB elaborato**; non è Free Tier nella maggior parte dei casi |

### 2.2 Elastic IP e indirizzi IPv4 pubblici

| Componente | Quantità | Dettaglio | Possibili costi |
|---|---:|---|---|
| Elastic IP Juice Shop | 1 | Associato all'istanza Juice Shop | **Costo per ogni indirizzo IPv4 pubblico**, se applicabile al tipo di account, anche se associato; è una risorsa che può generare costi anche mentre l'istanza è ferma |
| Elastic IP WAF | 1 | Associato all'istanza WAF | Come sopra |
| Elastic IP Bastion | 1 | Associato al bastion, usato per l'accesso SSH | Come sopra |
| Elastic IP NAT Gateway | 1 | Allocato al NAT Gateway | Come sopra: oltre al costo dell'indirizzo, evita che il NAT perda il proprio IP pubblico |

AWS addebita pubblicamente gli indirizzi IPv4 in base alle politiche e al piano/account attivo. L'infrastruttura crea **4 indirizzi IPv4 pubblici in totale**: 3 per istanze e 1 per il NAT Gateway. Alcuni piani AWS offrono un limite mensile gratuito iniziale per IPv4, ma la soglia viene superata facilmente dalle 4 risorse se restano attive tutto il mese. Un Elastic IP non associato a una risorsa costa quasi sempre di più per essere mantenuto inutilizzato.

### 2.3 Istanze EC2

| Istanza | Tipo | Disco root | Rete | Software/servizio | Possibili costi |
|---|---|---:|---|---|---|
| **Juice Shop** | `t3.small` | 20 GiB gp2 crittografato | Subnet pubblica, IP pubblico tramite Elastic IP | OWASP Juice Shop | **Costo EC2**, **EBS**, **IPv4 pubblico**, trasferimento dati |
| **WAF** | `t3.medium` | 30 GiB gp2 crittografato | Subnet pubblica, IP pubblico tramite Elastic IP | nginx + ModSecurity + OWASP CRS | **Costo EC2**, **EBS**, **IPv4 pubblico**, trasferimento dati |
| **Wazuh** | `t3.medium` | 30 GiB gp2 crittografato | Subnet privata, senza IP pubblico diretto | Wazuh manager/SIEM, OpenSearch, dashboard | **Costo EC2**, **EBS**, **uscita tramite NAT**, trasferimento dati |
| **Bastion** | `t3.micro` | 8 GiB gp2 crittografato | Subnet pubblica, IP pubblico tramite Elastic IP | Jump host SSH, Ansible | **Costo EC2**, **EBS**, **IPv4 pubblico**, trasferimento dati |

AMI: Ubuntu 24.04 LTS Noble (`ubuntu-noble-24.04-amd64`) più recente, proprietà Canonical. Le istanze hanno `delete_on_termination=true`, quindi i dischi root vengono eliminati con l'istanza.

**Nota sul Free Tier:**

- `t3.micro` può rientrare nei limiti del Free Tier/crediti AWS in determinate condizioni, ma il servizio è disponibile solo se l'account conserva ancora l'allocazione prevista dal piano.
- `t3.small` e `t3.medium` non sono da considerare automaticamente gratuiti: superano la tipologia di EC2 mensile libera comunemente associata ai micro/micro-like instance.
- AWS Learner Lab usa crediti temporanei o limiti accademici. Il consumo di istanze più grandi può esaurirli rapidamente.

### 2.4 Volumi EBS

Sono presenti 4 volumi root gp2:

| Istanza | Volume | Totale |
|---|---:|---:|
| Juice Shop | 20 GiB | 20 GiB |
| WAF | 30 GiB | 30 GiB |
| Wazuh | 30 GiB | 30 GiB |
| Bastion | 8 GiB | 8 GiB |
| **Totale** |  | **88 GiB** |

- Il volume EBS è crittografato e viene eliminato alla distruzione dell'istanza.
- EBS può avere un limite Free Tier mensile, spesso 30 GiB di storage general purpose per account eleggibile. Questo laboratorio supera i 30 GiB totali.
- La tariffa dipende dal tipo di volume, dalla regione e dalle snapshot, ma in questo codice non vengono create snapshot.
- Se un'istanza viene arrestata anziché distrutta, il relativo volume gp2 **continua a generare costo**.

### 2.5 Security Group

Sono creati 4 Security Group:

| Security Group | Porte ingress dall'esterno | Destinazione |
|---|---|---|
| `labtest-dev-sg-juice` | TCP 22, 80, 443, 3000 | Juice Shop |
| `labtest-dev-sg-waf` | TCP 22, 80, 443 | WAF |
| `labtest-dev-sg-wazuh` | TCP 80, 443, 1514, 1515 da Internet | Wazuh dashboard/servizi; SSH solo dal bastion |
| `labtest-dev-sg-bastion` | TCP 22 da Internet | Bastion SSH |

Il traffico uscito è consentito per tutti i Security Group. La configurazione attuale espone porte Wazuh 80/443/1514/1515 direttamente a `0.0.0.0/0`: il laboratorio dovrebbe usare solo il bastion o restringere l'SG prima di lasciare l'ambiente attivo.

I Security Group non hanno costi AWS separati. Anche le singole regole non hanno costi separati.

### 2.6 IAM

Il modulo EC2 riutilizza il ruolo IAM esistente `LabRole` nel Learner Lab e crea per ogni istanza un **Instance Profile** dedicato:

- `labtest-dev-juice-profile`
- `labtest-dev-waf-profile`
- `labtest-dev-bastion-profile`
- `labtest-dev-wazuh-profile`

Il ruolo `LabRole` non viene creato dal Terraform di `testtf2`; viene solo cercato come risorsa preesistente. Instance Profile, ruolo IAM e relativa configurazione non hanno normalmente una tariffa separata.

### 2.7 Key Pair

Viene indicato il nome AWS `miaokey`, collegato a un Key Pair già esistente. Non viene creata una coppia privata/pubblica dal Terraform. Un EC2 Key Pair non ha normalmente costo.

La chiave privata `.pem` non è una risorsa AWS fatturabile. Deve restare locale e protetta.

### 2.8 User data e bootstrap

Ogni istanza riceve uno script `cloud-init` che:

- prepara l'account `ubuntu` e le chiavi SSH condivise;
- installa Git e Ansible;
- crea uno script `ansible-pull-lab`;
- crea un timer systemd che esegue Ansible ogni 15 minuti;
- recupera automaticamente i playbook dal repository GitHub;
- configura i collegamenti tra Wazuh, Juice Shop e WAF.

Ansible, Git, nginx, ModSecurity, OWASP CRS e Wazuh sono software installati sulle VM: non creano addebiti AWS separati, ma consumano risorse EC2, RAM, CPU, disco e rete.

## 3. Componenti configurati ma non creati direttamente

Queste componenti vengono associate o calcolate da AWS/EC2 ma non sono risorse Terraform separate:

- AMI Ubuntu;
- disco root gp2 crittografato;
- indirizzi IPv4 privati della VPC;
- indirizzo IP pubblico associato agli Elastic IP;
- scheda di rete primaria delle istanze (ENI);
- risoluzione DNS della VPC;
- event/metadata EC2;
- Key Pair esistente `miaokey`;
- ruolo IAM preesistente `LabRole`.

Le ENI non hanno in genere costo separato quando usate dalle EC2. DNS risoluto dentro la VPC non produce in genere un costo separato rilevante.

## 4. Risorse che possono generare costi

### 4.1 Costo quasi certo mentre l'infrastruttura resta attiva

| Risorsa | Perché genera o può generare costo |
|---|---|
| 1 × NAT Gateway | Addebito orario indipendente dall'uso reale + addebito sul traffico elaborato |
| 4 × istanze EC2 | 4 macchine a consumo orario finché in stato running |
| 88 GiB EBS gp2 | Storage fatturato per il tempo in cui i volumi esistono, anche se l'EC2 è arrestata |
| Elastic IP/IPv4 pubblici | Fino a 4 indirizzi: NAT, Juice, WAF e Bastion |
| Traffico Internet/Elastic IP/NAT | Costo dati in uscita verso Internet e costo di elaborazione NAT |

### 4.2 Risorse che richiedono attenzione nel Learner Lab

| Risorsa | Rischio |
|---|---|
| EC2 `t3.medium` ×2 | Consumo elevato dei crediti accademici |
| NAT Gateway | Una delle risorse più costose e non necessaria se Wazuh non deve accedere in modo continuo a Internet |
| Elastic IP NAT inattivo oppure istanze interrotte male | Costo continuato o consumi residui se le risorse non vengono distrutte correttamente |
| Volume EBS residuo | I volumi con `delete_on_termination=true` vengono rimossi con l'istanza, ma controllare sempre il Billing/Cost Explorer |
| Trasferimento dati verso Internet | Dipende dal traffico verso Juice Shop, Wazuh, aggiornamenti apt e pull Ansible |

### 4.3 Risorse AWS gratuite o normalmente senza costo separato

- VPC
- subnet
- Internet Gateway
- route table e associazioni
- Security Group e relative regole
- NAT Gateway **non rientra** in questa categoria
- IAM Role e Instance Profile
- EC2 Key Pair
- ENI delle istanze
- DNS interno alla VPC
- uso locale di Ubuntu, Wazuh, Ansible, nginx e ModSecurity

## 5. Stima qualitativa

La voce economicamente principale è quasi sempre il **NAT Gateway**, seguita dalle istanze EC2 `t3.medium`, dagli IPv4 pubblici e dal traffico dati.

Per il laboratorio, l'uso di quattro istanze può essere ridotto solo distruggendo o arrestando componenti temporaneamente inutilizzate:

- distruggere Wazuh o tutto il laboratorio quando non necessario con `terraform destroy`;
- evitare di lasciare le risorse attive tra una sessione e l'altra;
- controllare che tutti i quattro Elastic IP siano associati e che nessuno resti orfano;
- eliminare il NAT Gateway se Wazuh non ha bisogno di uscita verso Internet;
- usare la subnet privata solo se il NAT resta necessario;
- mantenere il controllo dei crediti AWS Learner Lab nella console Billing/AWS Academy.

Il Free Tier o i crediti Learner Lab possono coprire una parte o tutti i costi solo entro limiti e validità specifiche dell'account. **Superato il limite si pagano le risorse effettivamente attive**, indipendentemente dal fatto che siano state create per una esercitazione didattica.

## 6. Output Terraform rilevanti

Gli output mostrano:

- ID della VPC;
- ID della subnet pubblica e privata;
- IP pubblico Juice Shop;
- IP pubblico WAF;
- IP pubblico Bastion;
- IP privato Wazuh;
- comando SSH per raggiungere Wazuh passando dal bastion.

Questi dati non sono risorse AWS e non generano costi.

## 7. Flusso di rete

1. Internet raggiunge Juice, WAF e Bastion attraverso l'Internet Gateway e i rispettivi Elastic IP.
2. Juice è esposto sulla porta 3000, WAF sulle porte 80/443 e Bastion sulla porta 22.
3. Wazuh è nella subnet privata e non ha Elastic IP o IP pubblico diretto.
4. Il bastion usa la subnet pubblica per raggiungere Wazuh in SSH sulla porta 22.
5. Wazuh esce verso Internet per aggiornamenti, pacchetti e servizi tramite il NAT Gateway.
6. Le istanze eseguono Ansible Pull ogni 15 minuti, quindi generano anche eventuale traffico verso GitHub e verso i repository di pacchetti.


## Modifiche da implementare:
- mantenere EIP unicamente su NAT GW per wazuh
- implementazione baked ami gold
- Attenzione alla suddivisione dei volumi EBS per vm wazuh:
    • Root Volume (/dev/xvda o /dev/nvme0n1): Contiene solo il sistema operativo, i binari del SIEM/WAF e i file di configurazione statici. Questo è l'unico disco che finisce dentro la Baked AMI.
    • Data Volume (/dev/xvdf o /dev/nvme1n1): È un volume EBS separato dedicato esclusivamente ai database, agli indici e ai log persistenti.
- Spostamento juiceshop in subnet privata
- Aggiunta s3 bucket collegato a siem per raccolta log
- Aggiunta s3bucket per bootstrap tf

### Architettura AWS fuori dalla Sandbox

Dopo configurazione e verifica di Wazuh e WAF, l'infrastruttura verrà migrata da AWS Learner Lab a un account AWS reale.

#### Migrazione delle VM

| VM | Tipo EC2 indicativo | CPU/RAM | Root EBS | Volume dati | Posizione |
|---|---|---:|---:|---:|---|
| Bastion | `t3.micro` | 2 vCPU / 1 GiB | 8-20 GiB gp3 | — | Subnet pubblica |
| WAF | `t3.medium` o `m7i.large` | 2-2 vCPU / 4-8 GiB | 30-50 GiB gp3 | Opzionale 50 GiB gp3 | Subnet pubblica |
| Juice Shop | `t3.small` o `t3.medium` | 2 vCPU / 2-4 GiB | 20-30 GiB gp3 | — | Subnet privata |
| Wazuh | `m6i.2xlarge` minimo iniziale | 8 vCPU / 32 GiB | 50-100 GiB gp3 | 500 GiB gp3 o superiore | Subnet privata |

Le dimensioni di Wazuh dipendono da numero di agenti, volumi di log e retention. Sono valori iniziali per una singola istanza SIEM e dovranno essere monitorati con CloudWatch.

#### Suddivisione dei volumi Wazuh

- **Root volume:** 50-100 GiB `gp3`, crittografato con KMS.
  - Contiene SO, binari Wazuh/OpenSearch e configurazioni statiche.
  - Può essere inclusa in una Baked AMI contenente le dipendenze già verificate.
  - Non contiene database o indici persistenti.
- **Data volume:** 500 GiB `gp3` o superiore, crittografato con KMS.
  - È dedicato a database, indici, log operativi e dati OpenSearch.
  - Deve essere montato su `/var/ossec` o sulla directory effettivamente scelta per OpenSearch/Wazuh.
  - Deve essere formattato, montato con `fstab` e protetto da snapshot o lifecycle policy.
  - Dovrebbe usare UUID persistente anziché nomi dispositivo come `/dev/xvdf`, che possono cambiare.
  - Devono essere previsti snapshot EBS programmati e test di ripristino.

I Baked AMI devono contenere dipendenze, patch di base e configurazione candidata. Database, indici, segreti e dati operativi devono restare fuori dall'immagine.

#### Spostamento di Juice Shop nella subnet privata

La subnet privata impedisce l'accesso diretto di Internet a Juice Shop.

Il traffico proposto sarà:

```text
Utente
  -> Internet
  -> Elastic IP del WAF
  -> WAF nella subnet pubblica
  -> Juice Shop su 10.0.2.x:3000 nella subnet privata
```

# La raggiungibilità richiede:

- WAF nella subnet pubblica;
- Juice nella subnet privata;
- rule del Security Group Juice che consente TCP/3000 esclusivamente dal Security Group del WAF;
- route dalla subnet pubblica alla subnet privata già presente nella VPC;
- nessun Elastic IP su Juice Shop;
- preferibilmente un Application Load Balancer davanti al WAF per TLS, health check e pubblicazione del servizio;
- una NAT Gateway solo se Juice o WAF devono avviare connessioni verso Internet.

Nel caso in cui il traffico debba uscire da WAF verso Juice, il WAF usa il CIDR privato o il DNS interno della VPC. Non deve usare l'IP pubblico di Juice.

# Backend Terraform remoto separato

Il backend verrà creato da Terraform separato:

- bucket dedicato allo stato Terraform principale;
- blocco della pubblicazione pubblica;
- versioning attivato;
- crittografia SSE-KMS;
- lifecycle delle vecchie versioni;
- logging degli accessi;
- DynamoDB o lock nativo S3 per il locking dello stato;
- accesso limitato ai ruoli Terraform autorizzati;
- workflow di creazione una tantum prima dell'infrastruttura principale.

Il bucket dello stato non deve contenere segreti in chiaro. Le variabili sensibili devono usare AWS Secrets Manager o Parameter Store SecureString.

# Bucket separati per bootstrap e log

Sarà necessario utilizzare un minimo di tre contenitori separati:

- Bucket Terraform state
   - conserva terraform.tfstate;
   - mantiene lo storico mediante il versioning;
   - viene protetto da policy IAM e crittografia KMS.

- Bucket bootstrap
   - contiene script di bootstrap;
   - contiene pacchetti applicativi non sensibili;
   - contiene configurazioni già validate;
   - deve avere accesso pubblico disabilitato;
   - può usare un ciclo di vita per eliminare artefatti obsoleti.

- Bucket archiviazione log Wazuh
   - riceve log indicizzati o export da Wazuh;
   - usa classi storage come S3 Standard, Infrequent Access o Glacier;
   - usa lifecycle policy basata sulla retention;
   - usa Object Lock per log legalmente o operativamente critici;
   - deve impedire cancellazioni non autorizzate.

# KMS e cifratura

Per i dati a riposo saranno necessarie chiavi KMS separate quando la separazione dei domini è utile:
   - chiave KMS per EBS;
   - chiave KMS per il bucket dello stato Terraform;
   - chiave KMS per il bucket bootstrap;
   - chiave KMS per i log Wazuh;
   - eventuale chiave separata per Secrets Manager.

Le policy della chiave devono limitare l'uso a:
   - EC2 tramite Instance Profile;
   - Terraform attraverso ruolo IAM dedicato;
   - Wazuh tramite ruolo IAM dedicato;
   - amministratori autorizzati;
   - eventuali servizi di backup.

È necessario abilitare rotazione annuale delle chiavi gestite da AWS e audit degli utilizzi con CloudTrail.

# Rete verso Wazuh

   - La subnet privata espone Wazuh solo alle sorgenti necessarie:
   - SSH dal Bastion;
   - porte 1514/1515 soltanto dai Security Group degli agenti;
   - dashboard soltanto dal Bastion, da una VPN o da un Load Balancer privato;
   - nessuna porta Wazuh aperta verso 0.0.0.0/0;
   - traffico verso S3 mediante gateway o endpoint VPC per evitare passaggi inutili sul NAT;
   - traffico verso Internet soltanto per aggiornamenti o servizi autorizzati.

# Riduzione dei costi dell'infrastruttura reale

   - mantenere un solo Elastic IP sul NAT Gateway;
   - usare IP dinamici o un Application Load Balancer per il traffico pubblico;
   - usare gp3 anziché gp2;
   - adottare scheduling start/stop solo se i servizi lo consentono;
   - rimuovere risorse non usate;
   - usare snapshot EBS incremental e lifecycle S3;
   - verificare CloudWatch, Cost Explorer e AWS Budgets;
   - usare AWS Backup soltanto se necessario per soddisfare i requisiti di retention.
Queste specifiche sono un baseline iniziale. Prima dell'implementazione reale è necessario dimensionare Wazuh usando volume atteso degli eventi, retention, numero di agenti e requisiti di backup.