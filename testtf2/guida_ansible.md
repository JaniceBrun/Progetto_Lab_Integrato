# Guida Ansible PULL con Terraform

Questa guida descrive i comandi da eseguire uno alla volta. L'architettura usa **ansible-pull**: il PC non si collega alle VM tramite SSH per lanciare Ansible; ogni VM clona il repository e esegue il proprio playbook in locale.

## 1. Aprire la shell corretta

Su Windows usare **Git Bash** o **WSL**. PowerShell non è adatto all'esecuzione diretta dello script Bash.

```bash
cd /c/Users/janice.brun/Desktop/Progetto_Lab_Integrato/testtf2
```

Verificare la directory:

```bash
pwd
ls
```

## 2. Verificare Terraform

Controllare la formattazione:

```bash
terraform fmt -check -recursive
```

Inizializzare i provider:

```bash
terraform init -upgrade
```

L'inizializzazione crea o aggiorna `.terraform` e il file di locking.

Validare la configurazione:

```bash
terraform validate
```

## 3. Creare il piano Terraform

```bash
terraform plan -out=tfplan.binary
```

Esaminare attentamente il piano. Verificare in particolare:

- Wazuh con indirizzo privato assegnato dinamicamente dalla subnet privata.
- Wazuh nel volume privato con il volume configurato da Terraform.
- User data con i playbook `wazuh.yml`, `waf.yml` e `juiceshop.yml`.
- Nessuna modifica distruttiva inattesa.

## 4. Applicare l'infrastruttura

```bash
terraform apply tfplan.binary
```

In alternativa, lo script completo può eseguire init, validate, plan e apply:

```bash
./build.sh apply
```

Al termine, Terraform crea o aggiorna EC2, reti, security group e user data. Non lancia playbook Ansible dal PC.

## 5. Verificare il bootstrap sulle VM

I comandi seguenti richiedono l'accesso alla singola VM tramite bastion o console disponibile nel laboratorio.

Controllare l'output completo di cloud-init:

```bash
sudo tail -n 200 /var/log/cloud-init-output.log
```

Controllare il log ansible-pull:

```bash
sudo tail -n 200 /var/log/ansible-pull.log
```

Seguire l'esecuzione in tempo reale:

```bash
sudo journalctl -u ansible-pull-lab.service -f
```

## 6. Controllare il timer PULL

Verificare che il timer sia attivo:

```bash
sudo systemctl status ansible-pull-lab.timer
```

Mostrare i prossimi avvii:

```bash
sudo systemctl list-timers ansible-pull-lab.timer
```

Il timer ripete ansible-pull ogni 15 minuti.

## 7. Rilanciare ansible-pull manualmente

Per rilanciare il ciclo sulla VM corrente:

```bash
sudo systemctl start ansible-pull-lab.service
```

Controllarne l'esito:

```bash
sudo systemctl status ansible-pull-lab.service
sudo journalctl -u ansible-pull-lab.service --since "10 minutes ago"
```

Il playbook può essere provato direttamente dalla copia clonata dal repository. Ottieni prima l'IP privato reale da Terraform:

```bash
terraform output -raw wazuh_private_ip
```

Impostalo in una shell e rilancia il playbook:

```bash
WAZUH_IP=$(terraform -chdir=/percorso/Progetto_Lab_Integrato/testtf2 output -raw wazuh_private_ip)
cd /opt/ansible-pull/ansible
sudo ansible-pull -U https://github.com/JaniceBrun/Progetto_Lab_Integrato.git -C main -d /opt/ansible-pull -i localhost, -c local --purge ansible/wazuh.yml -e "wazuh_manager_ip=$(hostname -I | awk '{print $1}')"
```

Questo comando va eseguito **solo sulla VM Wazuh**. Sulla WAF e su Juice Shop usa l'IP recuperato da Terraform:

```bash
sudo ansible-pull -U https://github.com/JaniceBrun/Progetto_Lab_Integrato.git -C main -d /opt/ansible-pull -i localhost, -c local --purge ansible/waf.yml -e "wazuh_manager_ip=$WAZUH_IP"
```

```bash
sudo ansible-pull -U https://github.com/JaniceBrun/Progetto_Lab_Integrato.git -C main -d /opt/ansible-pull -i localhost, -c local --purge ansible/juiceshop.yml -e "wazuh_manager_ip=$WAZUH_IP"
```

## 8. Verificare i servizi Wazuh

Sulla VM Wazuh:

```bash
sudo systemctl status wazuh-indexer
```

```bash
sudo systemctl status wazuh-manager
```

```bash
sudo systemctl status wazuh-dashboard
```

Verificare che tutte le porte siano in ascolto:

```bash
sudo ss -lntp | grep -E ':(1514|1515|9200|443)\b'
```

Attendere che il Manager sia pronto prima di controllare l'aggiornamento degli agenti:

```bash
sudo /var/ossec/bin/wazuh-control status
```

## 9. Verificare gli agenti Wazuh

Sulla VM WAF:

```bash
sudo systemctl status wazuh-agent
sudo /var/ossec/bin/agent_control -l
```

Sulla VM Juice Shop:

```bash
sudo systemctl status wazuh-agent
sudo /var/ossec/bin/agent_control -l
```

Per vedere lo stato di connessione dell'agente:

```bash
sudo tail -n 100 /var/ossec/logs/ossec.log
```

## 10. Controllare i log raccolti dalla WAF

```bash
sudo ls -l /var/log/nginx/access.log /var/log/nginx/error.log /var/log/modsec_audit.log
```

Questi file devono esistere affinché gli eventi vengano ricevuti dall'agente Wazuh.

## 11. Controllare i log Docker su Juice Shop

```bash
sudo find /var/lib/docker/containers -name '*-json.log' -ls
```

Verificare che Docker sia attivo:

```bash
sudo systemctl status docker
```

## 12. Verificare la password locale della dashboard

La password viene generata una sola volta sulla VM Wazuh dal ruolo Ansible.

```bash
sudo ls -l /etc/wazuh-dashboard/.wazuh_admin_pass
sudo stat -c '%U:%G %a %n' /etc/wazuh-dashboard/.wazuh_admin_pass
```

Leggere la password, quando necessario:

```bash
sudo cat /etc/wazuh-dashboard/.wazuh_admin_pass
```

Il file deve essere leggibile solo da `root` e dal gruppo `wazuh-dashboard`, con permessi `0600`. Non inserire la password nel repository o negli script Terraform.

## 13. Aprire il tunnel SSH verso la dashboard

Dal PC locale, sostituire `<IP_BASTION>` con l'IP pubblico del bastion:

```bash
ssh -i miaokey.pem -L 8443:10.0.2.10:443 -J ubuntu@<IP_BASTION> ubuntu@10.0.2.10
```

Non chiudere questa sessione SSH. Nel browser aprire:

```text
https://localhost:8443
```

Accedere con l'utente configurato da Wazuh e la password letta dal file locale sopra.

## 14. Controlli Ansible dal PC

Questi comandi verificano la sintassi locale senza collegarsi alle VM:

```bash
cd /c/Users/janice.brun/Desktop/Progetto_Lab_Integrato/testtf2
export ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg"
ansible-playbook --syntax-check -i 'localhost,' -c local ansible/wazuh.yml
ansible-playbook --syntax-check -i 'localhost,' -c local ansible/waf.yml
ansible-playbook --syntax-check -i 'localhost,' -c local ansible/juiceshop.yml
```

Per la verifica completa dello script:

```bash
./build.sh syntax
```

Questo comando non modifica l'infrastruttura e non distribuisce nulla tramite SSH.

## 15. Distruggere l'infrastruttura

Solo quando il laboratorio deve essere eliminato:

```bash
terraform plan -destroy
```

```bash
terraform destroy
```

Oppure:

```bash
./build.sh destroy
```

## Ordine consigliato

1. Wazuh si avvia e installa Manager, Indexer e Dashboard.
2. WAF e Juice Shop avviano il bootstrap e attendono la porta `1515` del Manager.
3. Il timer ripete il pull ogni 15 minuti se una delle prime esecuzioni fallisce.
4. Il tunnel SSH dal bastion rende disponibile la dashboard sul browser locale.
