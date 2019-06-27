#!/bin/bash

set -ex

cd "$(dirname $0)"/..

# Wait for instance configuration to finish
while [ ! -f /var/lib/cloud/instance/boot-finished ]; do sleep 2; done
sleep 1

source config/config.sh

# Start Certbot
sudo certbot --apache --non-interactive --agree-tos --email $shimmer_contact --domains $shimmer_hostname
sudo systemctl --now enable certbot-renew.timer

# Start Shibboleth
sudo mv config/sp-*-*.pem /etc/shibboleth/
sudo systemctl enable shibd
sudo systemctl restart shibd

# Start CloudWatch Agent
sudo setfacl -R -m u:cwagent:rX /var/log
sudo systemctl --now enable amazon-cloudwatch-agent

# Start daemon
sudo systemctl --now enable shimmer

# Output SSH host key fingerprints
sudo grep --only-matching 'ec2:.*' /var/log/messages
