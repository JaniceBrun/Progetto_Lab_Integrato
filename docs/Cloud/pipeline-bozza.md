# Bozza pipeline CI/CD per AWS

## Obiettivo

Questa bozza definisce una pipeline GitHub Actions per il deploy dell'infrastruttura AWS, con una logica iniziale da usare solo su `dev` e con `prod` previsto ma non ancora attivo.

## Trigger

- CI: automatico su `push` e `pull_request`
- CD: manuale tramite `workflow_dispatch`
- Nessun deploy automatico su `main`

## Ambienti

- `dev`: ambiente attivo e pronto per l'uso
- `prod`: previsto come implementazione futura, ma disabilitato finché non saranno definiti account, ruolo IAM e backend Terraform

## Sicurezza e qualità

La pipeline include i controlli minimi richiesti:

- `flake8` per Python ( verificare se necessario altrimenti eliminare)
- `terraform fmt -check`
- `terraform validate`
- `terraform plan` in modalità di simulazione
- `ansible-lint` se è presente codice Ansible
- `checkov` per la scansione di sicurezza su Terraform e Ansible

## Autenticazione AWS

La pipeline usa GitHub OIDC:

- `aws-actions/configure-aws-credentials@v4`
- `role-to-assume` basato su variabili GitHub `vars`
- account `dev` attivo
- account `prod` lasciato come placeholder per future configurazioni

## Parametri placeholder

I seguenti valori devono essere definiti in GitHub repository variables o secrets:

- `AWS_REGION`
- `AWS_ACCOUNT_ID_DEV`
- `AWS_ACCOUNT_ID_PROD`
- `AWS_GITHUB_ACTIONS_ROLE_NAME`
- `TF_STATE_BUCKET`
- `TF_STATE_LOCK_TABLE`

## Comportamento attuale

- `dev` può essere usato in modo manuale tramite `workflow_dispatch`
- `prod` è bloccato finché non verranno definiti i requisiti di sicurezza, account e backend
- `apply` e `destroy` sono entrambi disponibili solo per `dev` in questa fase

## Come usarla in GitHub

1. Vai su GitHub > Actions > `CI - validation and security` e lascia che parta automaticamente su push o pull request.
2. Per il deploy, vai su GitHub > Actions > `CD - deploy or destroy infrastructure` e clicca `Run workflow`.
3. Nella finestra di input seleziona:
   - action: `apply` oppure `destroy`
   - environment: `dev` (in questa fase)
4. La pipeline CD è separata dal workflow CI: non viene lanciata automaticamente da `main`, quindi puoi deciderla manualmente quando serve.
5. Se vuoi fare un test di validazione senza toccare AWS, usa il workflow CI; se vuoi creare o eliminare infrastruttura, usa il workflow CD con `workflow_dispatch`.

## Comandi esatti da usare

```bash
# CI manuale (non necessario in normale uso, ma utile per forzare la validazione)
gh workflow run "CI - validation and security"

# CD manuale: applica infrastruttura su dev
gh workflow run "CD - deploy or destroy infrastructure" \
  -f action=apply \
  -f environment=dev

# CD manuale: distruggi infrastruttura su dev
gh workflow run "CD - deploy or destroy infrastructure" \
  -f action=destroy \
  -f environment=dev
```

Se vuoi usare la pipeline in modo grafico invece che via CLI, apri GitHub > Actions > workflow desiderato > `Run workflow` e inserisci gli stessi valori.


