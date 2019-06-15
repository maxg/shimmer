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

[Install]
WantedBy=multi-user.target
EOD

# Security updates (all packages, CentOS does not provide security metadata)
sed -e 's/^\(update_cmd *= *\).*/\1default/' \
    -e 's/^\(download_updates *= *\)no/\1yes/' \
    -e 's/^\(apply_updates *= *\)no/\1yes/' -i /etc/yum/yum-cron.conf
systemctl enable yum-cron

# Rotate away logs from provisioning
logrotate -f /etc/logrotate.conf 
