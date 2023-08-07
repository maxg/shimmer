#!/bin/bash

set -eux

# Wait for instance configuration to finish
while [ ! -f /var/lib/cloud/instance/boot-finished ]; do sleep 2; done

# Go to app directory & obtain application code
mkdir /var/$APP
cd /var/$APP
tar xf /tmp/$APP.tar
mv /tmp/config.sh config/

# Create daemon user
adduser --system $APP

source config/config.sh

source setup/setup.sh

chown -R $ADMIN:$ADMIN /var/$APP
chown -R $ADMIN:$APP config
chmod 770 config

# Packages
dnf install -y amazon-efs-utils amazon-cloudwatch-agent rsyslog

# Install Certbot
python3 -m venv /opt/certbot
/opt/certbot/bin/pip install --upgrade pip
/opt/certbot/bin/pip install certbot certbot-apache
cat > /lib/systemd/system/certbot-renew.service <<EOD
[Service]
Type=oneshot
ExecStart=/opt/certbot/bin/certbot -q renew
PrivateTmp=true
EOD
cat > /lib/systemd/system/certbot-renew.timer <<EOD
[Timer]
OnCalendar=*-*-* 00:00:00
RandomizedDelaySec=43200

[Install]
WantedBy=timers.target
EOD

(
  cd server
  # Install Node.js packages
  sudo -u $ADMIN npm ci
  # Build app
  sudo -u $ADMIN npm exec tsc
)

# Daemon
cat > /lib/systemd/system/$APP.service <<EOD
[Unit]
After=network.target

[Service]
User=$APP
ExecStart=/var/$APP/server/$APP
Restart=always

[Install]
WantedBy=multi-user.target
EOD

# Log to CloudWatch
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOD
{
  "agent": { "run_as_user": "cwagent" },
  "logs": { "logs_collected": { "files": { "collect_list": [
    {
      "file_path": "/var/log/messages",
      "log_group_name": "/cwagent/$APP-messages",
      "timestamp_format": "%b %-d %H:%M:%S"
    },
    {
      "file_path": "/var/log/shibboleth/transaction.log",
      "log_group_name": "/cwagent/$APP-shibboleth-transaction-log",
      "timestamp_format": "%Y-%m-%d %H:%M:%S"
    },
    {
      "file_path": "/var/log/httpd/access_log",
      "log_group_name": "/cwagent/$APP-httpd-access-log",
      "timestamp_format": "%d/%b/%Y:%H:%M:%S %z"
    },
    {
      "file_path": "/var/log/httpd/error_log",
      "log_group_name": "/cwagent/$APP-httpd-error-log",
      "timestamp_format": "%a %b %d %H:%M:%S"
    }
  ] } } }
}
EOD

systemctl enable httpd

systemctl restart firewalld
firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=https --permanent
systemctl restart firewalld

timedatectl set-timezone America/New_York

# Rotate away logs from provisioning
logrotate -f /etc/logrotate.conf
