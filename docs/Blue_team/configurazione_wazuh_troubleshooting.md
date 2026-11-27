# Setup Wazuh (SIEM) — Sessione terminale 19/11/2026

> Trascrizione pulita (comandi doppi rimossi) del tab "wazuh 19-11" del documento *Lab Integrato Vanguard*, seguita da analisi e riepilogo. La sessione copre **due giri di configurazione su due VM diverse**, perché l'infrastruttura è stata ricreata a metà lavoro: prima la VM `10.0.2.21` (lavoro iniziato verso le 12:46 UTC), poi — dopo problemi SSH e un redeploy — la VM `10.0.2.134` (ripartito dalle 13:44 UTC, stesso giorno).

---

## 0. Verifica iniziale della VM (prima VM, `10.0.2.21`)

```bash
cat /etc/os-release | grep -E 'PRETTY|VERSION_ID'
nproc
free -m
df -h /var/lib

# Tipo istanza e IP (IMDSv2)
TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
for p in instance-type local-ipv4 public-ipv4 placement/availability-zone; do
  echo -n "$p: "; curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/$p; echo
done

# Cosa è già installato/in ascolto
dpkg -l | grep -E 'wazuh|filebeat'
systemctl is-active wazuh-indexer wazuh-manager wazuh-dashboard filebeat
sudo ss -tlnp | grep -E ':(22|443|1514|1515|9200|9300|55000)\b'
sysctl vm.max_map_count

# Eventuali errori
sudo journalctl -u wazuh-indexer -u wazuh-manager -u wazuh-dashboard --no-pager -p warning -n 50
```

**Esito:** `t3.medium`, 2 vCPU, ~3.8 GB RAM, Ubuntu 24.04. `wazuh-indexer`/`wazuh-manager`/`wazuh-dashboard` e `filebeat` risultano già pacchettizzati (installati via Ansible in una fase precedente, non ripresa in questo tab) ma solo `wazuh-indexer` era attivo; manager e dashboard ancora spenti.

---

## 1. Ispezione certificati e stato Indexer
(fixed 27/11/26)
```bash
sudo ls -l /opt/wazuh-certs/wazuh-certificates/ /etc/wazuh-indexer/certs/
sudo cat /opt/wazuh-certs/config.yml
sudo grep -vE '^\s*#|^\s*$' /etc/wazuh-indexer/opensearch.yml
sudo grep -E '^-Xm[sx]' /etc/wazuh-indexer/jvm.options
sudo ls -l /var/lib/wazuh-indexer/.ansible_security_initialized
ps -o pid,rss,args -C java | cut -c1-110

sudo curl -s --cacert /etc/wazuh-indexer/certs/root-ca.pem \
  --cert /etc/wazuh-indexer/certs/admin.pem --key /etc/wazuh-indexer/certs/admin-key.pem \
  "https://10.0.2.21:9200/_cluster/health?pretty"

sudo openssl x509 -in /etc/wazuh-indexer/certs/admin.pem   -noout -subject -nameopt RFC2253
sudo openssl x509 -in /etc/wazuh-indexer/certs/indexer.pem -noout -subject -nameopt RFC2253
sudo openssl x509 -in /etc/wazuh-indexer/certs/indexer.pem -noout -ext subjectAltName
```

**Esito:** la prima chiamata a `_cluster/health` restituisce `Unauthorized`. L'ispezione dei certificati rivela la causa: i certificati hanno `subject=CN=admin,OU=Wazuh,O=Wazuh,...` (con `OU=Wazuh`), ma `opensearch.yml` dichiarava `admin_dn`/`nodes_dn` senza `OU` → mismatch sul Distinguished Name.

---

## 2. Swap da 2 GB (eseguito identico su entrambe le VM)

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf
sudo sysctl --system
```

Necessario perché con ~3.8 GB di RAM e Indexer (heap `-Xms1g -Xmx1g`) + Manager + Dashboard, la memoria libera scende rapidamente (osservata sotto i 200 MB liberi durante l'avvio del Manager).

---

## 3. Fix del Distinguished Name nei certificati OpenSearch
Fixed

```bash
sudo cp -a /etc/wazuh-indexer/opensearch.yml /etc/wazuh-indexer/opensearch.yml.bak

sudo sed -i \
  -e 's/"CN=admin,O=Wazuh/"CN=admin,OU=Wazuh,O=Wazuh/' \
  -e 's/"CN=wazuh-indexer,O=Wazuh/"CN=wazuh-indexer,OU=Wazuh,O=Wazuh/' \
  /etc/wazuh-indexer/opensearch.yml

sudo grep -n 'CN=' /etc/wazuh-indexer/opensearch.yml
sudo systemctl restart wazuh-indexer
until sudo ss -tln | grep -q ':9200'; do sleep 5; done; echo "9200 UP"
```

È la modifica indicata nel documento come "probabilmente la più importante" della sessione.

---

## 4. Inizializzazione sicurezza dell'Indexer

```bash
sudo /usr/share/wazuh-indexer/bin/indexer-security-init.sh

sudo curl -s --cacert /etc/wazuh-indexer/certs/root-ca.pem \
  --cert /etc/wazuh-indexer/certs/admin.pem --key /etc/wazuh-indexer/certs/admin-key.pem \
  "https://<IP_VM>:9200/_cluster/health?pretty"
```

**Esito:** su `10.0.2.21` cluster `YELLOW` (1 nodo, 1 shard non assegnata, 4/5 shard attive). Sulla seconda VM (`10.0.2.134`, §9) lo stesso script porta il cluster a `GREEN`.

---

## 5. Avvio di wazuh-manager

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now wazuh-manager
sleep 30
sudo systemctl status wazuh-manager --no-pager | head -12
sudo /var/ossec/bin/wazuh-control status
sudo ss -tlnp | grep -E ':(1514|1515|55000)\b'
sudo grep -E 'ERROR|CRITICAL' /var/ossec/logs/ossec.log | tail -n 10
free -m | grep -E 'Mem|Swap'
```

**Esito:** manager attivo, tutti i moduli core in esecuzione (`remoted`, `analysisd`, `authd`, `db`, `apid`, ecc.), porte `1514`/`1515`/`55000` in ascolto, nessun errore critico nei log.

---

## 6. Installazione e configurazione di Filebeat (prima VM)

```bash
sudo apt-get install -y filebeat
sudo curl -fsSL -o /etc/filebeat/filebeat.yml https://packages.wazuh.com/4.14/tpl/wazuh/filebeat/filebeat.yml
sudo sed -i 's#^\(\s*hosts:\).*#\1 ["10.0.2.21:9200"]#' /etc/filebeat/filebeat.yml

# Keystore (credenziali di default, da cambiare in una fase successiva)
sudo filebeat keystore create
echo admin | sudo filebeat keystore add username --stdin --force
echo admin | sudo filebeat keystore add password --stdin --force

# Template e modulo Wazuh
sudo curl -fsSL -o /etc/filebeat/wazuh-template.json \
  https://raw.githubusercontent.com/wazuh/wazuh/v4.14.10/extensions/elasticsearch/7.x/wazuh-template.json
sudo chmod go+r /etc/filebeat/wazuh-template.json
curl -fsSL https://packages.wazuh.com/4.x/filebeat/wazuh-filebeat-0.4.tar.gz | sudo tar -xz -C /usr/share/filebeat/module

# Certificati client di Filebeat (mutual TLS, riusando i certificati del manager)
sudo mkdir -p /etc/filebeat/certs
sudo cp /opt/wazuh-certs/wazuh-certificates/wazuh-manager.pem     /etc/filebeat/certs/filebeat.pem
sudo cp /opt/wazuh-certs/wazuh-certificates/wazuh-manager-key.pem /etc/filebeat/certs/filebeat-key.pem
sudo cp /opt/wazuh-certs/wazuh-certificates/root-ca.pem           /etc/filebeat/certs/root-ca.pem
sudo chown -R root:root /etc/filebeat/certs
sudo chmod 500 /etc/filebeat/certs
sudo chmod 400 /etc/filebeat/certs/*

# Avvio e test
sudo systemctl daemon-reload
sudo systemctl enable --now filebeat
sleep 10
sudo filebeat test output
sudo systemctl is-active filebeat
```

**Esito:** `talk to server... OK`, TLS 1.3, `filebeat active`. (Il primo giro di `chmod 400 /etc/filebeat/certs/*` è fallito perché il glob si espande come utente non-root prima di `sudo`; risolto ripetendolo con `sudo sh -c 'chmod 400 /etc/filebeat/certs/*'`.)

---

## 7. Verifica indicizzazione log (prima VM)

```bash
sudo tail -n 15 /var/log/filebeat/filebeat
sudo tail -n 2 /var/ossec/logs/alerts/alerts.json | cut -c1-200

CURL="sudo curl -s --cacert /etc/wazuh-indexer/certs/root-ca.pem --cert /etc/wazuh-indexer/certs/admin.pem --key /etc/wazuh-indexer/certs/admin-key.pem"
$CURL "https://10.0.2.21:9200/_cat/templates/wazuh*?v"
$CURL "https://10.0.2.21:9200/_cat/indices/wazuh-alerts-*?v"
```

**Esito:** template `wazuh` registrato, indice `wazuh-alerts-4.x-2026.11.19` creato e in stato `green` con alert (PAM, disk-space monitor, ecc.) già indicizzati.

---

## 8. Redeploy dell'infrastruttura → problemi di accesso SSH

A questo punto la VM Wazuh è stata ricreata (nuovo IP privato `10.0.2.134`, nuovo bastion `3.221.253.102`/`3.224.111.68`). Un secondo membro del team (Marco) ha tentato di riconnettersi da Windows, con diversi tentativi falliti:

```text
ssh wazuh / ssh bastion → Permission denied (publickey)
ssh 10.0.2.172 → Connection timed out
```

**Causa:** la `~/.ssh/config` locale puntava a `HostName`/`IdentityFile` non più corrispondenti all'host e alla chiave effettivamente autorizzati sulla nuova VM (IP e bastion cambiati col redeploy). Risolto riscrivendo `~/.ssh/config` con il bastion corretto come `ProxyJump` e la chiave privata giusta (`marco_progetto`), dopo di che la connessione (`ssh wazuh` → `10.0.2.134` via bastion) va a buon fine.

> ⚠️ **Nota di sicurezza:** durante la diagnosi, nel terminale sono state stampate in chiaro (con `cat`) **due chiavi private SSH complete** (`marco_progetto` e `id_ed25519`) e i relativi contenuti di `known_hosts`/`authorized_keys`. Il contenuto non è riportato qui: va considerato come materiale sensibile — vedi la sezione "Criticità di sicurezza" più sotto.

---

## 9. Ripetizione del setup sulla nuova VM (`10.0.2.134`)

Una volta ristabilito l'accesso, è stata rifatta **da capo** la stessa sequenza dei punti 2‑7:

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf
sudo sysctl --system

sudo cp -a /etc/wazuh-indexer/opensearch.yml /etc/wazuh-indexer/opensearch.yml.bak
sudo sed -i \
  -e 's/"CN=admin,O=Wazuh/"CN=admin,OU=Wazuh,O=Wazuh/' \
  -e 's/"CN=wazuh-indexer,O=Wazuh/"CN=wazuh-indexer,OU=Wazuh,O=Wazuh/' \
  /etc/wazuh-indexer/opensearch.yml
sudo systemctl restart wazuh-indexer

sudo /usr/share/wazuh-indexer/bin/indexer-security-init.sh   # → cluster GREEN
sudo systemctl enable --now wazuh-manager

sudo apt-get update
sudo apt-get install -y filebeat
sudo curl -fsSL -o /etc/filebeat/filebeat.yml https://packages.wazuh.com/4.14/tpl/wazuh/filebeat/filebeat.yml
sudo sed -i 's#hosts:.*#hosts: ["10.0.2.21:9200"]#' /etc/filebeat/filebeat.yml   # ⚠️ IP sbagliato, vedi sotto

sudo filebeat keystore create
echo admin | sudo filebeat keystore add username --stdin --force
echo admin | sudo filebeat keystore add password --stdin --force
sudo systemctl enable --now filebeat

sudo curl -fsSL -o /etc/filebeat/wazuh-template.json \
  https://raw.githubusercontent.com/wazuh/wazuh/v4.14.0/extensions/elasticsearch/7.x/wazuh-template.json
curl -s https://packages.wazuh.com/4.x/filebeat/wazuh-filebeat-0.5.tar.gz | sudo tar -xz -C /usr/share/filebeat/module
```

**Problemi emersi (specifici del redeploy):**

- **IP sbagliato in `filebeat.yml`:** il `sed` ha riscritto `hosts:` con l'IP della *vecchia* VM (`10.0.2.21`) invece di quello nuovo (`10.0.2.134`) — copia/incolla del comando non aggiornato. Corretto con:
  ```bash
  sudo sed -i 's/10\.0\.2\.21:9200/10.0.2.134:9200/' /etc/filebeat/filebeat.yml
  ```
- **Certificati Filebeat mancanti:** il comando per copiare `filebeat.pem`/`filebeat-key.pem` puntava a `/etc/wazuh-indexer/certs/`, dove quei file *non esistono mai* (ci sono solo `admin.pem`, `indexer.pem`, `root-ca.pem`; i certificati `filebeat.pem` nella prima VM venivano da `/opt/wazuh-certs/wazuh-certificates/wazuh-manager*.pem`, rinominati). Risultato: `cp` fallisce silenziosamente, resta solo `root-ca.pem`, e Filebeat va in crash-loop:
  ```text
  Error initializing output: 1 error: open /etc/filebeat/certs/filebeat.pem: no such file or directory
  ```

**Soluzione adottata (temporanea):** rimosse le direttive `ssl.certificate` / `ssl.key` da `filebeat.yml`, disattivando il mutual TLS lato client — resta solo la verifica del certificato server tramite `root-ca.pem` più autenticazione basic `admin`/`admin`:

```bash
sudo sed -i.bak '/^[[:space:]]*ssl\.certificate:/d; /^[[:space:]]*ssl\.key:/d' /etc/filebeat/filebeat.yml
sudo filebeat test config -c /etc/filebeat/filebeat.yml   # Config OK
sudo filebeat test output                                  # talk to server... OK
sudo systemctl restart filebeat                             # active (running)
```

---

## 10. Verifica agenti e alert (seconda VM)

```bash
sudo curl -s --cacert /etc/filebeat/certs/root-ca.pem -u admin "https://10.0.2.134:9200/_cat/indices/wazuh-alerts-*?v"
sudo /var/ossec/bin/agent_control -l
sudo /var/ossec/bin/agent_control -i 001
sudo /var/ossec/bin/agent_control -i 002
sudo tail -n 30 /var/ossec/logs/alerts/alerts.json
```

**Esito:**
- Indice `wazuh-alerts-4.x-2026.11.19` in stato `green`, alert in arrivo.
- 2 agenti connessi e attivi: `001` (`ip-10-0-1-24`) e `002` (`ip-10-0-1-154`) — presumibilmente Juice Shop e WAF.
- Tra gli alert: molti eventi PAM/sudo/SSH standard e **un evento "Web server 500 error code"** proveniente dall'agente `002` (`/var/log/nginx/access.log`) → l'agente sul WAF sta già inoltrando correttamente i log di accesso Nginx al manager.

### Ricerca dei log ModSecurity

```bash
sudo grep -i -m 10 'modsecurity' /var/ossec/logs/alerts/alerts.json
sudo grep -n -A 5 '<localfile>' /var/ossec/etc/ossec.conf
sudo find /var/ossec/etc/shared -type f -name 'agent.conf'
sudo cat /var/ossec/etc/shared/default/agent.conf
sudo grep -RniE 'nginx|modsecurity|access\.log|audit\.log' /var/ossec/etc/
sudo grep -iE 'nginx|modsecurity|logcollector' /var/ossec/logs/ossec.log | tail -n 30
sudo grep -RniE '^[[:space:]]*SecAudit(Log|Engine|LogType)' /etc/nginx /etc/modsecurity 2>/dev/null
sudo nginx -T 2>&1 | grep -i modsecurity
dpkg -l | grep -iE 'modsecurity|libmodsecurity'
```

**Esito: nessun risultato.** `agent.conf` condiviso è vuoto (solo il commento placeholder), nel manager non ci sono `<localfile>` dedicati ai log/audit di ModSecurity, e queste ricerche sono state lanciate **dalla VM Wazuh**, non dalla VM WAF — quindi non dicono nulla su se/dove ModSecurity sia installato o configurato lì. L'integrazione WAF → SIEM per gli eventi ModSecurity **non risulta ancora completata**.

---

## 11. Wazuh Dashboard (seconda VM)

```bash
sudo systemctl status wazuh-dashboard --no-pager -l   # inactive (dead)
sudo systemctl start wazuh-dashboard                   # crash
sudo journalctl -u wazuh-dashboard -n 40 --no-pager
```

**Errore 1:** `ENOENT ... /etc/wazuh-dashboard/certs/dashboard-key.pem` — i certificati della dashboard non erano mai stati installati.

```bash
sudo install -d -o root -g wazuh-dashboard -m 750 /etc/wazuh-dashboard/certs
sudo install -o root -g wazuh-dashboard -m 640 /opt/wazuh-certs/wazuh-certificates/wazuh-dashboard.pem     /etc/wazuh-dashboard/certs/dashboard.pem
sudo install -o root -g wazuh-dashboard -m 640 /opt/wazuh-certs/wazuh-certificates/wazuh-dashboard-key.pem /etc/wazuh-dashboard/certs/dashboard-key.pem
sudo install -o root -g wazuh-dashboard -m 640 /opt/wazuh-certs/wazuh-certificates/root-ca.pem             /etc/wazuh-dashboard/certs/root-ca.pem

sudo sed -i.bak 's|https://localhost:9200|https://10.0.2.134:9200|' /etc/wazuh-dashboard/opensearch_dashboards.yml
sudo systemctl restart wazuh-dashboard
```

**Errore 2:** `index_create_block_exception` — il cluster rifiutava la creazione dell'indice `.kibana` perché aveva un blocco persistente attivo:

```bash
sudo curl -s --cacert /etc/filebeat/certs/root-ca.pem -u admin \
  'https://10.0.2.134:9200/_cluster/settings?include_defaults=true&filter_path=*.cluster.blocks.*&pretty'
# → persistent.cluster.blocks.create_index = "true"

sudo curl -sS --fail-with-body --cacert /etc/filebeat/certs/root-ca.pem -u admin -X PUT \
  'https://10.0.2.134:9200/_cluster/settings' \
  -H 'Content-Type: application/json' \
  -d '{"persistent":{"cluster.blocks.create_index":null}}'
```

**Esito finale:** dashboard avviata, indice `.kibana` creato con successo, plugin Wazuh inizializzato (`App revision: 02`, 2 agenti sincronizzati), server in ascolto su `https://0.0.0.0:443`. Verifica:

```bash
curl -k -I https://localhost:443
# → HTTP/1.1 302 Found, location: /app/login
```

---

## Analisi — problemi riscontrati e cause

| # | Problema | Causa | Fix applicato | Stato |
|---|---|---|---|---|
| 1 | `_cluster/health` → `Unauthorized`, poi `indexer-security-init.sh` falliva | DN dei certificati (`OU=Wazuh`) non combaciava con `admin_dn`/`nodes_dn` in `opensearch.yml` | `sed` per allineare il DN, restart indexer | ✅ Risolto — **ripetuto identico su entrambe le VM**, segno di un difetto sistematico nel template/script di generazione certificati usato dal team |
| 2 | Memoria quasi esaurita all'avvio di Manager/Dashboard | Solo ~3.8 GB RAM per Indexer (heap 1 GB) + Manager + Dashboard sulla stessa VM | Swap da 2 GB + `vm.swappiness=10` | ⚠️ Mitigato, non risolto — il documento stesso segnala che la VM Wazuh andrebbe portata a 4 vCPU / 8 GB RAM appena disponibile su AWS |
| 3 | `ssh`/`ProxyJump` → `Permission denied` / `Connection timed out` dopo il redeploy | `~/.ssh/config` locale non aggiornato con il nuovo IP del bastion/VM e la chiave corretta | Riscritta la config SSH con bastion e chiave giusti | ✅ Risolto, ma **chiavi private stampate in chiaro nel terminale durante il debug** — vedi criticità sotto |
| 4 | Filebeat in crash-loop sulla seconda VM | Il comando di copia dei certificati client puntava a un path (`/etc/wazuh-indexer/certs/filebeat*.pem`) dove quei file non sono mai stati generati | Rimossi `ssl.certificate`/`ssl.key` da `filebeat.yml` → solo validazione CA + basic auth | ⚠️ Soluzione temporanea — va ripristinato il mutual TLS con i certificati client corretti (come nella prima VM, presi da `/opt/wazuh-certs/wazuh-certificates/wazuh-manager*.pem`) |
| 5 | `filebeat.yml` puntava ancora alla VM vecchia (`10.0.2.21`) | Comando copiato dalla sessione precedente senza aggiornare l'IP | `sed` correttivo sull'IP | ✅ Risolto |
| 6 | Dashboard non si avvia (certificati) | Certificati dashboard mai installati in `/etc/wazuh-dashboard/certs/` | Copiati da `/opt/wazuh-certs/wazuh-certificates/` con `install -o root -g wazuh-dashboard -m 640` | ✅ Risolto |
| 7 | Dashboard non si avvia (`index_create_block_exception`) | `cluster.blocks.create_index` impostato a `true` (causa non indagata nei log — verosimilmente un blocco di sicurezza/disco residuo dal cluster) | Rimosso il blocco via API `_cluster/settings` | ✅ Risolto, ma la **causa del blocco non è stata accertata** — da verificare che non si ripresenti (es. soglie di spazio disco) |
| 8 | Nessun log ModSecurity in Wazuh | L'agente sul WAF invia già i log di accesso Nginx, ma manca un `<localfile>` per i log/audit ModSecurity sia lato agente (`agent.conf` condiviso vuoto) sia lato manager | — | ❌ Non risolto — prossimo passo pianificato |

## Criticità di sicurezza da segnalare al team

1. **Chiavi private SSH esposte in chiaro nel log della sessione** (`marco_progetto` e `id_ed25519`, stampate via `cat`). Il documento sorgente contiene il materiale completo della chiave privata in testo semplice: andrebbe **rimosso dal documento condiviso** e le chiavi coinvolte **rigenerate/revocate**, dato che sono state esposte in un file potenzialmente visibile a tutto il team/organizzazione.
2. **Credenziali di default `admin`/`admin`** ancora in uso per Filebeat Keystore e per l'autenticazione verso l'Indexer OpenSearch: il documento le segnala già come provvisorie ("da cambiare alla Fase F"), ma al 19/11 non risultano ancora sostituite.
3. **Mutual TLS disattivato lato Filebeat** sulla seconda VM come workaround: il traffico resta cifrato (TLS verso il server) ma il client non si autentica più con certificato, solo con basic auth — da ripristinare con certificati client dedicati.
4. **Causa del blocco `cluster.blocks.create_index` non indagata**: rimuoverlo senza capire perché si fosse attivato rischia di nascondere un problema di capacità/disco che potrebbe ripresentarsi.

## Riepilogo — stato a fine sessione (19/11, VM `10.0.2.134`)

- `wazuh-indexer`, `wazuh-manager`, `filebeat`, `wazuh-dashboard`: tutti **attivi**.
- Cluster OpenSearch `GREEN`, indice `wazuh-alerts-4.x-*` popolato.
- 2 agenti Wazuh connessi e attivi (presumibilmente Juice Shop e WAF), già sincronizzati con syscheck.
- Dashboard raggiungibile su `https://10.0.2.134:443` (redirect a `/app/login` verificato con `curl`).
- **Da fare, in ordine di priorità:**
  1. Rimuovere le chiavi private dal documento e ruotarle.
  2. Cambiare le credenziali di default (`admin`/`admin`) su Indexer/Filebeat.
  3. Ripristinare il mutual TLS per Filebeat con certificati client propri.
  4. Configurare la raccolta dei log/audit ModSecurity dall'agente WAF (`SecAuditLog` + `<localfile>` su `agent.conf`/manager) per completare l'integrazione WAF → SIEM.
  5. Portare la VM Wazuh a 4 vCPU/8 GB RAM come da documentazione ufficiale, non appena disponibile su AWS.

---

## Nota tecnica aggiunta il 27 novembre 2026 — mismatch `OU=Wazuh` nei DN

### Verifica della causa

L'esito `Unauthorized` nella prima chiamata a `GET /_cluster/health` era legato alla gestione dei certificati da parte di Ansible:

- il ruolo `testtf2/ansible/roles/wazuh` genera i certificati tramite `wazuh-certs-tool.sh -A` usando `testtf2/ansible/roles/wazuh/templates/config.yml.j2`;
- il certificato generato contiene un subject con la struttura `CN=admin,OU=Wazuh,O=Wazuh,L=California,C=US` per l'amministratore e `CN=wazuh-indexer,OU=Wazuh,O=Wazuh,L=California,C=US` per il nodo;
- il template `testtf2/ansible/roles/wazuh/templates/opensearch.yml.j2` dichiarava invece i DN senza `OU=Wazuh`:
  - `CN=admin,O=Wazuh,L=California,C=US`;
  - `CN=wazuh-indexer,O=Wazuh,L=California,C=US`.

Questa differenza era un **mismatch reale del Distinguished Name** e non poteva essere risolta dall'autenticazione HTTP o dalle sole credenziali: i due certificati devono essere riconosciuti dalle liste OpenSearch Security usando lo stesso DN presente nei certificati.

### Correzione applicata

Il template Ansible di `opensearch.yml` è stato corretto aggiungendo `OU=Wazuh` sia in `plugins.security.authcz.admin_dn` sia in `plugins.security.nodes_dn`:

```yaml
plugins.security.authcz.admin_dn:
  - "CN=admin,OU=Wazuh,O=Wazuh,L=California,C=US"

plugins.security.nodes_dn:
  - "CN=wazuh-indexer,OU=Wazuh,O=Wazuh,L=California,C=US"
```

Dalla configurazione appena applicata, Ansible ricrea il file completo dell'Indexer e quindi evita i patch manuali che avevano causato in precedenti interventi elementi DN incompleti o valori duplicati.

### Verifiche sul server dopo il deploy

```bash
sudo openssl x509 -in /etc/wazuh-indexer/certs/admin.pem -noout -subject -nameopt RFC2253
sudo openssl x509 -in /etc/wazuh-indexer/certs/indexer.pem -noout -subject -nameopt RFC2253
sudo grep -nE 'admin_dn|nodes_dn|OU=Wazuh|CN=' /etc/wazuh-indexer/opensearch.yml
sudo python3 -c "import yaml; yaml.safe_load(open('/etc/wazuh-indexer/opensearch.yml')); print('YAML OK')"
sudo systemctl restart wazuh-indexer
sudo /usr/share/wazuh-indexer/bin/indexer-security-init.sh
sudo curl -sS --fail --cacert /etc/wazuh-indexer/certs/root-ca.pem \
  --cert /etc/wazuh-indexer/certs/admin.pem \
  --key /etc/wazuh-indexer/certs/admin-key.pem \
  'https://127.0.0.1:9200/_cluster/health?pretty'
```

Il valore atteso per i subject è rispettivamente `CN=admin,OU=Wazuh,O=Wazuh,L=California,C=US` e `CN=wazuh-indexer,OU=Wazuh,O=Wazuh,L=California,C=US`; `OU=Wazuh` deve comparire identicamente nelle relative liste `admin_dn`/`nodes_dn`. Il risultato atteso della health API è HTTP 200 con stato `green` o `yellow` su un singolo nodo.

---

## Nota tecnica aggiunta il 27 novembre 2026 — IP dell'Indexer in Filebeat

### Problema osservato

Durante il secondo setup manuale Marco ha copiato il comando usato sulla prima VM. Il comando sostituiva l'endpoint con `10.0.2.21:9200`, cioè con l'IP privato della VM precedente, anziché usare `10.0.2.134:9200`, IP della nuova VM. La differenza era invisibile perché il comando non derivava dinamicamente il nuovo indirizzo dall'ambiente.

### Soluzione automatizzata

È possibile eliminare il problema con una variabile Ansible già disponibile nel progetto:

```yaml
hosts: ["{{ wazuh_manager_ip }}:9200"]
```

`wazuh_manager_ip` viene trattato diversamente in base al tipo di VM:

- sulla VM Wazuh il bootstrap rileva l'IP privato locale con `hostname -I | awk '{print $1}'`;
- sulle VM agente WAF/Juice Shop l'IP viene passato da Terraform o dal runner Ansible.

Il ruolo Wazuh ora configura quindi `/etc/filebeat/filebeat.yml` senza usare indirizzi fissi e installa anche i certificati client in `/etc/filebeat/certs/`, ripristinando il mutual TLS anziché disabilitarlo manualmente.

### Verifica dopo il prossimo deploy

```bash
sudo grep -nE 'hosts:|ssl\.certificate|ssl\.key|ssl\.certificate_authorities' /etc/filebeat/filebeat.yml
sudo filebeat test config -c /etc/filebeat/filebeat.yml
sudo filebeat test output -c /etc/filebeat/filebeat.yml
sudo systemctl status filebeat --no-pager -l
```

Il valore `hosts:` deve contenere l'IP privato effettivo della VM Wazuh corrente. Il test dell'output deve confermare la raggiungibilità HTTPS e la configurazione dei certificati TLS.

---

## Nota tecnica aggiunta il 27 novembre 2026 — generazione certificato client dedicato Filebeat

### Correzione verificata nel ruolo Ansible

Il problema dei certificati Filebeat mancanti non è stato affrontato mediante una copia successiva del certificato del Manager. Il ruolo Wazuh ora genera una identità client distinta, denominata `filebeat`, firmata dalla CA generata da `wazuh-certs-tool.sh -A`.

Dopo la generazione dei certificati standard Wazuh, Ansible:

1. verifica `/opt/wazuh-certs/wazuh-certificates/root-ca.key`;
2. crea `/opt/wazuh-certs/filebeat-ext.cnf` con estensioni `clientAuth`;
3. genera la chiave privata `filebeat-key.pem`;
4. genera il CSR con subject `CN=filebeat,OU=Wazuh,O=Wazuh,L=California,C=US`;
5. firma `filebeat.pem` con `root-ca.pem` e `root-ca.key`;
6. distribuisce certificato, chiave e CA in `/etc/filebeat/certs/`;
7. configura i parametri TLS nel file `/etc/filebeat/filebeat.yml`.

Nessun certificato o passaggio manuale è necessario al primo deployment. La procedura resta idempotente grazie ai marker `creates` dei file OpenSSL e al comportamento di convergenza di Ansible.

### Verifiche sul server dopo il deploy

```bash
sudo openssl x509 -in /etc/filebeat/certs/filebeat.pem -noout -subject -issuer -dates
sudo openssl verify -CAfile /etc/filebeat/certs/root-ca.pem /etc/filebeat/certs/filebeat.pem
sudo ls -l /etc/filebeat/certs
sudo grep -nE 'ssl\.certificate_authorities|ssl\.certificate|ssl\.key' /etc/filebeat/filebeat.yml
sudo filebeat test config -c /etc/filebeat/filebeat.yml
sudo filebeat test output -c /etc/filebeat/filebeat.yml
```

Risultato atteso:

- `subject` contiene `CN=filebeat,OU=Wazuh,O=Wazuh,L=California,C=US`;
- `issuer` coincide con la CA Wazuh;
- la verifica OpenSSL restituisce `OK`;
- `filebeat.pem` e `filebeat-key.pem` esistono con permessi restrittivi;
- `filebeat test output` conferma la connessione HTTPS mutual TLS.

---

## Nota tecnica aggiunta il 27 novembre 2026 — confronto con la seconda sessione manuale di Marco

### Criterio di analisi

Sono stati confrontati i comandi eseguiti sulla VM `10.0.2.134` del 19/11/2026 con il ruolo `testtf2/ansible/roles/wazuh` e con i role comuni/agent. I passaggi manuali validi sono automatizzati; i passaggi errati o temporanei vengono conservati come cronaca e non devono essere ripetuti in futuro.

### Passaggi già automatizzati o corretti da fix precedenti

| Passaggio manuale | Stato Ansible attuale |
|---|---|
| Swap, fstab e `vm.swappiness=10` | Automatizzati nel ruolo Wazuh con swap 2 GB. |
| Fix manuale `CN=admin,OU=Wazuh` e `CN=wazuh-indexer,OU=Wazuh` | Template OpenSearch già corretto: il fix manuale va ignorato. |
| `indexer-security-init.sh` | Eseguito una sola volta mediante marker `/var/lib/wazuh-indexer/.ansible_security_initialized`. |
| Avvio Wazuh Manager | Gestito da `systemd_service`, dopo health check dell'Indexer. |
| Installazione Filebeat | Gestita dal ruolo Wazuh tramite `apt`. |
| IP Filebeat | Configurato tramite `wazuh_manager_ip`, rilevato o passato dall'infrastruttura. |
| Template indici Wazuh per Filebeat | Scaricato dal repository ufficiale nella versione selezionata. |
| Modulo Wazuh Filebeat | Scaricato automaticamente in `/usr/share/filebeat/module`. |
| Certificati Filebeat | Certificato dedicato firmato dalla CA Wazuh e copiato in `/etc/filebeat/certs/`. |
| Mutual TLS | Configurato automaticamente nel file Filebeat. |
| Certificati Dashboard | Copiati con nomi attesi e permessi corretti dal ruolo. |
| Endpoint Dashboard verso l'Indexer | Configurato con `wazuh_manager_ip` tramite Ansible. |
| Avvio Dashboard | Gestito da `systemd_service`. |
| Heap e vm.max_map_count | Già gestiti dal ruolo. |
| Log Nginx e ModSecurity dell'agente WAF | Già configurati da `roles/wazuh_agent/tasks/main.yml`. |
| ModSecurity su VM WAF | Già installato e configurato dal ruolo WAF. |

### Nuovi passaggi automatizzati dalla sessione manuale

Il ruolo Wazuh include ora:

- creazione, inizializzazione e attivazione di `/swapfile`;
- registrazione di `/swapfile` in `/etc/fstab`;
- impostazione persistente di `vm.swappiness=10`;
- creazione del keystore Filebeat;
- configurazione delle chiavi `username` e `password` nel keystore, se la password è fornita;
- installazione del modulo Wazuh per Filebeat;
- verifica del blocco persistente `cluster.blocks.create_index`;
- rimozione automatica controllata del blocco solo se risulta effettivamente impostato a `true`.

Questi task completano il deployment senza cambiare i fix già applicati per DN, certificati dedicati e endpoint dinamico.

### Comandi manuali errati da ignorare

I seguenti passaggi fanno parte della cronaca della seconda sessione, ma **non devono essere riutilizzati come procedura**:

1. `sed` manuale sui DN di `opensearch.yml`, sostituito dal template Ansible corretto.
2. `sed` con `10.0.2.21:9200`, sostituito da `wazuh_manager_ip`.
3. Copia di `filebeat.pem` e `filebeat-key.pem` da `/etc/wazuh-indexer/certs/`, un path dove quei file non esistono.
4. Tentativo di `chmod 400` su un glob vuoto.
5. Rimozione manuale di `ssl.certificate` e `ssl.key`, sostituita dalla configurazione mutual TLS automatica.
6. Copia manuale dei certificati Dashboard, sostituita dal ruolo Wazuh.
7. `sed` manuale dell'endpoint Dashboard a `10.0.2.134:9200`, sostituito da `wazuh_manager_ip`.
8. Rimozione manuale del blocco `cluster.blocks.create_index`, ora verificata e rimossa solo dal role in modo condizionale.

### Comandi di diagnosi ancora utili

Le operazioni seguenti sono diagnostiche e possono essere mantenute al termine del deploy:

```bash
sudo swapon --show
free -h
sudo filebeat test config -c /etc/filebeat/filebeat.yml
sudo filebeat test output -c /etc/filebeat/filebeat.yml
sudo openssl x509 -in /etc/filebeat/certs/filebeat.pem -noout -subject -issuer
sudo systemctl status wazuh-indexer wazuh-manager wazuh-dashboard filebeat --no-pager
sudo /var/ossec/bin/wazuh-control status
sudo /var/ossec/bin/agent_control -l
sudo curl -sS --cacert /etc/wazuh-indexer/certs/root-ca.pem \
  --cert /etc/wazuh-indexer/certs/admin.pem \
  --key /etc/wazuh-indexer/certs/admin-key.pem \
  'https://127.0.0.1:9200/_cluster/health?pretty'
```

### Stato atteso al prossimo deploy

Al bootstrap completo, Ansible deve aver configurato senza intervento manuale:

- Swap e heap dell'Indexer;
- DN dei certificati coerenti;
- Indexer, Manager e Dashboard avviati;
- sicurezza dell'Indexer inizializzata una volta;
- certificato dedicato, CA e mutual TLS di Filebeat;
- endpoint Filebeat e Dashboard dipendenti dall'IP corrente;
- modulo e template Wazuh di Filebeat;
- certificati Dashboard già presenti;
- registro ModSecurity/Nginx già configurato sull'agente WAF;
- blocco persistente degli indici verificato e rimosso solo se necessario.

---

## Nota tecnica aggiunta il 27 novembre 2026 — password amministratore in Ansible Vault

La password amministratore richiesta dal laboratorio è memorizzata cifrata nel file:

```text
testtf2/ansible/group_vars/vault.yml
```

Il file contiene una variabile Ansible cifrata `wazuh_indexer_admin_password` e non può essere letto in chiaro senza la password master Vault. Il master password non è stato inserito nei template Terraform, nei playbook né nei file Markdown.

Il runner Ansible usa automaticamente:

```bash
--vault-password-file /etc/wazuh/ansible-vault-password
```

quando il file master esiste sulla VM con permessi `0600`. Tale file deve essere creato manualmente una sola volta oppure distribuito attraverso un sistema di secrets esterno.

Il `.gitignore` protegge i file master locali da commit accidentali. La password deve essere modificata anche nel backend OpenSearch/Wazuh, non soltanto nel vault: il vault permette ad Ansible/Filebeat di utilizzare la password, ma non sostituisce il cambio della password dell'account `admin` nel sistema Wazuh.
