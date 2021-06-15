#!/bin/bash

# You can get this token from https://console-openshift-console.apps.ci.l2s4.p1.openshiftapps.com/ by
# clicking on your name in the top right corner and coping the login
# command (the token is part of the command)
set +x
export CI_TOKEN=''
set -x

# Select a different release stream from which to pull the latest image, if the
# image name is not specified
#export OPENSHIFT_RELEASE_STREAM=4.8

# Select a different release type from which to pull the latest image,
# e.g ci, nightly or ga
# if using ga then set OPENSHIFT_VERSION to the required version.
#export OPENSHIFT_RELEASE_TYPE=nightly

# Use <NAME>_LOCAL_IMAGE to build or use copy of container images locally e.g.
#export IRONIC_LOCAL_IMAGE=https://github.com/metal3-io/ironic
#export IRONIC_LOCAL_IMAGE=quay.io/username/ironic
#export MACHINE_CONFIG_OPERATOR_LOCAL_IMAGE=https://github.com/openshift/machine-config-operator
# NOTE: If a checkout already exists in $HOME, it won't be re-created.
# NOTE: You must set CUSTOM_REPO_FILE to build some OpenShift images, e.g. ironic ones.
# NOTE: The use of IRONIC_INSPECTOR_LOCAL_IMAGE is limited to Openshift up to
# Version 4.8, starting from Openshift 4.9 the ironic-inspector container is not used anymore.

# Use <IMAGE_NAME>_EXTRA_PACKAGES to set the path (relative to dev-scripts or
# absolute) to a file with extra packages to install in the image, one per line.
# At the moment, this option is supported with ironic-image and
# ironic-inspector-image (NOTE: the ironic-inspector container has been
# removed in Openshift 4.9)
# For example:
# export IRONIC_EXTRA_PACKAGES=ironic-extra-pkgs.txt

# Set this variable to point the custom base image to a different location
# It can be an absolute path or a local path under the dev-scripts dir
# export BASE_IMAGE_DIR=base-image

# To build custom images based on custom base images with custom repositories
# put all the custom repositories in a .repo file inside the base-image directory
# (default to dev-scripts/base-image) and set this variable with the name of the
# .repo file, e.g. if the filename is ocp46.repo
# export CUSTOM_REPO_FILE=ocp46.repo

# We can also change the very image the base-image is built from using the BASE_IMAGE_FROM
# variable; when we choose this, the repos included in the base image won't be removed.
# export BASE_IMAGE_FROM=centos:8

# If needed, we can fetch the change associated to a Pull Request for the images
# we're building locally. Specifying the PR number will fetch the PR, switch the
# local image repo to it, and build the image locally with that specific change.
# For example, for the PR #34 for the ironic-image:
# export IRONIC_PR=34

# IP stack for the cluster.  The default is "v6".  You may also set "v4", or
# "v4v6" for dual stack.
#export IP_STACK=v4

# IP stack for the hosts. If unset, defaults to ${IP_STACK}, but you can set
# IP_STACK to "v4" or "v6" and HOST_IP_STACK to "v4v6" to install a single-stack
# cluster on dual-stack hosts.
#export HOST_IP_STACK=v4v6

# BMC type. Valid values are redfish, redfish-virtualmedia, or ipmi.
#export BMC_DRIVER=redfish-virtualmedia

# Mirror latest ci images to local registry. This is always true for IPv6, but can be turned off
# for an IPv4 install.
#export MIRROR_IMAGES=true

# Ensure that the local registry will be available
#export ENABLE_LOCAL_REGISTRY=true

# Switch to upstream metal3-io ironic images instead of openshift ones.
#export UPSTREAM_IRONIC=true

# SSH key used to ssh into deployed hosts.  This must be the contents of the
# variable, not the filename. The contents of ~/.ssh/id_rsa.pub are used by
# default.
#export SSH_PUB_KEY=$(cat ~/.ssh/id_rsa.pub)

# Configure custom ntp servers if needed
#export NTP_SERVERS="00.my.internal.ntp.server.com;01.other.ntp.server.com"

# Indicate number of workers to deploy
#export NUM_WORKERS=0

# Indicate number of extra VMs to create but not deploy
#export NUM_EXTRA_WORKERS=0

# Apply extra workers automatically if NUM_EXTRA_WORKERS is set
#export APPLY_EXTRA_WORKERS=true

# Indicate the online status of the NUM_EXTRA_WORKERS set in extra_host_manifests.yaml
#export EXTRA_WORKERS_ONLINE_STATUS=true

# Provisioning interface on the helper ndoe
#export PRO_IF="eno1"

# Internal interface
#export INT_IF="eno2"

# Provisioning interface within the cluster
#export CLUSTER_PRO_IF="eno1"

# Which disk to deploy
#export ROOT_DISK_NAME="/dev/sda"

# Cluster name
#export CLUSTER_NAME="mycluster"

# Domain name
#export BASE_DOMAIN="kni.lab.metal3.io"

# Manage bridge
#export MANAGE_BR_BRIDGE=n

# Path to the json files with ipmi credentials
#export NODES_FILE="/root/git/dev-scripts/bm.json"

# Whether the installation is on baremetal or not
#export NODES_PLATFORM=BM

# DNS_VIP
#export DNS_VIP="11.0.0.2"

# Network type
#export NETWORK_TYPE="OpenShiftSDN"

# Provisioning network
#export PROVISIONING_NETWORK="172.23.0.0/16"

# IPv6 Provisioning network
#export PROVISIONING_NETWORK=fd00:1101::0/64

# Provisioning network profile, can be set to "Managed" or "Disabled"
#export PROVISIONING_NETWORK_PROFILE=Managed

# Instruct the redfish emulator to ignore any instructions to set the boot device
#export REDFISH_EMULATOR_IGNORE_BOOT_DEVICE=False

# External subnet
#export EXTERNAL_SUBNET_V4="11.0.0.0/24"
#export EXTERNAL_SUBNET_V6="fd2e:6f44:5dd8:c956::/120"

# Cluster Subnet
#export CLUSTER_SUBNET_V4="10.128.0.0/14"
#export CLUSTER_HOST_PREFIX_V4="23"
#export CLUSTER_SUBNET_V6="fd01::/48
#export CLUSTER_HOST_PREFIX_V6="64"

# Cluster Host Prefix

# Service Subnet
#export SERVICE_SUBNET_V4="172.30.0.0/16"
#export SERVICE_SUBNET_V6="fd02::/112"

# Enable testing of custom machine-api-operator-image
#export TEST_CUSTOM_MAO=true

# Custom machine-api-operator image with tag
#export CUSTOM_MAO_IMAGE="quay.io/mao-user/machine-api-operator:mao-fix"

# Git repository that is holding any custom machine-api-operator changes
#export REPO_NAME="mao-user"

# Name of branch in the above repo which contains the custom MAO changes
#export MAO_BRANCH="mao-fix"

#export LOCAL_REGISTRY_DNS_NAME="virthost.ostest.test.metalkube.org"
#export LOCAL_REGISTRY_PORT="5000"

# configure username for registry
#export REGISTRY_USER=some-user

# congiugre password for registry user
#export REGISTRY_PASS=some-pass

# configure base directory for registry
#export REGISTRY_DIR=/opt/registry

# configure location of mirror's creds
#export REGISTRY_CREDS=${REGISTRY_CREDS:-$USER/private-mirror.json}

# Install operator-sdk for local testing of baremetal-operator
#export INSTALL_OPERATOR_SDK=1

# Set a custom hostname format for masters. This is a format string that should
# include one %d field, which will be replaced with the number of the node.
#export MASTER_HOSTNAME_FORMAT=master-%d

# Set a custom hostname format for workers. This is a format string that should
# include one %d field, which will be replaced with the number of the node.
#export WORKER_HOSTNAME_FORMAT=worker-%d

# Change VM resources for masters
#export MASTER_MEMORY=16384
#export MASTER_DISK=20
#export MASTER_VCPU=8

# Change VM resources for workers
#export WORKER_MEMORY=8192
#export WORKER_DISK=20
#export WORKER_VCPU=4

# Change VM resources for extra workers. If not supplied defaults to the
# regular workers specs
#export EXTRA_WORKER_MEMORY=8192
#export EXTRA_WORKER_DISK=20
#export EXTRA_WORKER_VCPU=4

# Add extradisks to VMs
# export VM_EXTRADISKS=true

# Configure how many extra disks to add to VMs. Takes a string of disk
# names delimited by spaces. Example "vdb vdc"
# export VM_EXTRADISKS_LIST="vdb vdc"

# Configure size of extra disks added to VMs
# export VM_EXTRADISKS_SIZE="10G"

# Provide additional master/worker ignition configuration, will be
# merged with the installer provided config, can be used to modify
# the default nic configuration etc
#export IGNITION_EXTRA=extra.ign

# Folder where to copy extra manifests for the cluster deployment
#export ASSETS_EXTRA_FOLDER=local_file_path

# Enable FIPS mode
#export FIPS_MODE=true

# In order to test using unicast for keepalived, one needs to disable multicast.
# Setting this variable to true will block multicast via ebtables for both IPv4 and IPv6.
#export DISABLE_MULTICAST=false

# Enable metallb ("l2" or "bgp" )
#export ENABLE_METALLB_MODE="l2"
# metallb container location (optional)
#export METALLB_IMAGE_BASE=
#export METALLB_IMAGE_TAG=

##
## Multi-cluster/Hive variables
##

# Image reference for installing hive. See hive_install.sh.
#export HIVE_DEPLOY_IMAGE="registry.ci.openshift.org/openshift/hive-v4.0:hive"

# PEM-encoded X.509 certificate bundle that will be added to the nodes' trusted
# certificate store. This trust bundle may also be used when a proxy has
# been configured.
# export ADDITIONAL_TRUST_BUNDLE=/path/to/ca_file

##
## Assisted Deployment
##

# The following variables will allow for setting a custom image to use for each
# of the components deployed by the Assisted Operator

# export ASSISTED_SERVICE_IMAGE="quay.io/ocpmetal/assisted-service:latest"
# export ASSISTED_INSTALLER_IMAGE="quay.io/ocpmetal/assisted-installer:latest"
# export ASSISTED_AGENT_IMAGE="quay.io/ocpmetal/assisted-installer-agent:latest"
# export ASSISTED_DATABASE_IMAGE="quay.io/ocpmetal/postgresql-12-centos7:latest"
# export ASSISTED_CONTROLLER_IMAGE="quay.io/ocpmetal/assisted-installer-controller:latest"

# Get the latest default versions from the assisted-service repo itself.
# export ASSISTED_OPENSHIFT_VERSIONS=$(wget -qO- https://raw.githubusercontent.com/openshift/assisted-service/master/default_ocp_versions.json)

# Operator's bundle index to use. This will allow for testing a custom Assisted operator build that has
# not been published yet. For custom Assisted Service images it's enough to overwrite one of the images above.
# Overwrite this image only if you are working on the operator itself.
# export ASSISTED_OPERATOR_INDEX="quay.io/ocpmetal/assisted-service-index:latest"

# The namespace to use for Assisted Service. Note that the assisted service also deploys Hive
# and the Local Storage oeprator. Hive's subscription will be deployed on the `openshift-operators`
# namespace and the Local Storage in the `openshift-local-storage` one.
# export ASSISTED_NAMESPACE="assisted-installer"

# Uncomment the following line to have BareMetal Operator
# watch the BareMetalHosts on all namespaces. Note that
# setting this variable to true will require more RAM
# More info here: https://github.com/openshift-metal3/dev-scripts/pull/1241#issuecomment-846067822
# export BMO_WATCH_ALL_NAMESPACES="true"
