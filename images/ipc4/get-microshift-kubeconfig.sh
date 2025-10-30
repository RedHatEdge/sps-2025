#!/bin/bash

mkdir -p ~/.kube/
sudo cat /var/lib/microshift/resources/kubeadmin/kubeconfig > ~/.kube/config