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

### Setup the ACP
The ACP setup is an agent-based install using a local mirror registry located on IPC4. A job on IPC4 will generate the installation ISO for you, all you need to do is download it, mount it to the target installation device, and boot from it. The install should happen automatically from there.

