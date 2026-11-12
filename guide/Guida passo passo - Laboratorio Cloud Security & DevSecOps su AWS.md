# Guida passo passo: Laboratorio Cloud Security & DevSecOps su AWS

Costruisci, attacca e difendi OWASP Juice Shop su AWS. Tutti i comandi sono pensati per **Windows + WSL2 (Ubuntu)**; dove serve PowerShell è indicato.

## 0. Piano in breve

| Step | Cosa fai | Output |
| --- | --- | --- |
| 1 | Prepari PC, AWS, chiavi SSH, repo | Ambiente pronto |
| 2 | Crei il bucket S3 per il tfstate | Backend remoto |
| 3 | Terraform: VPC, subnet, NAT, SG, 4 VM | Infrastruttura su AWS |
| 4 | Checkov su Terraform e Ansible | Report di sicurezza |
| 5 | Ansible: chiavi, Juice Shop, WAF, Wazuh, agent | VM configurate |
| 6 | Red Team (WAF in DetectionOnly) | Report con login admin |
| 7 | Blue Team (WAF in On) + SIEM | Attacchi bloccati e visibili su Wazuh |
| 8 | Costi, documentazione, consegna | Documento finale, video |

## 1. Preparazione (una volta per persona)

### 1.1 WSL2

Ansible non gira su Windows nativo: usa WSL per tutto (Terraform, Checkov, Ansible, AWS CLI). In **PowerShell come amministratore**:

```powershell
wsl --install -d Ubuntu-24.04
```

Riavvia, apri Ubuntu e crea utente e password. Tieni il repository in `~/lab` (non in `/mnt/c`: i permessi delle chiavi SSH non funzionano lì). Per modificare i file usa VS Code con l'estensione WSL (`code .` da Ubuntu).

### 1.2 Strumenti (dentro Ubuntu)

```bash
sudo apt update && sudo apt install -y git unzip curl pipx gnupg lsb-release
pipx ensurepath
pipx install --include-deps ansible
pipx install checkov

# Terraform (repo HashiCorp)
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform

# AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip && sudo ./aws/install

# Verifica (riapri il terminale prima)
terraform -version; ansible --version; checkov --version; aws --version
```

Serve Terraform 1.10 o superiore (per `use_lockfile`).

### 1.3 Accesso AWS

1. Ogni collega ha il proprio utente IAM (o SSO) con **MFA attiva**. Niente chiavi condivise.
2. In aula puoi dare al gruppo la policy gestita `PowerUserAccess`; in un caso reale si restringe.
3. Configura la CLI e verifica:

```bash
aws configure        # oppure: aws configure sso
aws sts get-caller-identity
```

Regione consigliata: `eu-central-1` (Francoforte, non richiede attivazione). Se un tipo di istanza non è disponibile, usa `eu-west-1`.

### 1.4 Chiavi SSH personali

```bash
ssh-keygen -t ed25519 -f ~/.ssh/lab_ed25519 -C nome.cognome
chmod 600 ~/.ssh/lab_ed25519
```

La **privata** non esce mai dal tuo PC. La **pubblica** va nel repository (`ssh_keys/nome.pub`).

### 1.5 Repository

```bash
mkdir -p ~/lab/{bootstrap,infra,ansible/roles,ssh_keys,reports} && cd ~/lab && git init
cp ~/.ssh/lab_ed25519.pub ssh_keys/nome.pub
printf '.terraform/\n*.tfstate*\n*.tfvars\n*.pem\nid_*\n.vscode/\n' > .gitignore
```

Struttura finale:

```text
lab/
  bootstrap/            # bucket S3 del tfstate (progetto separato)
  infra/                # Terraform: rete, SG, VM
  ansible/              # ansible.cfg, inventory.ini, site.yml, roles/
  ssh_keys/             # solo chiavi pubbliche
  reports/              # output Checkov, screenshot, evidenze
```

## 2. Bucket S3 per il tfstate (mini progetto separato)

Il bucket sta fuori dalla VPC e si crea una volta sola. Il suo stato resta locale: **conservalo** (non in git) o ricrealo a fine corso.

`bootstrap/main.tf`:

```hcl
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
}

variable "region" { default = "eu-central-1" }
variable "bucket_name" { description = "Nome univoco globale, es. its-lab-tfstate-cognome-2026" }

provider "aws" { region = var.region }

resource "aws_s3_bucket" "tfstate" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_versioning" "v" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "e" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "p" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

```bash
cd ~/lab/bootstrap
terraform init
terraform apply -var bucket_name=its-lab-tfstate-COGNOME-2026
```

Poi limita l'accesso al bucket con una policy IAM solo ai colleghi del team (resta una policy IAM, non una bucket policy pubblica).

## 3. Terraform: rete, Security Group, VM

Indirizzi IP privati fissi: evitano di dover riscrivere le configurazioni di Ansible.

`infra/backend.tf`:

```hcl
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
  backend "s3" {
    bucket       = "its-lab-tfstate-COGNOME-2026"
    key          = "lab/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" { region = var.region }
```

`infra/variables.tf`:

```hcl
variable "region" { default = "eu-central-1" }
variable "team_cidrs" {
  type        = list(string)
  description = "IP pubblici del team in formato x.x.x.x/32"
}
variable "bootstrap_pubkey" {
  default = "../ssh_keys/nome.pub"
}
```

`infra/terraform.tfvars` (non in git; ottieni il tuo IP con `curl -s https://checkip.amazonaws.com`):

```hcl
team_cidrs = ["203.0.113.10/32", "203.0.113.11/32"]
```

`infra/network.tf`:

```hcl
resource "aws_vpc" "lab" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "lab-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = "lab-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = false
  tags                    = { Name = "lab-public" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.lab.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.region}a"
  tags              = { Name = "lab-private" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "lab-nat" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.lab.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
```

`infra/security.tf` (un SG per ruolo; le regole usano altri SG come sorgente, non IP):

```hcl
locals {
  sgs = ["waf", "app", "wazuh", "bastion"]

  sg_rules = {
    waf_http       = { to = "waf",   port = 80,   src = null,      cidr = "0.0.0.0/0" }
    waf_https      = { to = "waf",   port = 443,  src = null,      cidr = "0.0.0.0/0" }
    waf_ssh        = { to = "waf",   port = 22,   src = "bastion", cidr = null }
    app_3000       = { to = "app",   port = 3000, src = "waf",     cidr = null }
    app_ssh        = { to = "app",   port = 22,   src = "bastion", cidr = null }
    wazuh_ssh      = { to = "wazuh", port = 22,   src = "bastion", cidr = null }
    wazuh_ui       = { to = "wazuh", port = 443,  src = "bastion", cidr = null }
    wazuh_1514_waf = { to = "wazuh", port = 1514, src = "waf",     cidr = null }
    wazuh_1515_waf = { to = "wazuh", port = 1515, src = "waf",     cidr = null }
    wazuh_1514_app = { to = "wazuh", port = 1514, src = "app",     cidr = null }
    wazuh_1515_app = { to = "wazuh", port = 1515, src = "app",     cidr = null }
  }
}

resource "aws_security_group" "sg" {
  for_each    = toset(local.sgs)
  name        = "lab-${each.key}"
  description = "Lab ${each.key}"
  vpc_id      = aws_vpc.lab.id
  tags        = { Name = "lab-${each.key}" }
}

resource "aws_vpc_security_group_ingress_rule" "r" {
  for_each                     = local.sg_rules
  security_group_id            = aws_security_group.sg[each.value.to].id
  from_port                    = each.value.port
  to_port                      = each.value.port
  ip_protocol                  = "tcp"
  cidr_ipv4                    = each.value.cidr
  referenced_security_group_id = each.value.src == null ? null : aws_security_group.sg[each.value.src].id
}

# SSH al bastion solo dagli IP del team
resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each          = toset(var.team_cidrs)
  security_group_id = aws_security_group.sg["bastion"].id
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "all" {
  for_each          = toset(local.sgs)
  security_group_id = aws_security_group.sg[each.key].id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
```

`infra/compute.tf`:

```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "bootstrap" {
  key_name   = "lab-bootstrap"
  public_key = file(var.bootstrap_pubkey)
}

locals {
  vms = {
    bastion   = { type = "t3.micro", subnet = "public",  ip = "10.0.1.10", disk = 10, eip = true,  sg = "bastion" }
    waf       = { type = "t3.small", subnet = "public",  ip = "10.0.1.20", disk = 20, eip = true,  sg = "waf" }
    juiceshop = { type = "t3.small", subnet = "private", ip = "10.0.2.10", disk = 20, eip = false, sg = "app" }
    wazuh     = { type = "t3.large", subnet = "private", ip = "10.0.2.20", disk = 50, eip = false, sg = "wazuh" }
  }
}

resource "aws_instance" "vm" {
  for_each               = local.vms
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = each.value.type
  subnet_id              = each.value.subnet == "public" ? aws_subnet.public.id : aws_subnet.private.id
  private_ip             = each.value.ip
  vpc_security_group_ids = [aws_security_group.sg[each.value.sg].id]
  key_name               = aws_key_pair.bootstrap.key_name
  monitoring             = true
  ebs_optimized          = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = each.value.disk
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "lab-${each.key}" }
}

resource "aws_eip" "vm" {
  for_each   = { for k, v in local.vms : k => v if v.eip }
  instance   = aws_instance.vm[each.key].id
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
}

output "bastion_ip" { value = aws_eip.vm["bastion"].public_ip }
output "waf_ip"     { value = aws_eip.vm["waf"].public_ip }
```

Wazuh ha 8 GB di RAM (`t3.large`): sotto i 4 GB l'installazione fallisce.

### Esegui

```bash
cd ~/lab/infra
terraform init
terraform fmt && terraform validate
# prima di applicare: passo 4 (Checkov)
terraform plan -out tfplan
terraform apply tfplan
```

Annota `bastion_ip` e `waf_ip`.

## 4. Checkov (prima del deploy)

```bash
cd ~/lab
checkov -d infra --framework terraform --compact | tee reports/checkov_terraform.txt
checkov -d ansible --framework ansible --compact | tee reports/checkov_ansible.txt
```

Per ogni controllo fallito scegli e **documenta** una delle due strade:

- **Correggi**: ad esempio flow log della VPC, restrizione dell'egress dei SG.
- **Accetta con motivazione**: aggiungi nel blocco della risorsa un commento `#checkov:skip=CKV_AWS_382:egress aperto necessario per apt e immagini Docker`.

Tipici controlli che compaiono (verifica gli ID nel tuo report): egress dei SG aperto, VPC senza flow log, SG di default non ristretto, monitoring dettagliato EC2, e per il bucket tfstate logging, KMS e replica.

Rilancia Checkov dopo le correzioni e salva il report finale in `reports/` (è un deliverable).

## 5. Accesso SSH e Ansible

### 5.1 SSH con bastion

`~/.ssh/config` in Ubuntu (sostituisci `BASTION_IP`):

```text
Host bastion
  HostName BASTION_IP
  User ubuntu
  IdentityFile ~/.ssh/lab_ed25519
  StrictHostKeyChecking accept-new

Host 10.0.1.20 10.0.2.*
  User ubuntu
  IdentityFile ~/.ssh/lab_ed25519
  ProxyJump bastion
  StrictHostKeyChecking accept-new
```

Test: `ssh bastion` e poi `ssh 10.0.2.10`. La prima connessione funziona solo per chi ha la chiave di bootstrap; gli altri colleghi entrano dopo il passo 5.3.

### 5.2 File Ansible

`ansible/ansible.cfg`:

```ini
[defaults]
inventory = inventory.ini
roles_path = roles
remote_user = ubuntu
interpreter_python = auto_silent

[ssh_connection]
pipelining = True
```

`ansible/inventory.ini`:

```ini
[bastion]
bastion ansible_host=bastion

[waf]
10.0.1.20

[juiceshop]
10.0.2.10

[wazuh]
10.0.2.20

[agents:children]
waf
juiceshop
```

`ansible/site.yml` (Wazuh prima degli agent):

```yaml
- hosts: all
  become: true
  roles: [common]

- hosts: juiceshop
  become: true
  roles: [juiceshop]

- hosts: wazuh
  become: true
  roles: [wazuh]

- hosts: waf
  become: true
  roles:
    - { role: waf, tags: waf }

- hosts: agents
  become: true
  roles: [wazuh_agent]
```

### 5.3 Ruolo `common` (chiavi del team)

`ansible/roles/common/tasks/main.yml`:

```yaml
- name: Aggiorna cache apt
  ansible.builtin.apt:
    update_cache: true
    cache_valid_time: 3600

- name: Distribuisci le chiavi pubbliche del team
  ansible.posix.authorized_key:
    user: ubuntu
    key: "{{ lookup('file', item) }}"
  loop: "{{ lookup('ansible.builtin.fileglob', playbook_dir + '/../ssh_keys/*.pub', wantlist=True) }}"
```

Quando arriva un nuovo collega: aggiunge la sua `.pub` in `ssh_keys/`, push, e chi ha già accesso rilancia l'intero playbook con `ansible-playbook site.yml` (è idempotente: cambia solo `authorized_keys`).

### 5.4 Ruolo `juiceshop`

`roles/juiceshop/tasks/main.yml`:

```yaml
- name: Installa Docker
  ansible.builtin.apt:
    name: [docker.io, python3-docker]
    state: present

- name: Avvia Docker
  ansible.builtin.service:
    name: docker
    state: started
    enabled: true

- name: Avvia Juice Shop
  community.docker.docker_container:
    name: juiceshop
    image: bkimminich/juice-shop
    restart_policy: unless-stopped
    published_ports: ["3000:3000"]
```

### 5.5 Ruolo `wazuh` (manager, indexer, dashboard)

`roles/wazuh/tasks/main.yml`:

```yaml
- name: Installa Wazuh all-in-one (10-15 minuti)
  ansible.builtin.shell: |
    curl -sO https://packages.wazuh.com/4.x/wazuh-install.sh
    bash wazuh-install.sh -a
  args:
    chdir: /root
    creates: /var/ossec/bin/wazuh-control
  async: 2400
  poll: 30

- name: Regole di detection per ModSecurity
  ansible.builtin.copy:
    src: modsecurity_rules.xml
    dest: /var/ossec/etc/rules/modsecurity_rules.xml
    owner: wazuh
    group: wazuh
    mode: "0660"
  notify: Riavvia wazuh-manager
```

`roles/wazuh/handlers/main.yml`:

```yaml
- name: Riavvia wazuh-manager
  ansible.builtin.service:
    name: wazuh-manager
    state: restarted
```

`roles/wazuh/files/modsecurity_rules.xml`:

```xml
<group name="modsecurity,">
  <rule id="100100" level="8">
    <decoded_as>json</decoded_as>
    <match>SQL Injection</match>
    <description>ModSecurity: attacco SQL injection rilevato</description>
  </rule>
  <rule id="100101" level="12">
    <if_sid>100100</if_sid>
    <match>http_code":403</match>
    <description>ModSecurity: attacco SQL injection BLOCCATO (403)</description>
  </rule>
</group>
```

Verifica la versione corrente dell'installer sulla documentazione Wazuh (se `4.x` non risponde, usa il percorso della versione, ad esempio `.../4.14/wazuh-install.sh`).

### 5.6 Ruolo `waf` (Nginx + ModSecurity + OWASP CRS)

`roles/waf/defaults/main.yml`:

```yaml
modsec_engine: DetectionOnly   # Red Team. Per il Blue Team: On
juiceshop_ip: 10.0.2.10
```

`roles/waf/tasks/main.yml`:

```yaml
- name: Installa Nginx, ModSecurity e CRS
  ansible.builtin.apt:
    name: [nginx, libnginx-mod-http-modsecurity, modsecurity-crs]
    state: present

- name: Crea modsecurity.conf dal file raccomandato
  ansible.builtin.copy:
    src: /etc/modsecurity/modsecurity.conf-recommended
    dest: /etc/modsecurity/modsecurity.conf
    remote_src: true
    force: false

- name: Imposta motore, formato e path del log di audit
  ansible.builtin.lineinfile:
    path: /etc/modsecurity/modsecurity.conf
    regexp: "{{ item.re }}"
    line: "{{ item.line }}"
  loop:
    - { re: '^SecRuleEngine', line: 'SecRuleEngine {{ modsec_engine }}' }
    - { re: '^SecAuditLogFormat', line: 'SecAuditLogFormat JSON' }
    - { re: '^SecAuditLog ', line: 'SecAuditLog /var/log/modsec_audit.log' }
  notify: Riavvia nginx

- name: File principale ModSecurity (modsecurity.conf + CRS)
  ansible.builtin.copy:
    dest: /etc/modsecurity/main.conf
    content: |
      Include /etc/modsecurity/modsecurity.conf
      Include /etc/modsecurity/crs/crs-setup.conf
      Include /usr/share/modsecurity-crs/rules/*.conf
  notify: Riavvia nginx

- name: Reverse proxy verso Juice Shop
  ansible.builtin.copy:
    dest: /etc/nginx/sites-available/default
    content: |
      server {
        listen 80 default_server;
        modsecurity on;
        modsecurity_rules_file /etc/modsecurity/main.conf;
        location / {
          proxy_pass http://{{ juiceshop_ip }}:3000;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
      }
  notify: Riavvia nginx
```

`roles/waf/handlers/main.yml`:

```yaml
- name: Riavvia nginx
  ansible.builtin.service:
    name: nginx
    state: restarted
```

Se `nginx -t` segnala file mancanti, controlla i percorsi reali con `dpkg -L modsecurity-crs` e `dpkg -L libmodsecurity3`.

### 5.7 Ruolo `wazuh_agent` (su WAF e Juice Shop)

`ansible/group_vars/waf.yml`:

```yaml
agent_logs:
  - /var/log/modsec_audit.log
```

`ansible/group_vars/juiceshop.yml`:

```yaml
agent_logs:
  - /var/lib/docker/containers/*/*-json.log
```

`roles/wazuh_agent/tasks/main.yml`:

```yaml
- name: Scarica chiave GPG Wazuh
  ansible.builtin.get_url:
    url: https://packages.wazuh.com/key/GPG-KEY-WAZUH
    dest: /tmp/GPG-KEY-WAZUH

- name: Importa la chiave nel keyring
  ansible.builtin.shell: |
    gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import /tmp/GPG-KEY-WAZUH
    chmod 644 /usr/share/keyrings/wazuh.gpg
  args:
    creates: /usr/share/keyrings/wazuh.gpg

- name: Repository Wazuh
  ansible.builtin.apt_repository:
    repo: "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main"
    state: present

- name: Installa wazuh-agent (si registra sul manager)
  ansible.builtin.apt:
    name: wazuh-agent
    state: present
  environment:
    WAZUH_MANAGER: "10.0.2.20"

- name: Aggiungi i log da leggere
  ansible.builtin.blockinfile:
    path: /var/ossec/etc/ossec.conf
    insertbefore: "</ossec_config>"
    block: |
      {% for f in agent_logs %}
      <localfile>
        <log_format>json</log_format>
        <location>{{ f }}</location>
      </localfile>
      {% endfor %}
  notify: Riavvia wazuh-agent

- name: Avvia l'agent
  ansible.builtin.service:
    name: wazuh-agent
    state: started
    enabled: true
```

`roles/wazuh_agent/handlers/main.yml`:

```yaml
- name: Riavvia wazuh-agent
  ansible.builtin.service:
    name: wazuh-agent
    state: restarted
```

### 5.8 Lancio

```bash
cd ~/lab/ansible
ansible all -m ping
checkov -d . --framework ansible --compact
ansible-playbook site.yml
```

Per le prove Wazuh e per il Blue Team i ruoli sono idempotenti: puoi rilanciare tutto senza danni.

### 5.9 Accesso alla dashboard Wazuh e password

```bash
ssh bastion 'ssh 10.0.2.20 "sudo tar -O -xf /root/wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt"'
ssh -L 8443:10.0.2.20:443 bastion
```

Con il tunnel aperto vai su `https://localhost:8443` (utente `admin`, password dal comando sopra; il certificato è autofirmato). Nella dashboard controlla che gli agent `waf` e `juiceshop` risultino **Active**.

## 6. Fase Red Team (WAF in DetectionOnly)

Il WAF è già davanti a Juice Shop ma in sola registrazione: gli attacchi passano.

1. **Ricognizione**: apri `http://WAF_IP` nel browser; esplora funzioni, ricerca, login; in DevTools (scheda Network) annota gli endpoint `/rest/...` e `/api/...`.
2. **Analisi**: individua il punto debole, il form di login (`POST /rest/user/login`). Opzionale: scansione con OWASP ZAP (`Automated Scan` verso `http://WAF_IP`).
3. **Exploit (SQL injection)**: nel campo email del login inserisci `' OR true--` con una password qualsiasi. Da PowerShell:

```powershell
$waf = "WAF_IP"
$body = '{"email":"'' OR true--","password":"x"}'
Invoke-RestMethod -Uri "http://$waf/rest/user/login" -Method Post -ContentType "application/json" -Body $body
```

4. **Obiettivo**: la risposta contiene un token JWT; l'accesso avviene come primo utente (admin). Nel browser verifica di essere dentro come `admin@juice-sh.op`. Salva screenshot e richiesta/risposta in `reports/`.
5. Su Wazuh (filtro `rule.id:100100`) vedi l'attacco registrato ma non bloccato.

Nel report vulnerability assessment inserisci: vulnerabilità (SQL injection, OWASP A03), evidenza, impatto, mitigazione proposta.

## 7. Fase Blue Team (WAF in On)

Stessa rete, stessa architettura: cambia solo il motore.

```bash
cd ~/lab/ansible
ansible-playbook site.yml --tags waf -e modsec_engine=On
```

Ripeti lo stesso attacco: ora la richiesta riceve **403 Forbidden**. Verifica:

```bash
ssh bastion 'ssh 10.0.1.20 "sudo tail -n 1 /var/log/modsec_audit.log"'
```

Su Wazuh: filtra `rule.id:100101` (attacco bloccato, livello 12) e crea una dashboard con numero di attacchi per tipo, per IP sorgente e per ora. Se le regole non scattano, prova una riga di log reale con `/var/ossec/bin/wazuh-logtest` sulla VM Wazuh e adatta il `match`.

Check finale: il login normale con credenziali valide funziona ancora (nessun falso positivo sul flusso base).

## 8. Analisi costi

Produci una tabella con queste voci (prezzi dal **AWS Pricing Calculator**, regione scelta):

| Voce | Come calcolarla |
| --- | --- |
| Ore/uomo | ore per fase x numero di persone x tariffa oraria del profilo |
| EC2 | 4 istanze x ore di accensione (waf, bastion, juiceshop, wazuh) |
| NAT Gateway | costo orario + dati elaborati: di solito la voce più cara dopo Wazuh |
| Elastic IP | 3 IP pubblici (WAF, bastion, NAT), tutti tariffati a ore |
| EBS | 100 GB gp3 totali |
| S3 | tfstate: trascurabile |
| Manutenzione annua | patch, backup, monitoraggio, ore/uomo |
| Alternative | sandbox on-prem o altro cloud: stesso schema |

Risparmio: a fine sessione lancia `terraform destroy` in `infra/` (non nel bootstrap) e ricrea con `apply` + Ansible all'inizio della successiva. Ogni giorno acceso costa; imposta un **AWS Budget** con avviso via email.

## 9. Consegna: checklist

- [ ] Repository Git: `bootstrap/`, `infra/`, `ansible/`, `ssh_keys/` (solo pubbliche), nessun segreto né tfstate
- [ ] Schema architettura (VPC, subnet, SG, flussi) e pitch iniziale
- [ ] Report Checkov su Terraform e Ansible, con correzioni e skip motivati
- [ ] Demo tecnica per il SAL: rete, VM raggiungibili, installazioni
- [ ] Report vulnerability assessment con evidenza del login admin
- [ ] Configurazione WAF (DetectionOnly e On) e prova del 403
- [ ] Screenshot dashboard Wazuh e regole di detection
- [ ] Analisi costi di deploy e manutenzione
- [ ] Documentazione per il cliente finale
- [ ] Video demo o ambiente live

## 10. Estensione opzionale: pipeline CI/CD con OIDC

1. In AWS crea un identity provider OIDC per il tuo servizio CI (es. GitHub Actions) e un ruolo IAM con trust policy limitata al tuo repo e ai permessi minimi del lab.
2. Pipeline: `terraform fmt/validate` → `checkov` (fallisce sui controlli critici) → `terraform plan` → approvazione → `terraform apply`.
3. Nessuna chiave AWS statica nei segreti del repo: il ruolo si assume con `aws-actions/configure-aws-credentials` e `role-to-assume`.

## 11. Problemi comuni

| Sintomo | Causa probabile e rimedio |
| --- | --- |
| `Permission denied (publickey)` | Chiave privata con permessi larghi (`chmod 600`) o `.pub` non distribuita; usa chiave di bootstrap |
| Ansible resta appeso sulle VM private | `ssh 10.0.2.10` manuale prima; controlla `ProxyJump` e che l'IP del bastion sia aggiornato |
| `apt` fallisce sulle VM private | Route privata verso il NAT, NAT in subnet pubblica con EIP; attendi che il NAT sia `available` |
| 502 dal WAF | Container non attivo (`docker ps` su juiceshop) o regola SG `app_3000` mancante |
| Agent non compare su Wazuh | Porte 1514/1515 dagli SG `waf` e `app`; `systemctl status wazuh-agent` |
| Installer Wazuh fallisce | RAM insufficiente o rete: controlla `/var/log/wazuh-install.log` |
| IP del team cambiato | Aggiorna `team_cidrs` e riesegui `terraform apply` |
