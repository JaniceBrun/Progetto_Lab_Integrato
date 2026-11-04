1. Architettura "Pull" invece che "Push": ansible-pull (Consigliata)
Anziché eseguire Ansible dal GitHub Runner che "spinge" la configurazione verso le VM via SSH (ansible-playbook), sono le VM stesse che "tirano" il codice da GitHub al momento del boot ed eseguono Ansible localmente su 127.0.0.1.
┌──────────────────────────┐
│   GitHub Repository      │
│  (Codice Playbook)       │
└──────────────────────────┘
             ▲
             │ HTTPS (Outbound)
             │
┌──────────────────────────┐
│  VM Privata (User-Data)  │
│  1. Installa Ansible     │
│  2. esegue ansible-pull  │
└──────────────────────────┘

Come funziona: Nel file user_data di Terraform (cloud-init), installi Ansible e lanci:

ansible-pull -U https://github.com/utente/repo.git -i localhost, site.yml

Perché risolve il problema:

Il GitHub Runner non si deve collegare via SSH a nessuna macchinetta.

Non serve SSM.

Il Bastion Host rimane attivo con la porta 22 aperta agli IP del team di Cybersecurity per i loro test di penetrazione.

----------------------
Pre-baking delle Immagini con Packer (Immutable Infrastructure)
Anziché eseguire Ansible su VM già accese, usi Packer nella pipeline prima di Terraform.

Plaintext
[ Pipeline ] ──► Packer + Ansible ──► Crea AMI custom su AWS ──► Terraform lancia VM con l'AMI già pronta
Come funziona: Packer crea una VM temporanea, vi applica il playbook Ansible per installare software e configurazioni, e salva un'immagine disco (AMI AWS). Terraform poi lancia le VM finali partendo da quella AMI.

Vantaggi: All'avvio la VM è già configurata al 100%. Nessun bisogno di connessioni SSH da CI/CD durante il terraform apply.

-----------------------------------
