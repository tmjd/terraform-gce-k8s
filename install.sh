#!/bin/bash
set -e

apt-get update -qq && apt-get install -qq -y apt-transport-https
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update -qq
apt-get install -qq -y docker.io kubelet kubeadm kubectl kubernetes-cni
