# VM Juice Shop

## Stato documentato

Data di configurazione: 19 novembre 2026.

## Cosa installa il user data Terraform

Il bootstrap comune di `testtf2/user_data/bootstrap.sh.tpl` installa, su tutte le VM applicative:

- Git.
- Ansible.
- File `ansible-pull-lab` in `/usr/local/bin`.
- Servizio systemd `ansible-pull-lab.service`.
- Timer systemd `ansible-pull-lab.timer`, con primo avvio dopo 3 minuti e successivi ogni 15 minuti.
- Connessione al repository Git e selezione di `testtf2/ansible/juiceshop.yml`.
- Versione Wazuh 4.14.10-1 passata agli agenti.
- Chiavi SSH pubbliche dei membri Sara e Marco in `/home/ubuntu/.ssh/authorized_keys`.

La VM Juice Shop è creata in subnet pubblica, con indirizzo pubblico e Elastic IP associata. Le porte esterne configurate sono SSH 22, HTTP 80, HTTPS 443 e Juice Shop 3000.

## Installazioni gestite da Ansible

Il playbook attivo è `testtf2/ansible/juiceshop.yml`.

Roles attivi:

1. `juice`.
2. `wazuh_agent`.

Il ruolo `juice` installa:

- `docker.io`.
- `nginx`.
- Container Docker `bkimminich/juice-shop`.
- Restart policy `unless-stopped`.
- Mapping porta `3000:3000`.
- Vhost nginx sulla porta 80 che effettua proxy verso `http://localhost:3000`.

## Versioni e configurazioni

- Ubuntu 24.04.5 LTS come immagine AWS.
- Wazuh agent fissato a 4.14.10-1.
- Juice Shop usa l'immagine Docker configurata nel repository; il tag non è fissato.
- Docker è abilitato e avviato.
- nginx è abilitato e avviato.
- Il container è raggiungibile localmente sulla porta 3000 e dalla rete pubblica sulla porta 3000 grazie al security group.
- nginx espone anche il servizio sulla porta 80.

## Configurazione Wazuh Agent

L'agente ha:

- Ruolo `juiceshop`.
- Server configurato con `wazuh_manager_ip`.
- Porte 1514 e 1515 attese verso il Manager.
- Monitoraggio dei log Docker JSON in:
  `/var/lib/docker/containers/*/*-json.log`.
- Configurazione in `/var/ossec/etc/ossec.conf` con permessi `0640`, proprietà root:wazuh.

## Storico decisioni e cambiamenti

### 19 novembre 2026

- Individuata causa iniziale dell'endpoint non raggiungibile: il ruolo `juice` era commentato nel playbook.
- Attivato il ruolo `juice`.
- Attivato contemporaneamente `wazuh_agent` per la raccolta log Docker.
- La porta 3000 era già autorizzata nel security group, ma nessun servizio la ascoltava.
- Mantenuto nginx sulla porta 80 come endpoint applicativo locale.
- La user-data passa ora `juiceshop_ip`, ma su questa VM il valore è vuoto perché il container viene raggiunto localmente tramite localhost.

### Nessuna modifica ai software Wazuh

Questa documentazione non introduce modifiche al ruolo Wazuh. Le correzioni Indexer/Manager/Dashboard sono documentate in `VMWazuh.md`.

## Comandi di verifica

```bash
sudo systemctl status ansible-pull-lab.timer
sudo systemctl start ansible-pull-lab.service
sudo systemctl status ansible-pull-lab.service
sudo tail -n 200 /var/log/ansible-pull.log
sudo systemctl status docker --no-pager
sudo docker ps
sudo docker logs juice-shop --tail 100
sudo ss -lntp | grep -E ':(80|3000)\b'
sudo nginx -t
sudo systemctl status nginx --no-pager
curl -I http://127.0.0.1:3000/
curl -I http://127.0.0.1/
sudo systemctl status wazuh-agent --no-pager
sudo tail -n 100 /var/ossec/logs/ossec.log
sudo ls -l /var/lib/docker/containers
```

Dall'esterno:

```bash
curl -I http://<IP_PUBBLICO_JUICE>:3000/
curl -I http://<IP_PUBBLICO_JUICE>/
```
