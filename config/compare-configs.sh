#!/bin/bash

cd "$(dirname "${BASH_SOURCE[0]}")"

ssh='ssh -i ~/.ssh/aws_shimmer ec2-user@shimmer.mit.edu'
configs='
grep -H ^ config.sh
openssl md5 idp-jwks.json
cd clients
echo -n "clients: "
ls -1 *.json | wc -l | xargs
grep -H ^ *.json
'

diff -s \
  --label local-config <(eval "$configs") \
  --label remote-config <($ssh "cd /var/shimmer/config ; $configs")
