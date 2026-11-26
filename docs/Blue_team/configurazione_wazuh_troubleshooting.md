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
