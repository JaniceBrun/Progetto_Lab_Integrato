# VM Bastion

## Stato documentato

Data di configurazione: 19 novembre 2026.

## Cosa installa il user data Terraform

Il bastion usa una configurazione user data separata definita in `testtf2/main.tf`:

- Crea `/home/ubuntu/.ssh`.
- Imposta `/home/ubuntu/.ssh` con permessi `0700`.
- Crea `/home/ubuntu/.ssh/authorized_keys`.
- Imposta `authorized_keys` con permessi `0600`.
- Configura `apt` e installa `ansible` e `git`.
- Aggiunge le chiavi SSH pubbliche condivise Sara e Marco.

La VM è nella subnet pubblica con Elastic IP. Il security group permette SSH dalla rete internet sulla porta 22.

## Funzione della VM

Il bastion è il punto di accesso SSH alla subnet privata Wazuh.

Funzione prevista:

- SSH in uscita verso Wazuh.
- ProxyJump per i comandi e la connessione alla Dashboard.
- Nessun ruolo Ansible applicativo configurato su questa VM.

## Configurazione SSH raccomandata

Sul PC Windows creare o aggiornare `~/.ssh/config`:

```text
Host bastion
    HostName <IP_PUBBLICO_BASTION>
    User ubuntu
    IdentityFile C:\Users\<utente>\.ssh\id_ed25519
    IdentitiesOnly yes

Host wazuh
    HostName <IP_PRIVATO_WAZUH>
    User ubuntu
    IdentityFile C:\Users\<utente>\.ssh\id_ed25519
    IdentitiesOnly yes
    ProxyJump bastion
```

Il comando diretto equivalente è:

```bash
ssh -i <chiave.pem> -J ubuntu@<IP_BASTION> ubuntu@<IP_PRIVATO_WAZUH>
```

## Storico decisioni e cambiamenti

### 19 novembre 2026

- La chiave privata non viene memorizzata nel repository.
- Le chiavi pubbliche dei membri sono inserite direttamente nel user data Terraform.
- Terraform deve essere riapplicato per aggiungere una chiave a una VM già esistente solo se il user data viene ricostruito; altrimenti l'aggiunta manuale resta necessaria.
- Il security group limita l'accesso SSH Wazuh al security group del bastion.
- Il bastion non è configurato come ansible-pull: gestisce solo la connettività operativa.

## Sicurezza

- Mai inserire o committare chiavi private `.pem` o `id_ed25519`.
- Proteggere `authorized_keys` con permessi `0600`.
- Proteggere la directory `.ssh` con permessi `700`.
- Revocare una chiave removendo la riga pubblica da `/home/ubuntu/.ssh/authorized_keys` su tutte le VM interessate.
- Applicare `StrictHostKeyChecking` solo con cautela quando è necessario un laboratorio temporaneo.

## Comandi di verifica

```bash
sudo systemctl status ssh --no-pager
sudo ls -ld /home/ubuntu/.ssh
sudo stat -c '%U:%G %a %n' /home/ubuntu/.ssh /home/ubuntu/.ssh/authorized_keys
sudo cat /home/ubuntu/.ssh/authorized_keys
sudo ss -lntp | grep ':22\b'
curl -I http://<IP_PUBBLICO_WAF>/
curl -I http://<IP_PUBBLICO_JUICE>:3000/
```

Dal PC:

```bash
ssh -i <chiave.pem> ubuntu@<IP_PUBBLICO_BASTION>
ssh bastion
ssh wazuh
ssh -i <chiave.pem> -L 8443:<IP_PRIVATO_WAZUH>:443 -J ubuntu@<IP_PUBBLICO_BASTION> ubuntu@<IP_PRIVATO_WAZUH>
```

### Test tunnel Dashboard

Aprire nel browser:

```text
https://localhost:8443
```

Controllare sul PC che il tunnel resti attivo e che la Dashboard risponda dopo l'avvio Wazuh.
