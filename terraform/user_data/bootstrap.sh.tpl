#!/bin/bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

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
exec /usr/bin/ansible-pull \
  -U '{{ repo_url }}' \
  -C '{{ repo_branch }}' \
  -d /opt/ansible-pull \
  -i localhost, \
  -c local \
  --purge \
  ansible/{{ playbook }} \
  -e 'wazuh_manager_ip={{ wazuh_manager_ip }}' \
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
