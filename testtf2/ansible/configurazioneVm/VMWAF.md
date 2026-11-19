# VM WAF

## Stato documentato

Data di configurazione: 19 novembre 2026.

## Cosa installa il user data Terraform

Il bootstrap comune installa:

- Git e Ansible.
- Script `/usr/local/bin/ansible-pull-lab`.
- Timer systemd che esegue ansible-pull ogni 15 minuti.
- Repository remoto `JaniceBrun/Progetto_Lab_Integrato` sul branch `janice-synctest`.
- Playbook `testtf2/ansible/waf.yml`.
- IP privato Wazuh come `wazuh_manager_ip`.
- IP privato Juice Shop come `juiceshop_ip`.
- Chiavi SSH pubbliche condivise.

La VM WAF è in subnet pubblica con Elastic IP e security group dedicato. Le porte aperte verso internet sono SSH 22, HTTP 80 e HTTPS 443.

## Installazioni gestite da Ansible

Il playbook attivo è `testtf2/ansible/waf.yml`.

Roles attivi:

1. `waf`.
2. `wazuh_agent`.

Il ruolo `waf` installa:

- nginx.
- ModSecurity 2 tramite `libnginx-mod-security2`.
- Git.
- OWASP CRS nel repository `/etc/nginx/modsecurity-crs`.
- Configurazione CRS di esempio copiata in `/etc/modsecurity/crs-setup.conf`.
- Configurazione `/etc/modsecurity/modsecurity.conf`.
- Vhost nginx in `/etc/nginx/sites-available/default`.

## Configurazione nginx

Il vhost attuale:

- Ascolta sulla porta 80.
- Attiva ModSecurity nel server.
- Usa `/etc/modsecurity/modsecurity.conf`.
- Effettua proxy verso `http://<IP_PRIVATO_JUICE_SHOP>:3000`.
- Propaga `Host`, `X-Real-IP` e `X-Forwarded-For`.

Il passaggio all'IP privato Juice sostituisce i vecchi endpoint/host fissi e permette alle VM di comunicare nella stessa VPC.

## Stato ModSecurity attuale

Configurazione attuale: traffico permesso.

`modsec_engine` è impostato su `Off` nel gruppo `ansible/group_vars/all.yml`, quindi il template genera:

```text
SecRuleEngine Off
```

Permangono l'accesso al body, i limiti di protezione, l'audit engine `RelevantOnly` e il log in `/var/log/modsec_audit.log`. Questa impostazione permette tutto il traffico per consentire l'uso del laboratorio finché non vengono create/rate regole di blocco.

## Configurazione Wazuh Agent

L'agente monitora:

- `/var/log/nginx/access.log` con formato syslog.
- `/var/log/nginx/error.log` con formato syslog.
- `/var/log/modsec_audit.log` con formato JSON.

L'indirizzo Manager è impostato tramite `wazuh_manager_ip`, fornito da Terraform.

## Storico decisioni e cambiamenti

### 19 novembre 2026

- Individuata causa iniziale dell'assenza del reverse proxy: il ruolo `waf` era commentato nel playbook.
- Attivato il ruolo `waf`.
- Attivato il ruolo `wazuh_agent` nello stesso run.
- Aggiunta la variabile `juiceshop_ip` al bootstrap Terraform e ad `ansible-pull`.
- Configurato il proxy verso l'IP privato Juice Shop invece di usare una configurazione fissa o il diretto pubblico.
- Impostato ModSecurity su `Off` per consentire tutto il traffico durante questa fase.
- Le porte `80` e `3000` restano aperte dal security group; nessuna regola ModSecurity attuale blocca la richiesta.

### Modifiche future da registrare

Ogni futura regola ModSecurity deve essere documentata in questa sezione con data, regola aggiunta, modalità Detection/Blocking e risultato testato.

## Comandi di verifica

```bash
sudo systemctl status ansible-pull-lab.timer
sudo systemctl start ansible-pull-lab.service
sudo systemctl status ansible-pull-lab.service
sudo tail -n 200 /var/log/ansible-pull.log
sudo nginx -t
sudo systemctl status nginx --no-pager
sudo ss -lntp | grep -E ':(80|443)\b'
curl -I http://127.0.0.1/
curl -I http://<IP_PRIVATO_JUICE>:3000/
sudo grep -n 'SecRuleEngine' /etc/modsecurity/modsecurity.conf
sudo systemctl status wazuh-agent --no-pager
sudo tail -n 100 /var/ossec/logs/ossec.log
sudo ls -l /var/log/nginx/access.log /var/log/nginx/error.log /var/log/modsec_audit.log
sudo tail -n 100 /var/log/nginx/access.log
sudo tail -n 100 /var/log/nginx/error.log
```

Dall'esterno:

```bash
curl -I http://<IP_PUBBLICO_WAF>/
```
