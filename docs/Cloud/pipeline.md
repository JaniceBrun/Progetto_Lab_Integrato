PR / lancio manuale
      │
      ▼
 1. fmt + validate + Checkov (terraform/ e ansible/) + ansible-lint
      │
      ▼
 2. terraform plan  (OIDC → ruolo AWS, backend.hcl dell'ambiente)
      │   approvazione manuale (Environment)
      ▼
 3. terraform apply  →  output: ansible_inventory, IP, ID
      │   inventory.yml passato come artifact
      ▼
 4. ansible-playbook (ProxyJump sul bastion)
      │
      ▼
 5. smoke test: curl sul WAF, agent Wazuh connessi
