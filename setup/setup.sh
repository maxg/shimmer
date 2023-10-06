#!/bin/bash

set -eux

# Repositories
curl https://shibboleth.net/cgi-bin/sp_repo.cgi?platform=amazonlinux2023 > /etc/yum.repos.d/shibboleth.repo

# Packages
dnf install -y git gzip tar vim
dnf install -y firewalld httpd mod_ssl augeas-libs shibboleth-3.* nodejs-18.*

npm install -g npm@9

# Apache config
sed -e "s/%%HOSTNAME%%/$shimmer_hostname/" \
    -e "s/%%ALTNAMES%%/${shimmer_altnames//,/ }/" \
  < httpd/shimmer.conf > /etc/httpd/conf.d/shimmer.conf

# Shibboleth config
touchstone=https://touchstone.mit.edu
(
  cd /etc/shibboleth/
  curl -s -O $touchstone/config/shibboleth-sp-3/shibboleth2.xml.in
  curl -s -O $touchstone/config/shibboleth-sp-3/attribute-map.xml
  curl -s -O $touchstone/certs/mit-md-cert.pem
  sed -e "s/%%HOSTNAME%%/${shimmer_entityname:-$shimmer_hostname}/" \
      -e "s/%%SIGNINGKEYPATH%%/sp-signing-key.pem/" \
      -e "s/%%SIGNINGCERTPATH%%/sp-signing-cert.pem/" \
      -e "s/%%ENCRYPTKEYPATH%%/sp-encrypt-key.pem/" \
      -e "s/%%ENCRYPTCERTPATH%%/sp-encrypt-cert.pem/" \
      -e "s/%%HANDLERSSL%%/true/" \
      -e "s/%%COOKIEPROPS%%/https/" \
      -e "s/%%CONTACT_EMAIL%%/$shimmer_contact/" \
      -e "s/%%BEGIN_INCOMMON%%/<!--/" \
      -e "s/%%END_INCOMMON%%/-->/" \
    < shibboleth2.xml.in > shibboleth2.xml
)
