
text
network --bootproto=dhcp --activate
clearpart --all --initlabel --disklabel=gpt
# Ensure you set the correct installation device
ignoredisk --only-use=sda
reqpart --add-boot
part / --grow --fstype xfs
ostreecontainer --url=/run/install/repo/container --transport=oci --no-signature-verification
services --enabled=sshd
user --name="ansible" --groups=wheel --plaintext --password='PUTINAGOODPASSWORD'
rootpw 'PUTINAGOODPASSWORD'
reboot
%post
install -o root -g root -m400 \<\-e \'%wheel\\tALL=\(ALL\)\\tNOPASSWD: ALL\'\) /etc/sudoers.d/freewheelers
systemctl set-default graphical.target
sudo hostnamectl set-hostname ipc4
%end