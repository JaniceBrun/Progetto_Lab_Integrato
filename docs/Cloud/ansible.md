# Guida Ansible

## Indice
1. [Strategia generale](#strategia-generale)
2. [user_data e bootstrap automatico](#user_data-e-bootstrap-automatico)
3. [AMI personalizzate](#ami-personalizzate)
4. [ansible-pull](#ansible-pull)
5. [Nginx come reverse proxy per Juice Shop](#nginx-come-reverse-proxy-per-juice-shop)

---

## Strategia generale

Il flusso del lab è diviso in due fasi:

**Fase 1 — Terraform:** crea l'infrastruttura (VPC, subnet, security group, EC2, EIP). Al termine le VM sono accese e raggiungibili ma non ancora configurate oltre al bootstrap iniziale.

**Fase 2 — Ansible:** configura le VM (installa e configura Wazuh, WAF, agenti, regole). Questa fase è ripetibile: dopo ogni `terraform destroy` + `terraform apply` basta rieseguirla per riportare l'ambiente allo stato desiderato.

---

## user_data e bootstrap automatico

Il `user_data` è uno script bash che AWS esegue **una volta sola** al primo avvio della VM, prima che qualsiasi utente si connetta.

Nel progetto è già configurato per Juice Shop: installa Docker, nginx e avvia il container automaticamente. Questo significa che dopo ogni `terraform apply`, Juice Shop è già raggiungibile su `http://<ip>` senza intervento manuale.

**Limiti del user_data:**
- Gira solo al primo avvio — se la VM viene stoppata e riavviata non viene rieseguito
- Non è adatto a configurazioni complesse o che cambiano nel tempo
- Non ha feedback diretto: per vedere i log devi connetterti alla VM e leggere `/var/log/cloud-init-output.log`
- Non gestisce dipendenze tra VM (es. configurare l'agent Wazuh su WAF richiede che Wazuh sia già up)

Per questo il `user_data` è usato solo per il bootstrap minimo (installare Docker, avviare Juice Shop, configurare nginx), mentre tutto il resto è delegato ad Ansible.

---

## AMI personalizzate

Una AMI (Amazon Machine Image) è uno snapshot completo di una VM in un dato momento — sistema operativo, software installato, configurazioni incluse.

**Quando ha senso crearla:**
Dopo aver configurato tutto manualmente o tramite Ansible, puoi creare una AMI di ogni VM. Al prossimo `terraform apply` le istanze partono già configurate, senza dover rieseguire Ansible.

**Il problema nel Learner Lab:**
Le AMI create nel Learner Lab **non persistono** tra una sessione e l'altra. Quando la sessione scade, AMI e snapshot EBS vengono cancellati. Per questo motivo nel contesto del lab le AMI non sono una soluzione praticabile per il ripristino rapido — Ansible è l'unica strada affidabile.

**Se invece lavorassi su un account AWS reale**, il flusso con AMI sarebbe:
1. `terraform apply` con AMI Ubuntu base
2. Ansible configura tutto
3. Crei AMI da ogni istanza configurata
4. Salvi gli AMI ID nel `terraform.tfvars`
5. Al prossimo `apply` le VM partono già pronte

---

## ansible-pull

### Cos'è

`ansible-pull` inverte il modello classico di Ansible. Invece di avere una macchina centrale (control node) che si connette alle VM e le configura, **ogni VM si configura da sola**: al boot scarica i playbook dalla repo Git ed esegue quelli che la riguardano.

Questo si sposa perfettamente con il `user_data`: lo script di bootstrap installa Ansible, clona la repo e lancia `ansible-pull`. Da quel momento la VM è autonoma.

### Flusso nel progetto

```
terraform apply
      │
      ▼
VM si avvia → user_data esegue:
      │  1. apt install ansible git
      │  2. ansible-pull -U <url-repo> playbooks/<ruolo>.yml
      ▼
VM configurata e pronta
```

### Struttura della repo

I playbook vanno nella cartella `Infrastructure/Ansible/` già presente nel progetto:

```
Infrastructure/Ansible/
├── playbooks/
│   ├── wazuh.yml       ← eseguito dalla VM wazuh
│   ├── waf.yml         ← eseguito dalla VM waf
│   └── bastion.yml     ← eseguito dalla VM bastion
├── roles/
│   ├── wazuh/
│   ├── waf/
│   └── common/         ← configurazioni comuni a tutte le VM
└── inventory/
    └── hosts.yml
```

### Esempio di user_data con ansible-pull

```bash
#!/bin/bash
apt-get update -y
apt-get install -y ansible git

ansible-pull \
  -U https://github.com/<org>/<repo>.git \
  -C main \
  Infrastructure/Ansible/playbooks/wazuh.yml
```

### Repo privata

Se la repo è privata (come probabilmente è la vostra), la VM deve poter autenticarsi a GitHub. Le opzioni sono:

**Deploy key (consigliata per il lab):**
1. Genera una chiave SSH dedicata: `ssh-keygen -t ed25519 -f deploy_key`
2. Aggiungi la chiave pubblica come Deploy Key nella repo GitHub (Settings → Deploy keys)
3. Passa la chiave privata alla VM tramite `user_data` o AWS Secrets Manager

**Token GitHub:**
Usa un Personal Access Token (PAT) con scope `repo` nell'URL:
```bash
ansible-pull -U https://<token>@github.com/<org>/<repo>.git ...
```
Più semplice ma meno sicuro — non committare il token nella repo.

### Divisione del lavoro

Il tuo collega di cybersecurity:
- Configura Wazuh e WAF manualmente la prima volta
- Documenta ogni comando eseguito
- Scrive i playbook Ansible corrispondenti nella repo

Tu del team cloud:
- Integri i playbook nel `user_data` tramite `ansible-pull`
- Verifichi che dopo ogni `terraform apply` le VM si configurino in autonomia

### Aggiornare la configurazione senza destroy

Con `ansible-pull` puoi aggiornare la configurazione di una VM senza distruggerla: basta connettersi via SSH e rieseguire il comando `ansible-pull` manualmente, oppure configurare un cron job sulla VM che lo esegue periodicamente:

```bash
# esegue ansible-pull ogni ora
echo "0 * * * * ubuntu ansible-pull -U https://github.com/<org>/<repo>.git Infrastructure/Ansible/playbooks/wazuh.yml" \
  >> /etc/cron.d/ansible-pull
```

Così ogni modifica ai playbook viene applicata automaticamente a tutte le VM senza intervento manuale.

---

## Nginx come reverse proxy per Juice Shop

### Perché

Juice Shop gira sulla porta 3000. Senza un reverse proxy devi raggiungere l'app con `http://<ip>:3000` — scomodo e non standard. Nginx ascolta sulla porta 80 e gira il traffico internamente a Juice Shop, rendendo l'app raggiungibile semplicemente con `http://<ip>`.

### Come funziona nel progetto

Il `user_data` della VM juice installa nginx insieme a Docker e scrive direttamente la configurazione del virtual host prima di avviare il servizio:

```
Browser → http://<ip>:80 → Nginx → http://localhost:3000 → Juice Shop
```

Nginx fa da intermediario: riceve la richiesta sulla 80, la passa a Juice Shop sulla 3000, e restituisce la risposta al browser. Juice Shop non sa di essere dietro un proxy.

### Configurazione applicata

```nginx
server {
  listen 80;
  location / {
    proxy_pass http://localhost:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
  }
}
```

- `proxy_pass` — gira tutto il traffico a Juice Shop sulla 3000
- `proxy_set_header Host` — preserva l'header Host originale
- `proxy_set_header X-Real-IP` — passa l'IP reale del client a Juice Shop, utile per i log

### Verifica dopo il deploy

Dopo `terraform apply`, una volta che la VM è up:

```bash
# verifica che nginx sia attivo
sudo systemctl status nginx

# verifica che risponda sulla 80
curl -s http://localhost | head -5
```

### Nota

Il `user_data` gira solo al primo avvio. Se fai `terraform apply` su una VM già esistente senza distruggerla, nginx non viene installato automaticamente — devi farlo a mano o tramite un playbook Ansible.
