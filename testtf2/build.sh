#!/usr/bin/env bash
set -Eeuo pipefail

# build.sh: orchestration locale per Terraform e verifica Ansible.
# Architettura PULL: lo script NON usa SSH o ansible-playbook verso le VM.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

MODE="${1:-apply}"
TF_PLAN="$SCRIPT_DIR/tfplan.binary"
export TF_IN_AUTOMATION=1

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERRORE: '$1' non trovato nel PATH." >&2
    exit 1
  fi
}

case "$MODE" in
  apply|plan|syntax|destroy) ;;
  *)
    echo "Uso: ./build.sh [apply|plan|syntax|destroy]" >&2
    exit 2
    ;;
esac

run_ansible_checks() {
  if command -v ansible-playbook >/dev/null 2>&1; then
    export ANSIBLE_CONFIG="$SCRIPT_DIR/ansible/ansible.cfg"
    echo "==> Controllo sintassi Ansible"
    ansible-playbook --syntax-check -i 'localhost,' -c local ansible/wazuh.yml
    ansible-playbook --syntax-check -i 'localhost,' -c local ansible/waf.yml
    ansible-playbook --syntax-check -i 'localhost,' -c local ansible/juiceshop.yml

    if command -v ansible-lint >/dev/null 2>&1; then
      echo "==> Lint Ansible"
      ansible-lint ansible/wazuh.yml ansible/waf.yml ansible/juiceshop.yml
    else
      echo "INFO: ansible-lint non installato; controllo sintassi completato."
    fi
  else
    echo "AVVISO: ansible-playbook non è installato nel sistema locale."
    echo "        Le verifiche Ansible sono state saltate; eseguirle su Ubuntu con:"
    echo "        sudo apt-get install -y ansible"
    echo "        ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook --syntax-check -i 'localhost,' -c local ansible/wazuh.yml"
  fi
}

if [[ "$MODE" == "syntax" ]]; then
  run_ansible_checks
  exit 0
fi

require_command terraform

echo "==> Terraform format check"
terraform fmt -check -recursive

echo "==> Terraform init"
terraform init -upgrade

if [[ "$MODE" == "apply" ]]; then
  echo "==> Avvio sequenza: init -> validate -> plan -> apply"
fi

echo "==> Terraform validate"
terraform validate

case "$MODE" in
  plan)
    echo "==> Terraform plan"
    terraform plan -out="$TF_PLAN"
    echo "==> Plan completato alle $(date '+%Y-%m-%d %H:%M:%S %Z')"
    ;;
  apply)
    echo "==> Terraform plan"
    terraform plan -out="$TF_PLAN"

    echo "==> Terraform apply"
    terraform apply "$TF_PLAN"

    APPLY_COMPLETED_AT="$(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "==> Terraform apply completato alle $APPLY_COMPLETED_AT"
    rm -f "$TF_PLAN"
    ;;
  destroy)
    echo "==> Terraform destroy"
    terraform destroy
    ;;
esac

run_ansible_checks

echo "==> Completato"
echo "Le VM eseguono ansible-pull autonomamente tramite cloud-init/timer."
echo "Per rilanciare manualmente da una singola VM: sudo systemctl start ansible-pull-lab.service"
