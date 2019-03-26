#!/usr/bin/env bash
set -x

source common.sh

# Kill and remove the running ironic containers
for name in ironic ironic-inspector ; do 
    sudo podman ps | grep -w "$name$" && sudo podman kill $name
    sudo podman ps --all | grep -w "$name$" && sudo podman rm $name -f
done

# Remove existing pod
if  sudo podman pod exists ironic-pod ; then
    sudo podman pod rm ironic-pod -f
fi

ANSIBLE_FORCE_COLOR=true ansible-playbook \
    -e "working_dir=$WORKING_DIR" \
    -e "local_working_dir=$HOME/.quickstart" \
    -e "virthost=$HOSTNAME" \
    -e @tripleo-quickstart-config/metalkube-nodes.yml \
    -e @config/environments/dev_privileged_libvirt.yml \
    -i tripleo-quickstart-config/metalkube-inventory.ini \
    -b -vvv tripleo-quickstart-config/metalkube-teardown-playbook.yml

sudo rm -rf /etc/NetworkManager/dnsmasq.d/openshift.conf /etc/NetworkManager/conf.d/dnsmasq.conf
sudo rm -rf /etc/sysconfig/network-scripts/ifcfg-provisioning
if [ "$INT_IF" ]; then
  sudo rm -rf /etc/sysconfig/network-scripts/ifcfg-baremetal
  sudo cp /etc/sysconfig/network-scripts/ifcfg-$INT_IF.orig /etc/sysconfig/network-scripts/ifcfg-$INT_IF
  sudo systemctl restart network
fi
sudo virsh net-destroy baremetal
sudo virsh net-undefine baremetal
sudo virsh net-destroy provisioning
sudo virsh net-undefine provisioning
