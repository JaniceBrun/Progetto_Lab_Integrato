#!/bin/bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

# Installazione anticipata delle chiavi SSH condivise, prima delle operazioni apt.
mkdir -p /home/ubuntu/.ssh
chmod 700 /home/ubuntu/.ssh
chown ubuntu:ubuntu /home/ubuntu/.ssh
touch /home/ubuntu/.ssh/authorized_keys
chmod 600 /home/ubuntu/.ssh/authorized_keys
chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys

grep -qxF 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIANI89MdEkKMcZYadmcCQ9YJEEAPXCb8+QjChd7d4GmP marco_progettolab' /home/ubuntu/.ssh/authorized_keys || \
  echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIANI89MdEkKMcZYadmcCQ9YJEEAPXCb8+QjChd7d4GmP marco_progettolab' >> /home/ubuntu/.ssh/authorized_keys

grep -qxF 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHYfUpoFu9qKnWWakZSRPCL7XOkrbiZZURXleIcc0yJw sara.progetto' /home/ubuntu/.ssh/authorized_keys || \
  echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHYfUpoFu9qKnWWakZSRPCL7XOkrbiZZURXleIcc0yJw sara.progetto' >> /home/ubuntu/.ssh/authorized_keys

grep -qxF 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK9GBRnl3PwUOULGi6bCVHK+r5EAFd6l7aeMJTNaJwf5 yousef' /home/ubuntu/.ssh/authorized_keys || \
  echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK9GBRnl3PwUOULGi6bCVHK+r5EAFd6l7aeMJTNaJwf5 yousef' >> /home/ubuntu/.ssh/authorized_keys

grep -qxF 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAToUD702j4+kKSr4PWyJh1IwdPbdY8ckyqqe/UXbj/e alessandro.tassone' /home/ubuntu/.ssh/authorized_keys || \
  echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAToUD702j4+kKSr4PWyJh1IwdPbdY8ckyqqe/UXbj/e alessandro.tassone' >> /home/ubuntu/.ssh/authorized_keys

echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4

# Ubuntu 24.04: Ansible è disponibile dal repository universe.
apt-get update -y
apt-get install -y software-properties-common
add-apt-repository -y universe
apt-get update -y
apt-get install -y git ansible

mkdir -p /opt/ansible-pull
mkdir -p /var/log
install -m 0640 /dev/null /var/log/ansible-pull.log

cat > /usr/local/bin/ansible-pull-lab <<'RUNNER'
#!/bin/bash
set -uo pipefail

WAZUH_MANAGER_IP='${wazuh_manager_ip}'
JUICESHOP_IP='${juiceshop_ip}'
if [ '${playbook}' = 'wazuh.yml' ]; then
  WAZUH_MANAGER_IP="$(hostname -I | awk '{print $1}')"
fi

WAZUH_VERSION='4.14.10-1'
WAZUH_VAULT_PASSWORD_FILE='/etc/wazuh/ansible-vault-password'
VAULT_ARGS=()
if [ -f "$WAZUH_VAULT_PASSWORD_FILE" ]; then
  VAULT_ARGS=(--vault-password-file "$WAZUH_VAULT_PASSWORD_FILE")
fi

exec flock -n /var/lock/ansible-pull-lab.lock /usr/bin/ansible-pull \
  "$${VAULT_ARGS[@]}" \
  -U '${repo_url}' \
  -C '${repo_branch}' \
  -d /opt/ansible-pull \
  -i localhost, \
  -c local \
  testtf2/ansible/${playbook} \
  -e "wazuh_manager_ip=$WAZUH_MANAGER_IP" \
  -e "juiceshop_ip=$JUICESHOP_IP" \
  -e "wazuh_version=$WAZUH_VERSION" \
  >> /var/log/ansible-pull.log 2>&1
RUNNER
chmod 0750 /usr/local/bin/ansible-pull-lab

cat > /etc/systemd/system/ansible-pull-lab.service <<'UNIT'
[Unit]
Description=Convergenza Ansible PULL del laboratorio
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=/
ExecStart=/usr/local/bin/ansible-pull-lab
UNIT

cat > /etc/systemd/system/ansible-pull-lab.timer <<'UNIT'
[Unit]
Description=Esegue ansible-pull ogni 15 minuti

[Timer]
OnBootSec=3min
OnUnitActiveSec=15min
Persistent=true
Unit=ansible-pull-lab.service

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now ansible-pull-lab.timer

# Primo tentativo immediato: il timer riproverà anche dopo un errore.
/usr/local/bin/ansible-pull-lab || true

mkdir -p /etc/wazuh
chmod 0700 /etc/wazuh
