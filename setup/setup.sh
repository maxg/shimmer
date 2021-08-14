#!/bin/bash

set -eux

# Yum Repositories
(
  cd /etc/yum.repos.d
  [ -f Shibboleth.repo ] || curl https://shibboleth.net/cgi-bin/sp_repo.cgi?platform=CentOS_7 > Shibboleth.repo
)
rpm --query nodesource-release-el7-1.noarch || rpm --install --nosignature https://rpm.nodesource.com/pub_12.x/el/7/x86_64/nodesource-release-el7-1.noarch.rpm

# Yum Packages
yum -y update
yum -y install epel-release centos-release-scl yum-cron zip unzip gcc-c++ make git vim
yum -y install gcc openssl-devel tcp_wrappers-devel rpm-build
yum -y install firewalld httpd mod_ssl certbot python2-certbot-apache shibboleth.x86_64 nodejs awscli jq

# stunnel
(
  cd /tmp
  curl -O https://www.stunnel.org/downloads/stunnel-5.59.tar.gz
  touch stunnel.init stunnel.logrotate
  rpmbuild -ta stunnel-5.*.tar.gz --define '_unpackaged_files_terminate_build 0'
  yum -y install ~/rpmbuild/RPMS/x86_64/stunnel-5.*.el7.x86_64.rpm
)

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
  sed -e "s/%%HOSTNAME%%/$shimmer_hostname/" \
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

systemctl enable httpd
systemctl restart httpd

systemctl enable firewalld
systemctl restart firewalld
firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=https --permanent
systemctl restart firewalld

timedatectl set-timezone America/New_York 
