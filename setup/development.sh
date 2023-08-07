#!/bin/bash

set -eux

cd "$(dirname "${BASH_SOURCE[0]}")"/..

source config/config.sh.example

source setup/setup.sh

# Repositories
curl https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo > /etc/yum.repos.d/hashicorp.repo

# Packages
dnf install -y packer-1.* terraform-1.*
dnf clean all
rm -rf /var/cache/dnf
