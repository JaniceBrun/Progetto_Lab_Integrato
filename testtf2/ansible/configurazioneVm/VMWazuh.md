# VM Wazuh

## Stato documentato

Data di configurazione iniziale: 19 novembre 2026.

## Cosa installa il user data Terraform

Il bootstrap comune installa:

- Git e Ansible.
- `/usr/local/bin/ansible-pull-lab`.
- Timer ansible-pull ogni 15 minuti.
- Repository remoto sul branch `janice-synctest`.
- Playbook `testtf2/ansible/wazuh.yml`.
- IP privato rilevato dalla VM al primo run invece di un indirizzo pubblico.

La VM è nella subnet privata e non ha Elastic IP pubblico. L'accesso SSH avviene tramite il bastion.

## Installazioni gestite da Ansible

Il playbook attivo è `testtf2/ansible/wazuh.yml` e usa esclusivamente il ruolo `wazuh`.

Pacchetti installati con versione fissata:

- `wazuh-indexer=4.14.10-1`.
- `wazuh-manager=4.14.10-1`.
- `wazuh-dashboard=4.14.10-1`.
- Supporto Python YAML `python3-yaml`.

## Configurazione Indexer

Modalità attuale: single-node.

Configurazione attiva:

- `cluster.name: wazuh-cluster`.
- `node.name: wazuh-indexer`.
- `network.host` ricavato dall'interfaccia privata della VM.
- `discovery.type: single-node`.
- Nessun `cluster.initial_master_nodes` in modalità single-node.
- Nessun `discovery.seed_hosts` in modalità single-node.
- Heap JVM impostato a `1g`.
- `vm.max_map_count=262144`, persistente tramite sysctl.
- Timeout systemd `TimeoutStartSec=600`.
- Validazione YAML prima del restart.

### Certificati

Directory `/etc/wazuh-indexer/certs`:

- Proprietario `wazuh-indexer:wazuh-indexer`.
- Directory permessi `0500`.
- Certificati permessi `0400`.

Certificati attesi:

- `indexer.pem`.
- `indexer-key.pem`.
- `root-ca.pem`.
- `admin.pem`.
- `admin-key.pem`.

La sezione `plugins.security.*` resta configurata per TLS, admin DN e nodes DN.

### Security init

La sicurezza viene inizializzata una sola volta tramite:

```text
/usr/share/wazuh-indexer/bin/indexer-security-init.sh
```

Il marker idempotente è:

```text
/var/lib/wazuh-indexer/.ansible_security_initialized
```

Lo stato viene controllato tramite health API HTTPS con il certificato admin. La password non è scritta nel repository.

## Manager e Dashboard

Il ruolo abilita e avvia:

- `wazuh-manager` sulle porte agent 1514 e registrazione 1515.
- `wazuh-indexer` sulla porta 9200.
- `wazuh-dashboard` sulla porta 443.

I certificati Manager sono copiati in `/etc/wazuh-manager/certs` con permessi `0640` e proprietà root:wazuh.

La Dashboard usa il certificato configurato in `/etc/wazuh-dashboard/certs` e imposta l'endpoint Indexer verso l'IP privato del Manager.

## Storico troubleshooting

### Problema 1: conflitto discovery single-node

Sintomo:

```text
IllegalArgumentException: setting [cluster.initial_master_nodes] is not allowed when [discovery.type] is set to [single-node]
```

Cause:

- Il file conteneva contemporaneamente `discovery.type: single-node`.
- Era presente anche `cluster.initial_master_nodes`.

Risoluzione:

- Conversione della configurazione in template completo `opensearch.yml.j2`.
- Nel template single-node viene scritto solo `discovery.type: single-node`.
- In modalità cluster vengono scritti `cluster.initial_master_nodes` e `discovery.seed_hosts`.
- Impedito il ricarico di chiavi incompatibili tra i due stati.

### Problema 2: lista orfana nel YAML

La rimozione parziale con replace/lineinfile lasciava elementi come `- "node-1"` senza la relativa chiave `cluster.initial_master_nodes:`.

Sintomo:

```text
MarkedYAMLException: expected <block end>, but found '-'
```

Risoluzione:

- Rimossi i patch parziali di `lineinfile/replace/blockinfile` per opensearch.yml.
- Generazione integrale del file dal template Jinja.
- Le liste `plugins.security.authcz.admin_dn`, `nodes_dn` e `roles` non vengono eliminate o ricompilate manualmente.

### Problema 3: timeout Indexer

Il timeout systemd era conseguenza del bootstrap fallito, non la causa principale.

Risoluzione:

- Timeout systemd esteso a 600 secondi.
- Attesa non autenticata sulla porta 9200 per 300 secondi con delay 10.
- Validazione YAML prima dell'avvio.
- `vm.max_map_count=262144` persistente.

### Problema 4: security index non inizializzata

Il servizio poteva entrare in running mentre l'Indice `.opendistro_security` non era ancora configurato.

Risoluzione:

- Esecuzione di `indexer-security-init.sh` una sola volta.
- Marker persistente dopo il primo successo.
- Health check TLS con certificato admin dopo il manager dell'indice.
- Manager avviato solamente dopo il controllo dell'Indexer.

### Problema 5: IP privato variabile

L'IP privato cambiava tra 10.0.2.203, 10.0.2.56 e altri indirizzi.

Risoluzione:

- `network.host` deriva da `ansible_default_ipv4.address`.
- Le configurazioni non usano un IP pubblico o un IP scritto fisso.
- `wazuh_manager_ip` viene rilevato dalla VM in modalità Wazuh; per gli agenti viene passato da Terraform.

### Problema 6: CN del certificato

Il nodo è `wazuh-indexer`, mentre una configurazione precedente usava il nodo `node-1` nei riferimenti.

Verifica da eseguire sul server:

```bash
sudo openssl x509 -in /etc/wazuh-indexer/certs/indexer.pem -noout -subject
```

Il CN deve essere coerente con `plugins.security.nodes_dn`.

## Storico decisioni e cambiamenti

### 19 novembre 2026

- Heap ridotto a `1g` per VM da 4 GB.
- Modalità single-node impostata di default.
- Introduzione template completo dell'Indexer.
- Aggiunta validazione YAML.
- Aggiunta override systemd.
- Security init resa idempotente con marker.
- Attesa non autenticata sulla porta 9200.
- Verifica health tramite certificati admin.
- IP configurato dinamicamente.

## 27 novembre 2026 — correzione DN certificati

### Modifica applicata

È stato corretto il template `testtf2/ansible/roles/wazuh/templates/opensearch.yml.j2`:

- `plugins.security.authcz.admin_dn` ora usa `CN=admin,OU=Wazuh,O=Wazuh,L=California,C=US`;
- `plugins.security.nodes_dn` ora usa `CN=wazuh-indexer,OU=Wazuh,O=Wazuh,L=California,C=US`.

La correzione elimina il mismatch individuato nel processo manuale precedente: i certificati generati dal tool Wazuh contenevano `OU=Wazuh`, mentre il template Ansible ometteva questa unità organizzativa.

### Motivazione

Prima della correzione la richiesta `_cluster/health` con certificato admin poteva restituire `Unauthorized`, anche se TLS e credenziali venivano configurati correttamente. OpenSearch Security confronta il DN del certificato con le liste `admin_dn` e `nodes_dn` configurate in `opensearch.yml`.

### Verifica prevista dopo il deploy Ansible

```bash
sudo openssl x509 -in /etc/wazuh-indexer/certs/admin.pem -noout -subject -nameopt RFC2253
sudo openssl x509 -in /etc/wazuh-indexer/certs/indexer.pem -noout -subject -nameopt RFC2253
sudo grep -nE 'admin_dn|nodes_dn|OU=Wazuh|CN=' /etc/wazuh-indexer/opensearch.yml
sudo systemctl restart wazuh-indexer
sudo curl -sS --fail --cacert /etc/wazuh-indexer/certs/root-ca.pem \
  --cert /etc/wazuh-indexer/certs/admin.pem \
  --key /etc/wazuh-indexer/certs/admin-key.pem \
  'https://127.0.0.1:9200/_cluster/health?pretty'
```

Il subject del certificato deve contenere `OU=Wazuh` e il file OpenSearch deve riportare lo stesso DN in `admin_dn` oppure `nodes_dn`. La health API deve restituire HTTP 200 con stato `green` o `yellow`.

## 27 novembre 2026 — endpoint Filebeat dinamico

### Modifica applicata

Il ruolo Wazuh ora installa e configura direttamente Filebeat e usa `wazuh_manager_ip` come indirizzo dell'Indexer.

- Per la VM Wazuh il bootstrap rileva l'IP privato locale con `hostname -I`.
- Per agenti e componenti remoti `wazuh_manager_ip` viene passato da Terraform o dal runner Ansible.
- Il template non contiene più indirizzi come `10.0.2.21` o `10.0.2.134`.
- Il task Ansible imposta `/etc/filebeat/filebeat.yml` con `hosts: ["{{ wazuh_manager_ip }}:9200"]`.
- Sono stati aggiunti i certificati manager come certificati client Filebeat in `/etc/filebeat/certs/`.

### Correzione del problema manuale

Il copia/incolla precedente configurava la nuova VM con l'IP della VM precedente. Questa dipendenza viene eliminata perché Ansible determina o riceve l'IP corrente al momento del deploy.

### Verifica prevista

```bash
sudo grep -nE 'hosts:|ssl\.certificate|ssl\.key|ssl\.certificate_authorities' /etc/filebeat/filebeat.yml
sudo filebeat test config -c /etc/filebeat/filebeat.yml
sudo filebeat test output -c /etc/filebeat/filebeat.yml
sudo systemctl status filebeat --no-pager -l
```

L'endpoint visualizzato deve coincidere con l'IP privato della VM Wazuh corrente e il test dell'output deve riuscire tramite TLS e mutual TLS.

## 27 novembre 2026 — certificato client dedicato Filebeat

### Verifica e correzione

Il ruolo Ansible ora genera e installa un certificato client dedicato a Filebeat, firmato dalla stessa CA Wazuh utilizzata da Indexer, Manager e Dashboard.

La sequenza viene eseguita subito dopo `wazuh-certs-tool.sh -A`:

1. verifica la presenza di `/opt/wazuh-certs/wazuh-certificates/root-ca.key`;
2. genera `/opt/wazuh-certs/wazuh-certificates/filebeat-key.pem`;
3. crea il CSR con subject `CN=filebeat,OU=Wazuh,O=Wazuh,L=California,C=US`;
4. firma `filebeat.pem` con la CA Wazuh tramite OpenSSL;
5. copia i tre file nel path `/etc/filebeat/certs/`.

File installati:

```text
/etc/filebeat/certs/filebeat.pem
/etc/filebeat/certs/filebeat-key.pem
/etc/filebeat/certs/root-ca.pem
```

Filebeat non riusa quindi il certificato del Manager. Questo risolve la mancanza rilevata nel secondo deployment manuale senza richiedere copie eseguite a mano.

### Verifica prevista

```bash
sudo openssl x509 -in /etc/filebeat/certs/filebeat.pem -noout -subject -issuer -dates
sudo openssl verify -CAfile /etc/filebeat/certs/root-ca.pem /etc/filebeat/certs/filebeat.pem
sudo ls -l /etc/filebeat/certs
sudo grep -nE 'ssl\.certificate_authorities|ssl\.certificate|ssl\.key' /etc/filebeat/filebeat.yml
sudo filebeat test config -c /etc/filebeat/filebeat.yml
sudo filebeat test output -c /etc/filebeat/filebeat.yml
```

L'issuer deve coincidere con la CA Wazuh, il subject deve indicare `CN=filebeat` e il test dell'output deve terminare con successo tramite mutual TLS.

## 27 novembre 2026 — confronto con la seconda sessione manuale

### Automazione completata

La configurazione manuale effettuata sulla VM `10.0.2.134` è stata confrontata con il ruolo `wazuh`.

Sono ora automatizzati:

- swap da 2 GB, permessi, `fstab` e `vm.swappiness=10`;
- repository e pacchetti Wazuh;
- generazione certificati Wazuh;
- generazione e distribuzione certificato client dedicato Filebeat;
- DN coerenti per admin e nodo Indexer;
- inizializzazione security una volta sola;
- avvio Indexer, Manager, Dashboard e Filebeat;
- endpoint dinamico Filebeat e Dashboard con `wazuh_manager_ip`;
- template e modulo ufficiali Wazuh per Filebeat;
- keystore Filebeat, username e password;
- certificati TLS della Dashboard;
- controllo e rimozione condizionale di `cluster.blocks.create_index`.

I passaggi manuali sono stati sostituiti dai task Ansible senza modificare i fix precedenti dei DN, dell'IP dinamico e del certificato Filebeat dedicato.

### Passaggi manuali da non ripetere

Non devono essere ripetuti i seguenti comandi della sessione manuale:

- `sed` manuale dei DN in `/etc/wazuh-indexer/opensearch.yml`;
- endpoint Filebeat con `10.0.2.21:9200`;
- copia di `filebeat.pem` o `filebeat-key.pem` da `/etc/wazuh-indexer/certs/`;
- rimozione manuale delle direttive `ssl.certificate` e `ssl.key`;
- copia manuale dei certificati Dashboard;
- endpoint Dashboard con l'IP fisso `10.0.2.134`;
- rimozione manuale persistente del blocco `cluster.blocks.create_index`.

La configurazione attuale usa esclusivamente template Jinja, variabili Ansible e task idempotenti.

### Evidenze già presenti senza intervento manuale

Il ruolo dell'agente Wazuh configura già sul WAF:

- `/var/log/nginx/access.log`;
- `/var/log/nginx/error.log`;
- `/var/log/modsec_audit.log`;
- indirizzo del Manager tramite `wazuh_manager_ip`.

Il ruolo WAF configura già ModSecurity e il relativo audit log. Le verifiche manuali della seconda sessione servono solo a confermare questi risultati sul deployment reale.

### Verifica finale raccomandata

```bash
sudo swapon --show
sudo systemctl status wazuh-indexer wazuh-manager wazuh-dashboard filebeat --no-pager
sudo filebeat test config -c /etc/filebeat/filebeat.yml
sudo filebeat test output -c /etc/filebeat/filebeat.yml
sudo openssl x509 -in /etc/filebeat/certs/filebeat.pem -noout -subject -issuer
sudo /var/ossec/bin/wazuh-control status
sudo /var/ossec/bin/agent_control -l
sudo ls -l /var/log/nginx/access.log /var/log/nginx/error.log /var/log/modsec_audit.log
```

## Comandi di verifica

```bash
sudo grep -nE 'discovery.type|cluster.initial_master_nodes|discovery.seed_hosts|node.name|network.host' /etc/wazuh-indexer/opensearch.yml
sudo python3 -c "import yaml; yaml.safe_load(open('/etc/wazuh-indexer/opensearch.yml')); print('YAML OK')"
sudo systemctl daemon-reload
sudo systemctl status wazuh-indexer --no-pager -l
sudo systemctl status wazuh-manager --no-pager -l
sudo systemctl status wazuh-dashboard --no-pager -l
sudo ss -lntp | grep -E ':(1514|1515|9200|443)\b'
sudo journalctl -u wazuh-indexer --no-pager -n 100
sudo journalctl -u wazuh-manager --no-pager -n 100
sudo journalctl -u wazuh-dashboard --no-pager -n 100
sudo /var/ossec/bin/wazuh-control status
sudo openssl x509 -in /etc/wazuh-indexer/certs/indexer.pem -noout -subject
sudo ls -ld /etc/wazuh-indexer/certs
sudo ls -l /etc/wazuh-indexer/certs
sudo grep -nE '^(-Xms|-Xmx)' /etc/wazuh-indexer/jvm.options
sudo sysctl vm.max_map_count
curl -k https://127.0.0.1:9200/_cluster/health?pretty
sudo /var/ossec/bin/agent_control -l
sudo systemctl status ansible-pull-lab.timer
sudo systemctl start ansible-pull-lab.service
sudo tail -n 200 /var/log/ansible-pull.log
```

## 27 novembre 2026 — password amministratore nel Vault Ansible

### Configurazione delle credenziali

La password dell'account amministratore Wazuh è stata cifrata nel file:

```text
testtf2/ansible/group_vars/vault.yml
```

Il file è un vault cifrato con `$ANSIBLE_VAULT`; il valore della password non appare in chiaro nel repository.

Il master password Vault non viene memorizzato nel repository né nei file Terraform. Deve essere installato una sola volta sulla VM in:

```text
/etc/wazuh/ansible-vault-password
```

Comando da eseguire manualmente sulla VM con permessi protetti:

```bash
sudo install -d -m 0700 /etc/wazuh
sudo vim /etc/wazuh/ansible-vault-password
sudo chmod 0600 /etc/wazuh/ansible-vault-password
```

Il runner `ansible-pull-lab` rileva automaticamente il file e aggiunge `--vault-password-file` al comando Ansible.

### Protezione Git

Il `.gitignore` esclude i file master password, tra cui:

```text
testtf2/ansible/.vault-password
testtf2/ansible/*vault-password*
**/vault-password.txt
**/.vault_pass
```

Il file `group_vars/vault.yml` può essere versionato perché contiene esclusivamente dati cifrati.

### Attenzione

Prima dell’uso operativo è necessario applicare la nuova password anche al backend OpenSearch/Wazuh, oltre a conservarla nel vault. Solo dopo deve essere effettuata la configurazione automatica di Filebeat e dei health check.
