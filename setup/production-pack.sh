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

# Install Node.js packages
(
  cd server
  npm install --production
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

# Security updates (all packages, CentOS does not provide security metadata)
sed -e 's/^\(update_cmd *= *\).*/\1default/' \
    -e 's/^\(download_updates *= *\)no/\1yes/' \
    -e 's/^\(apply_updates *= *\)no/\1yes/' -i /etc/yum/yum-cron.conf
systemctl enable yum-cron

# Log to CloudWatch
rpm --install https://s3.amazonaws.com/amazoncloudwatch-agent/centos/amd64/latest/amazon-cloudwatch-agent.rpm
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

# Rotate away logs from provisioning
logrotate -f /etc/logrotate.conf 
