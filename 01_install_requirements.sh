#!/usr/bin/env bash
set -ex

source logging.sh

# FIXME ocp-doit required this so leave permissive for now
sudo setenforce permissive
sudo sed -i "s/=enforcing/=permissive/g" /etc/selinux/config

# Update to latest packages first
sudo yum -y update

# Install EPEL required by some packages
if [ ! -f /etc/yum.repos.d/epel.repo ] ; then
    if grep -q "Red Hat Enterprise Linux" /etc/redhat-release ; then
        sudo yum -y install http://mirror.centos.org/centos/7/extras/x86_64/Packages/epel-release-7-11.noarch.rpm
    else
        sudo yum -y install epel-release --enablerepo=extras
    fi
fi

# Install qemu-img-ev on RHEL
if grep -q "Red Hat Enterprise Linux" /etc/redhat-release ; then
  sudo bash -c 'cat > /etc/yum.repos.d/sig-virt.repo' << -EOF
  [sig-virt-libvirt-latest]
  name=SIG-Virt libvirt packages for CentOS 7 x86_64
  baseurl=http://mirror.centos.org/centos-7/7/virt/x86_64/libvirt-latest
  enabled=1
  gpgcheck=0
  EOF

  # Enable the latest QEMU packages
  sudo bash -c 'cat > /etc/yum.repos.d/sig-virt-kvm-common.repo' << -EOF
  [sig-virt-kvm-common]
  name=SIG-Virt libvirt packages for CentOS 7 x86_64
  baseurl=http://mirror.centos.org/centos-7/7/virt/x86_64/kvm-common
  enabled=1
  gpgcheck=0
  EOF
fi

# Work around a conflict with a newer zeromq from epel
if ! grep -q zeromq /etc/yum.repos.d/epel.repo; then
  sudo sed -i '/enabled=1/a exclude=zeromq*' /etc/yum.repos.d/epel.repo
fi

# Install required packages
# python-{requests,setuptools} required for tripleo-repos install
sudo yum -y install \
  crudini \
  curl \
  dnsmasq \
  figlet \
  golang \
  NetworkManager \
  nmap \
  patch \
  psmisc \
  python-pip \
  python-requests \
  python-setuptools \
  vim-enhanced \
  wget

# We're reusing some tripleo pieces for this setup so clone them here
cd
if [ ! -d tripleo-repos ]; then
  git clone https://git.openstack.org/openstack/tripleo-repos
fi
pushd tripleo-repos
sudo python setup.py install
popd

# Needed to get a recent python-virtualbmc package
sudo tripleo-repos current-tripleo

# There are some packages which are newer in the tripleo repos
sudo yum -y update

# Setup yarn and nodejs repositories
sudo curl -sL https://dl.yarnpkg.com/rpm/yarn.repo -o /etc/yum.repos.d/yarn.repo
curl -sL https://rpm.nodesource.com/setup_10.x | sudo bash -

# make sure additional requirments are installed
sudo yum -y install \
  ansible \
  bind-utils \
  jq \
  libguestfs-tools \
  libvirt \
  libvirt-devel \
  libvirt-daemon-kvm \
  nodejs \
  podman \
  python-ironicclient \
  python-ironic-inspector-client \
  python-lxml \
  python-netaddr \
  python-openstackclient \
  python-virtualbmc \
  qemu-kvm \
  virt-install \
  unzip \
  yarn

# Install python packages not included as rpms
sudo pip install \
  lolcat \
  yq

# Install oc client
oc_version=4.0.22
oc_tools_dir=$HOME/oc-${oc_version}
oc_tools_local_file=openshift-client-${oc_version}.tar.gz
if [ ! -f ${oc_tools_dir}/${oc_tools_local_file} ]; then
  mkdir -p ${oc_tools_dir}
  cd ${oc_tools_dir}
  wget https://mirror.openshift.com/pub/openshift-v3/clients/${oc_version}/linux/oc.tar.gz -O ${oc_tools_local_file}
  tar xvzf ${oc_tools_local_file}
  sudo cp oc /usr/local/bin/
fi

# Generate user ssh key
if [ ! -f $HOME/.ssh/id_rsa.pub ]; then
    ssh-keygen -f ~/.ssh/id_rsa -P ""
fi

# root needs a private key to talk to libvirt
# See tripleo-quickstart-config/roles/virtbmc/tasks/configure-vbmc.yml
if sudo [ ! -f /root/.ssh/id_rsa_virt_power ]; then
  sudo ssh-keygen -f /root/.ssh/id_rsa_virt_power -P ""
  sudo cat /root/.ssh/id_rsa_virt_power.pub | sudo tee -a /root/.ssh/authorized_keys
fi
