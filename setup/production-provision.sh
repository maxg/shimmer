#!/bin/bash

set -ex

cd "$(dirname $0)"/..

# Wait for instance configuration to finish
while [ ! -f /var/lib/cloud/instance/boot-finished ]; do sleep 2; done
sleep 1

source config/config.sh

sudo certbot --apache --non-interactive --agree-tos --email $shimmer_contact --domains $shimmer_hostname

sudo mv config/sp-*-*.pem /etc/shibboleth/

# Start daemons
sudo systemctl enable certbot-renew.timer
sudo systemctl start certbot-renew.timer
sudo systemctl enable shibd
sudo systemctl restart shibd
sudo systemctl start shimmer

# Output SSH host key fingerprints
sudo grep --only-matching 'ec2:.*' /var/log/messages
