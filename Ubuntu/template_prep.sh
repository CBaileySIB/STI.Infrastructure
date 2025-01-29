#!/bin/bash
#
# this script patches an ubuntu machine, resets the hostname, resets the machine-id
# and prepares for it to be templated
#

# Check for elevated permissions
if [ `id -u` -ne 0 ]; then
	echo Need sudo
	exit 1
fi

set -v

# Install updates
sudo apt update -y
sudo apt dist-upgrade -y

# Install basic OS packages, vmware tools, etc.
# Then autoremove unneeded packages and clean apt cache 
sudo apt install vim git dos2unix zip unzip curl wget dnsutils traceroute open-vm-tools -y
sudo apt autoremove -y
sudo apt clean

# Disable ipv6
echo net.ipv6.conf.all.disable_ipv6=1 | sudo tee -a /etc/sysctl.conf
echo net.ipv6.conf.default.disable_ipv6=1 | sudo tee -a /etc/sysctl.conf
echo net.ipv6.conf.lo.disable_ipv6=1 | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Stop services for cleanup
sudo service rsyslog stop

# Clear audit logs
if [ -f /var/log/wtmp ]; then
    sudo truncate -s0 /var/log/wtmp
fi
if [ -f /var/log/lastlog ]; then
    sudo truncate -s0 /var/log/lastlog
fi

# Cleanup /tmp directories
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*

# This adds a check for ssh keys on reboot and regenerates if necessary
cat << 'EOL' | sudo tee /etc/rc.local
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will return "" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

# Dynamically create hostname
if hostname | grep localhost; then
    hostnamectl set-hostname "$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo '')"
fi

test -f /etc/ssh/ssh_host_dsa_key || dpkg-reconfigure openssh-server
exit 0
EOL

# Make sure the script is executable
sudo chmod +x /etc/rc.local

# Reset Hostname
# Prevent cloudconfig from preserving original hostname
sudo sed -i 's/preserve_hostname: false/preserve_hostname: true/g' /etc/cloud/cloud.cfg
sudo truncate -s0 /etc/hostname
sudo hostnamectl set-hostname localhost

# disable swap
sudo swapoff --all
sudo sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab

# make machine-id unique and symlink it - ubuntu uses machine id in the dhcp identifier and not mac addresses
sudo truncate -s 0 /etc/machine-id
sudo rm /var/lib/dbus/machine-id
sudo ln -s /etc/machine-id /var/lib/dbus/machine-id

# cleans out all of the cloud-init cache / logs - this is mainly cleaning out networking info
sudo cloud-init clean --logs

# remove netplan file
sudo rm /etc/netplan/*.yaml

# cleanup current ssh keys
sudo rm -f /etc/ssh/ssh_host_*

# cleanup shell history
cat /dev/null > ~/.bash_history && history -c
