# sps-2025
This repository contains setup information/automation for the Red Hat demos for SPS 2025. It is provided "as-is", for educational and informative reasons only.

## Demo Architecture

## Setup
The setup for this demo is broken up into several parts:
0. Basic setup
1. Setup bootstrap
2. Setup the ACP
3. Setup the NVIDIA Jetson

### Basic setup
A basic x86 Linux-ish system with sufficient disk space and podman should be able to handle the setup of the demos. You will also need a flash drive, or method to mount installation ISOs to devices.

### Setting basic variables
Create a copy of the `build-args.txt.example` file, and populate it with your information:
```
# RSHM args
RHSM_ORG=123456789
RHSM_AK=ak-whatever

# IPC4 Args
INTERNAL_INTERFACE=enp2s0
EXTERNAL_INTERFACE=enp0s31f6

# IPC4 app args
GITEA_ADMIN_PASSWORD=your-password-here

# OCP install args
# Note: Don't single-quote your pull secret
PULL_SECRET=your-pull-secret
ACP_INSTALL_DEVICE=/dev/sda
ACP_INTERFACE_NAME=enp3s0
ACP_INTERFACE_MAC_ADDRESS=11:22:33:44:55:66
COREOS_SSH_KEY=ssh-ed25519 blahblahblah you@your-computer
```

### Setup IPC4
Assuming your values are correct in your args file, all that needs to be done is to build the IPC4 image and install the device - all other steps are handled through containers on Microshift.

To build the image, run:
```bash
 podman build images/ipc4/ --tag localhost/ipc4:latest --build-arg-file=build-args.txt
```

To create an installation ISO, a script is available in the [scripts](scripts/) directory, which takes 4 arguments:
1. The image to add to the ISO
2. A path to a kickstart file
3. A path to a RHEL boot ISO
4. Where to output the created ISO

An example kickstart file is available in the [kickstarts](kickstarts/) directory.

*You would need to install `skopeo` and `mkksiso` to run the script*  
*Make sure to select the drive in the kickstart which is smaller, since the other one is going to be used to mirror OCP4 images*  

Example script run:
```bash
scripts/create-iso.sh localhost/ipc4:latest  $(pwd)/kickstarts/home-testing.ks ~/Downloads/rhel-9.6-x86_64-boot.iso $(pwd)/test.iso
```

Mount the ISO to the device using your preferred method (probably USB drive), boot from it, and wait a few moments for the install to complete.

To see progress during the installation, switch to one of the other panes using `alt` + `ctrl` +`F2`, and run:
```bash
tail -f /tmp/anaconda.log
```

Once the device reboots, everything should start up on its own.

To get the microshift kubeconfig, log in as your created user and run:
```bash
get-microshift-kubeconfig.sh
```

*If you installed something on the other disk on IPC4, make sure to wipe it, so that the LVM of Microshift can use that with something like `fdisk`*  

This will place the kubeconfig into the default path, so future `oc` commands will work without needing to specify a kubeconfig.

All services are ready when all pods reach `Running` or `Completed`:
```
oc get pods -A
NAMESPACE                              NAME                                                              READY   STATUS      RESTARTS      AGE
dhcp                                   dhcp                                                              1/1     Running     0             31m
dns                                    dns                                                               1/1     Running     0             31m
gitea-operator                         603b4118f8198b060bdc8e06ec74d38a6422d65b43d1fc6195be91491a29lrl   0/1     Completed   0             30m
gitea-operator                         gitea-operator-controller-manager-7fcc5585f5-dhwkn                2/2     Running     0             30m
gitea-operator                         redhat-rhpds-gitea-jjrhw                                          1/1     Running     0             31m
gitea                                  code-694b97bbf5-xk848                                             1/1     Running     0             28m
gitea                                  deploy-gitea-8fs9l                                                0/1     Completed   0             31m
gitea                                  postgresql-code-c45c7d5cc-nwbwr                                   1/1     Running     0             29m
gitea                                  setup-gitea-admin-s2tx4                                           0/1     Completed   0             31m
kube-system                            csi-snapshot-controller-5d77bbb59c-h2swq                          1/1     Running     0             32m
oc-mirror                              registry                                                          1/1     Running     0             31m
oc-mirror                              run-oc-mirror-p2zzv                                               1/1     Running     3 (10m ago)   31m
ocp-agent-install                      install-iso                                                       1/1     Running     0             31m
openshift-dns                          dns-default-7jt67                                                 2/2     Running     0             31m
openshift-dns                          node-resolver-x25vn                                               1/1     Running     0             32m
openshift-ingress                      router-default-7567c7c4df-s2tvt                                   1/1     Running     0             32m
openshift-operator-lifecycle-manager   catalog-operator-7b75665d5b-qf5pl                                 1/1     Running     0             32m
openshift-operator-lifecycle-manager   olm-operator-6d4dd7cd64-x2894                                     1/1     Running     0             32m
openshift-ovn-kubernetes               ovnkube-master-fz5t4                                              4/4     Running     1 (31m ago)   32m
openshift-ovn-kubernetes               ovnkube-node-jxgkq                                                1/1     Running     1 (31m ago)   32m
openshift-service-ca                   service-ca-5b4769d488-jntnk                                       1/1     Running     0             32m
openshift-storage                      lvms-operator-86566ddc69-x9w2l                                    1/1     Running     0             32m
openshift-storage                      vg-manager-nlrqd                                                  1/1     Running     0             31m
```

At this point, connect your computer to the internal demo network - you should get an address in the `192.168.100.0/24` subnet, and have internet access.

### Setup the ACP
The ACP setup is an agent-based install using a local mirror registry located on IPC4. A job on IPC4 will generate the installation ISO for you, all you need to do is download it, mount it to the target installation device, and boot from it. The install should happen automatically from there.

To download the installation ISO, grab it from IPC4:
```bash
wget --no-check-certificate https://serve-iso-ocp-agent-install.apps.ipc4.sps2025.com/agent.x86_64.iso
```

Mount this media to the target installation device (USB drive, etc), and boot from it. The cluster installation should begin and complete automatically.

The cluster kubeconfig and kubeadmin-password files are also available on IPC4:
```
wget --no-check-certificate https://serve-iso-ocp-agent-install.apps.ipc4.sps2025.com/auth/kubeconfig
wget --no-check-certificate https://serve-iso-ocp-agent-install.apps.ipc4.sps2025.com/auth/kubeadmin-password
```

To watch the installation process, two methods are useful:
1. SSH into the CoreOS node and run `sudo journalctl -f`
2. Watch the oprtators come up: `watch -d "oc get co"`

The cluster has baked-in manifests that will be deployed during the install - these should bootstrap GitOps, and link back to Gitea on IPC4.

## Access to systems for SPS 2025  
Please check the repo [here](https://github.com/lucamaf/sps-2025-systems)

