# To Do - Progetto Lab Integrato

## Priorità 1: allineamento architettura e repository

- [ ] Verificare la struttura finale del repository e definire la cartella di lavoro Terraform definitiva (`Infrastructure/Terraform/Mainterraform` vs root-level `terraform/`)
- [ ] Decidere il modello di naming standard per risorse, ambiente e project (`project-environment-*`) e mantenerlo coerente in tutti i moduli
- [ ] Confermare che i valori di input stabili siano gestiti come variabili per workflow e non come output hardcoded
- [ ] Stabilire il flusso di backend Terraform dedicato: bucket S3 state, locking, cifratura e policy IAM
- [ ] Documentare la convenzione di output runtime vs input statici per pipeline e Ansible

## Priorità 2: correttezza Terraform

- [ ] Validare i moduli Terraform per VPC, subnet, route table, NAT, Internet Gateway, EIP, KMS e security groups
- [ ] Controllare coerenza tra `main.tf`, `variables.tf`, `outputs.tf` e i moduli figli
- [ ] Verificare i nomi di risorse, `depends_on`, `for_each` e riferimenti tra moduli
- [ ] Controllare eventuali incongruenze di naming tra `app`, `juiceshop`, `waf`, `bastion`, `wazuh` e i ruoli attesi dal progetto
- [ ] Verificare che i Security Group rispettino la policy di least privilege e il pattern “SG come sorgente” previsto dal progetto
- [ ] Verificare eventuali lacune su egress/ingress per NAT, bastion, WAF e Wazuh
- [ ] Eseguire `terraform fmt`, `terraform init`, `terraform validate` e `terraform plan` in modo locale/CI

## Priorità 3: pipeline CI/CD e variabili di deploy

- [ ] Allineare la pipeline CI a real path del progetto e ai file Terraform esistenti
- [ ] Correggere i workflow di GitHub Actions per usare il directory Terraform corretta
- [ ] Definire i secrets e le variabili di ambiente richiesti dal deploy: account AWS, bucket tfstate, lock table, OIDC role, project, environment, region
- [ ] Definire la logica di passaggio dei valori dinamici tra Terraform e workflow (`terraform output -json` / artifacts)
- [ ] Disabilitare placeholder non definiti per prod, mantenere solo ambienti validi e verificati
- [ ] Aggiungere gestione esplicita del backend Terraform nel workflow CD
- [ ] Verificare che la pipeline includa il gate Checkov prima del deploy
- [ ] Verificare il flusso `plan` -> approvazione -> `apply` -> output -> inventory Ansible

## Priorità 4: preparazione Ansible e inventory

- [ ] Definire lo schema dell’inventory generato da Terraform per WAF, bastion, Juice Shop e Wazuh
- [ ] Verificare che le variabili Ansible usate in `ansible_inventory` siano coerenti con i nomi host e le regole di rete
- [ ] Verificare i ruoli e i gruppi Ansible previsti (`waf`, `juiceshop`, `wazuh`, `bastion`)
- [ ] Definire come il bastion funge da jump host e come si realizza `ProxyJump` in modo sicuro
- [ ] Preparare i passi di bootstrap e smoke test successivi al deploy

## Priorità 5: sicurezza e compliance

- [ ] Verificare che non ci siano segreti hardcoded né valori sensibili in repository
- [ ] Controllare che IAM, KMS, S3 e bucket tfstate rispettino best practice AWS e least privilege
- [ ] Verificare l’uso di MFA, OIDC e accessi minimizzati
- [ ] Esaminare il rispetto delle best practice Checkov e correggere le violazioni rilevate
- [ ] Documentare requisiti, rischi e mitigazioni per ambiente dev/prod

## Priorità 6: documentazione e tracciabilità

- [ ] Aggiornare la documentazione di architettura con lo stato finale delle scelte implementate
- [ ] Inserire nel repository memory/decision log le scelte rilevanti e le motivazioni tecniche
- [ ] Mantenere un log di verifiche eseguite: validazioni Terraform, Checkov, pipeline e smoke test
- [ ] Verificare la corrispondenza tra documentazione, codice e pipeline

## Sequenza consigliata di esecuzione

1. Allineare la struttura repository + path Terraform + backend
2. Verificare i moduli Terraform e la loro coerenza di naming / variabili / output
3. Correggere pipeline CI/CD in base alla reale struttura del progetto
4. Validare `terraform init`, `validate`, `plan` e Checkov
5. Preparare inventory Ansible & deployment post-apply
6. Documentare decisioni, rischi e verifiche finali

## Stato corrente

- [x] Analisi iniziale del repository
- [x] Verifica di coerenza tra architettura, regole e struttura Terraform
- [x] Identificazione dei punti critici: path pipeline, placeholder AWS, uscita di valori dinamici da Terraform e allineamento ingresso/uscita dati
- [ ] Aggiustamento della struttura pipeline e Terraform
- [ ] Validazione end-to-end di plan/apply e output
