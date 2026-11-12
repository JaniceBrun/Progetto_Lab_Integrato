# Gestione chiavi SSH

## Ogni membro del team genera la propria chiave

```bash
ssh-keygen -t ed25519 -C "nome.cognome"
```

Vengono creati due file:
- `~/.ssh/id_ed25519` — chiave **privata**, non condividere mai
- `~/.ssh/id_ed25519.pub` — chiave **pubblica**, da condividere con chi gestisce l'infrastruttura

---

## Aggiungere una chiave a una VM

Chi gestisce Terraform aggiunge la chiave pubblica nel `user_data` della VM interessata in `main.tf`:

```hcl
bastion_userdata = <<-EOF
  #!/bin/bash
  echo "ssh-ed25519 AAAA...chiave-pubblica-persona" >> /home/ubuntu/.ssh/authorized_keys
  chmod 600 /home/ubuntu/.ssh/authorized_keys
EOF
```

Poi:
```bash
terraform apply
```

> Il `user_data` viene eseguito solo al **primo avvio**. Per aggiungere chiavi a VM già in esecuzione vai alla sezione [Aggiunta manuale su VM esistente](#aggiunta-manuale-su-vm-esistente).

---

## Connettersi via SSH

**VM pubbliche (juice, waf, bastion):**
```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@<ip_pubblico>
```

**Wazuh (subnet privata) tramite bastion:**
```bash
ssh -i ~/.ssh/id_ed25519 -J ubuntu@<bastion_ip> ubuntu@<wazuh_private_ip>
```

**Accesso da bastion - modificare ~/.ssh/config su pc con ip corretti
Host bastion
  HostName <bastion_ip>
  User ubuntu
  IdentityFile ~/percorso/miaokey.pem

Host wazuh
  HostName <wazuh_private_ip>
  User ubuntu
  IdentityFile ~/percorso/miaokey.pem
  ProxyJump bastion


Gli IP vengono stampati da Terraform dopo ogni `apply`:
```bash
terraform output
```

---

## Aggiunta manuale su VM esistente

Se la VM è già in esecuzione, connettiti e aggiungi la chiave a mano:

```bash
echo "ssh-ed25519 AAAA...chiave-pubblica-persona" >> /home/ubuntu/.ssh/authorized_keys
```

---

## Revocare l'accesso

Rimuovi la riga corrispondente da `/home/ubuntu/.ssh/authorized_keys` su ogni VM a cui aveva accesso:

```bash
ssh ubuntu@<ip> "sed -i '/nome.cognome/d' /home/ubuntu/.ssh/authorized_keys"
```

---

## Note di sicurezza

- Non condividere mai la chiave privata (file senza `.pub`)
- Non committare chiavi private nella repo — il `.gitignore` esclude già `id_*` e `*.pem`
- Usa sempre `-t ed25519`, è più sicuro e compatto di RSA
