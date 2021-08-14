#!/bin/bash

set -eux

cd /vagrant

(
  cd config
  [ -f config.sh ] || cat > config.sh <<EOD
export shimmer_domain=localhost
export shimmer_hostname=10.18.6.60
export shimmer_altnames=
export shimmer_entityname=
export shimmer_contact=shimmer@localhost
EOD
)
source config/config.sh

source setup/setup.sh

(
  cd config
  [ -f sp-signing-key.pem ] || /etc/shibboleth/keygen.sh -b -h $shimmer_hostname -n sp-signing
  [ -f sp-encrypt-key.pem ] || /etc/shibboleth/keygen.sh -b -h $shimmer_hostname -n sp-encrypt
)
cp config/sp-*-*.pem /etc/shibboleth/

systemctl enable shibd
systemctl restart shibd
