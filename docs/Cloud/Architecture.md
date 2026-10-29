# Componenti dell'architettura

Laboratorio integrato Cloud Security & DevSecOps su AWS: una web application vulnerabile viene costruita, attaccata e difesa.

## Rete

| Componente | Ruolo |
| --- | --- |
| VPC (`10.0.0.0/16`) | Rete privata che contiene tutto il laboratorio |
| Subnet pubblica (`10.0.1.0/24`) | Ospita VM WAF, VM bastion e NAT Gateway |
| Subnet privata (`10.0.2.0/24`) | Ospita VM Juice Shop e VM Wazuh, non raggiungibili da Internet |
| Internet Gateway | Collega la subnet pubblica a Internet (route `0.0.0.0/0`) |
| NAT Gateway | In subnet pubblica, permette alle VM private di uscire verso Internet (pacchetti, immagini Docker). Solo traffico iniziato dall'interno |
| Elastic IP | IP pubblico fisso per VM WAF e VM bastion |
| Security Group | Un SG per ruolo (`waf`, `app`, `wazuh`, `bastion`); le regole usano come sorgente altri SG, non indirizzi IP |

## Macchine virtuali (Ubuntu)

| VM | Subnet | Software | Funzione |
| --- | --- | --- | --- |
| WAF | Pubblica | Nginx + ModSecurity + OWASP Core Rule Set, Wazuh agent | Reverse proxy, unico punto di ingresso pubblico (porte 80/443). Inoltra a Juice Shop sulla porta 3000 |
| Bastion | Pubblica | SSH | Unico punto di accesso amministrativo alle VM private (porta 22 solo dagli IP del team) |
| Juice Shop | Privata | Docker (`bkimminich/juice-shop`), Wazuh agent | Applicazione web vulnerabile, bersaglio degli attacchi. Accetta traffico solo dal WAF |
| Wazuh | Privata | Wazuh Manager, Indexer, Dashboard | SIEM: raccoglie i log (porte 1514/1515), applica le regole di detection e mostra i dashboard. Dimensionata con più RAM (4-8 GB) |

## Flussi di rete

- **Utenti e attaccanti**: Internet → Internet Gateway → WAF → Juice Shop (porta 3000).
- **Accesso del team**: PC → bastion → VM private, con SSH `ProxyJump`. La dashboard Wazuh si raggiunge con tunnel SSH verso la porta 443.
- **Log**: gli agent su WAF e Juice Shop inviano i log a Wazuh (porte 1514/1515).
- **Uscita Internet delle VM private**: route `0.0.0.0/0` verso il NAT Gateway.

## Fasi attacco e difesa

Il WAF resta sempre davanti a Juice Shop, senza modificare la rete tra le fasi:

- **Fase Red Team**: ModSecurity in `SecRuleEngine DetectionOnly`. Gli attacchi passano e vengono solo registrati.
- **Fase Blue Team**: ModSecurity in `SecRuleEngine On`. Gli stessi attacchi vengono bloccati.

## Strumenti di automazione

| Strumento | Uso | Dove gira |
| --- | --- | --- |
| Terraform | Crea rete, Security Group e VM | PC del team |
| Checkov | Scansiona il codice Terraform e Ansible prima del deploy | PC del team |
| Ansible (YAML) | Installa e configura le componenti con ruoli `juiceshop`, `waf`, `wazuh`, `wazuh_agent`; distribuisce le chiavi SSH pubbliche | PC del team, tramite il bastion |
| S3 | Conserva il tfstate (versioning, cifratura, Block Public Access, lock con `use_lockfile`) | Fuori dalla VPC, creato con un mini progetto Terraform separato |

## Accessi

- **AWS**: un utente IAM (o SSO) per ciascun collega, con MFA. Accesso al bucket tfstate limitato dalle policy IAM.
- **VM**: ogni persona ha la propria coppia di chiavi SSH. Nel repository ci sono solo le chiavi pubbliche (`ssh_keys/`), le private restano sui PC. Terraform usa una pubblica come chiave di bootstrap, poi Ansible distribuisce tutte le altre su tutte le VM.
- **Pipeline CI/CD** (estensione opzionale): OIDC per l'accesso ad AWS, senza chiavi statiche.