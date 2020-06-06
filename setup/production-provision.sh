#!/bin/bash

set -ex

TLS_FS=$1

cd "$(dirname $0)"/..

# Wait for instance configuration to finish
while [ ! -f /var/lib/cloud/instance/boot-finished ]; do sleep 2; done
sleep 1

# Output and tag SSH host key fingerprints
identity=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document)
export AWS_DEFAULT_REGION=$(jq -r .region <<< $identity)
sudo grep --only-matching 'ec2: .*' /var/log/messages | sed -n '/BEGIN SSH/,/END/p' | tee /dev/fd/2 |
grep --only-matching '.\+ .\+:.\+ .\+ (.\+)' |
while read _ _ hash etc; do echo "Key=SSH ${etc/#*(/(},Value=$hash"; done |
xargs -d "\n" aws ec2 create-tags --resources $(jq -r .instanceId <<< $identity) --tags

source config/config.sh

# Mount TLS filesystem
sudo tee --append /etc/fstab <<< "$TLS_FS"':/ /etc/letsencrypt efs context="system_u:object_r:etc_t:s0",tls,_netdev 0 0'
sudo mount /etc/letsencrypt

# Start Certbot
sudo certbot --apache --non-interactive --agree-tos --email $shimmer_contact --domains $shimmer_hostname
sudo sed --in-place '/<\/VirtualHost>/i SSLProtocol TLSv1.2' /etc/httpd/conf.d/shimmer-le-ssl.conf
sudo systemctl restart httpd
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
