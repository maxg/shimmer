#!/bin/bash

set -ex

cd "$(dirname $0)"/..

imds_token=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
instance_id=$(curl -s -H "X-aws-ec2-metadata-token: $imds_token" http://169.254.169.254/latest/meta-data/instance-id)

# Output and tag SSH host key fingerprints
for f in /etc/ssh/ssh_host_*key.pub; do ssh-keygen -l -f "$f"; done |
while read _ hash _ type; do echo "Key=SSH $type,Value=$hash"; done |
xargs -d "\n" aws ec2 create-tags --resources $instance_id --tags

source config/config.sh

# Mount TLS filesystem
sudo tee --append /etc/fstab <<< "$TLS_FS"':/ /etc/letsencrypt efs tls,_netdev 0 0'
sudo mkdir /etc/letsencrypt
sudo mount /etc/letsencrypt

# Start Certbot
sudo /opt/certbot/bin/certbot --apache --non-interactive --agree-tos --email $shimmer_contact --domains $shimmer_hostname$shimmer_altnames
sudo sed --in-place '/<\/VirtualHost>/i SSLProtocol TLSv1.2' /etc/httpd/conf.d/shimmer-le-ssl.conf
sudo systemctl restart httpd
sudo systemctl --now enable certbot-renew.timer

# Start Shibboleth
sudo mv config/sp-*-*.pem /etc/shibboleth/
sudo systemctl restart shibd

# Start CloudWatch Agent
sudo setfacl -R -m u:cwagent:rX /var/log
sudo systemctl --now enable amazon-cloudwatch-agent

# Start daemon
sudo systemctl --now enable shimmer
