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
