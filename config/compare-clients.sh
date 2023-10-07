#!/bin/bash

cd "$(dirname "${BASH_SOURCE[0]}")"

ssh='ssh -i ~/.ssh/aws_shimmer ec2-user@shimmer.mit.edu'
clients='ls -1 *.json | wc -l | xargs ; grep -H ^ *.json'

diff -s \
  --label all-local-clients <(cd clients ; eval "$clients") \
  --label all-remote-clients <($ssh "cd /var/shimmer/config/clients ; $clients")
