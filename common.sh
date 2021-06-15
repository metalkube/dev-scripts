#!/bin/bash

export PATH="/usr/local/go/bin:$HOME/.local/bin:$PATH"

# Set a PS4 value which logs the script name and line #.
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

eval "$(go env)"

export PATH="${GOPATH}/bin:$PATH"

# Ensure if a go program crashes we get a coredump
#
# To get the dump, use coredumpctl:
#   coredumpctl -o oc.coredump dump /usr/local/bin/oc
#
export GOTRACEBACK=crash

# Do not use pigz due to race condition in vendored docker code
# that oc uses.
# See: https://github.com/openshift/oc/issues/58,
#      https://github.com/moby/moby/issues/39859
export MOBY_DISABLE_PIGZ=true

SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
USER=`whoami`
GROUP=`id -gn`

function error () {
    echo $@ 1>&2
}

# Get variables from the config file
if [ -z "${CONFIG:-}" ]; then
    # See if there's a config_$USER.sh in the SCRIPTDIR
    if [ -f ${SCRIPTDIR}/config_${USER}.sh ]; then
        echo "Using CONFIG ${SCRIPTDIR}/config_${USER}.sh" 1>&2
        CONFIG="${SCRIPTDIR}/config_${USER}.sh"
    else
        error "Please run with a configuration environment set."
        error "eg CONFIG=config_example.sh ./01_all_in_one.sh"
        exit 1
    fi
fi
source $CONFIG

export CLUSTER_NAME=${CLUSTER_NAME:-ostest}

export PROVISIONING_NETWORK_PROFILE=${PROVISIONING_NETWORK_PROFILE:-"Managed"}

# Network interface names can only be 15 characters long, so
# abbreviate provisioning and baremetal and add them as suffixes to
# the cluster name.
export PROVISIONING_NETWORK_NAME=${PROVISIONING_NETWORK_NAME:-${CLUSTER_NAME}pr}
export BAREMETAL_NETWORK_NAME=${BAREMETAL_NETWORK_NAME:-${CLUSTER_NAME}bm}

export BASE_DOMAIN=${BASE_DOMAIN:-test.metalkube.org}
export CLUSTER_DOMAIN="${CLUSTER_NAME}.${BASE_DOMAIN}"
export SSH_PUB_KEY="${SSH_PUB_KEY:-$(cat $HOME/.ssh/id_rsa.pub)}"

# mirror images for installation in restricted network
export MIRROR_IMAGES=${MIRROR_IMAGES:-}

# Hypervisor details
export REMOTE_LIBVIRT=${REMOTE_LIBVIRT:-0}
export PROVISIONING_HOST_USER=${PROVISIONING_HOST_USER:-$USER}

# The dev-scripts working directory
export WORKING_DIR=${WORKING_DIR:-"/opt/dev-scripts"}
OCP_DIR=${OCP_DIR:-ocp/${CLUSTER_NAME}}

# The DNS name for the registry that this cluster should use.
export LOCAL_REGISTRY_DNS_NAME=${LOCAL_REGISTRY_DNS_NAME:-"virthost.${CLUSTER_NAME}.${BASE_DOMAIN}"}
# All DNS names for the registry, to be included in the certificate.
export ALL_REGISTRY_DNS_NAMES=${ALL_REGISTRY_DNS_NAMES:-${LOCAL_REGISTRY_DNS_NAME}}

# variables for local registry configuration
export LOCAL_REGISTRY_PORT=${LOCAL_REGISTRY_PORT:-"5000"}
export REGISTRY_USER=${REGISTRY_USER:-ocp-user}
export REGISTRY_PASS=${REGISTRY_PASS:-ocp-pass}
export REGISTRY_DIR=${REGISTRY_DIR:-$WORKING_DIR/registry}
export REGISTRY_CREDS=${REGISTRY_CREDS:-$HOME/private-mirror-${CLUSTER_NAME}.json}
export REGISTRY_CRT=registry.2.crt

# Set this variable to build the installer from source
export KNI_INSTALL_FROM_GIT=${KNI_INSTALL_FROM_GIT:-}

export OPENSHIFT_CLIENT_TOOLS_URL=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz

export OPENSHIFT_RELEASE_TYPE=${OPENSHIFT_RELEASE_TYPE:-nightly}
export OPENSHIFT_RELEASE_STREAM=${OPENSHIFT_RELEASE_STREAM:-4.9}
if [[ "$OPENSHIFT_RELEASE_TYPE" == "ga" ]]; then
    if [[ -z "$OPENSHIFT_VERSION" ]]; then
      error "OPENSHIFT_VERSION is required with OPENSHIFT_RELEASE_TYPE=ga"
      exit 1
    fi
    export OPENSHIFT_RELEASE_STREAM=${OPENSHIFT_VERSION%.*}
fi

# DNS resolution for amd64.ocp.releases.ci.openshift.org fails
# pretty regularly, so try a few times before giving up.
function get_latest_ci_image() {
    for i in {1..3}; do
        if curl -L https://amd64.ocp.releases.ci.openshift.org/api/v1/releasestream/${OPENSHIFT_RELEASE_STREAM}.0-0.${OPENSHIFT_RELEASE_TYPE}/latest | grep -o 'registry.ci.openshift.org[^"]\+'; then
            return
        fi
        echo "Failed to get CI image" 1>&2
        sleep 2
    done
}

#
# See https://amd64.ocp.releases.ci.openshift.org for release details
#
# if we provide OPENSHIFT_RELEASE_IMAGE, do not curl. This is needed for offline installs
if [ -z "${OPENSHIFT_RELEASE_IMAGE:-}" ]; then
  if [[ "$OPENSHIFT_RELEASE_TYPE" == "ga" ]]; then
    LATEST_CI_IMAGE=$(curl -L https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OPENSHIFT_VERSION}/release.txt  | grep -o 'quay.io/openshift-release-dev/ocp-release[^"]\+')
  else
    LATEST_CI_IMAGE=$(get_latest_ci_image)
    if [ -z "$LATEST_CI_IMAGE" ]; then
      error "No release image found."
      exit 1
    fi
  fi
fi
export OPENSHIFT_RELEASE_IMAGE="${OPENSHIFT_RELEASE_IMAGE:-$LATEST_CI_IMAGE}"
export OPENSHIFT_INSTALL_PATH="$GOPATH/src/github.com/openshift/installer"

# Override the image to use for installing hive
export HIVE_DEPLOY_IMAGE="${HIVE_DEPLOY_IMAGE:-registry.ci.openshift.org/openshift/hive-v4.0:hive}"

# CI images don't have version numbers
export OPENSHIFT_CI=${OPENSHIFT_CI:-""}
export OPENSHIFT_VERSION=${OPENSHIFT_VERSION:-""}
if [[ -z "$OPENSHIFT_CI" ]]; then
  export OPENSHIFT_VERSION=${OPENSHIFT_VERSION:-$(echo $OPENSHIFT_RELEASE_IMAGE | sed "s/.*:\([[:digit:]]\.[[:digit:]]\).*/\1/")}
fi

export OPENSHIFT_RELEASE_TAG=$(echo $OPENSHIFT_RELEASE_IMAGE | sed -E 's/[[:alnum:]\/.-]*release.*://')

# Use "ipmi" for 4.3 as it didn't support redfish, for other versions
# use "redfish", unless its CI where we use "mixed"
if [[ "$OPENSHIFT_VERSION" == "4.3" ]]; then
  export BMC_DRIVER=${BMC_DRIVER:-ipmi}
elif [[ -z "$OPENSHIFT_CI" ]]; then
  export BMC_DRIVER=${BMC_DRIVER:-redfish}
else
  export BMC_DRIVER=${BMC_DRIVER:-mixed}
fi

if [[ "$PROVISIONING_NETWORK_PROFILE" == "Disabled" ]]; then
  export BMC_DRIVER="redfish-virtualmedia"
fi

# Both utils.sh and 04_setup_ironic.sh use this log file, so set the
# name one time. Users should not override this.
export MIRROR_LOG_FILE=${REGISTRY_DIR}/${CLUSTER_NAME}-image_mirror-${OPENSHIFT_RELEASE_TAG}.log

# Switch Container Images to upstream, Installer defaults these to the openshift version
if [ "${UPSTREAM_IRONIC:-false}" != "false" ] ; then
    export IRONIC_LOCAL_IMAGE=${IRONIC_LOCAL_IMAGE:-"quay.io/metal3-io/ironic:master"}
# Starting from Openshift 4.9 the ironic-inspector container is not used anymore
    if [ "$OPENSHIFT_VERSION" <= "4.8" ]; then
        export IRONIC_INSPECTOR_LOCAL_IMAGE=${IRONIC_INSPECTOR_LOCAL_IMAGE:-"quay.io/metal3-io/ironic-inspector:master"}
    fi
    export IRONIC_IPA_DOWNLOADER_LOCAL_IMAGE=${IRONIC_IPA_DOWNLOADER_LOCAL_IMAGE:-"quay.io/metal3-io/ironic-ipa-downloader:master"}
    export IRONIC_STATIC_IP_MANAGER_LOCAL_IMAGE=${IRONIC_STATIC_IP_MANAGER_LOCAL_IMAGE:-"quay.io/metal3-io/static-ip-manager"}
    export BAREMETAL_OPERATOR_LOCAL_IMAGE=${BAREMETAL_OPERATOR_LOCAL_IMAGE:-"quay.io/metal3-io/baremetal-operator"}
fi

if [ -z "$KNI_INSTALL_FROM_GIT" ]; then
    export OPENSHIFT_INSTALLER=${OPENSHIFT_INSTALLER:-${OCP_DIR}/openshift-baremetal-install}
 else
    export OPENSHIFT_INSTALLER=${OPENSHIFT_INSTALLER:-$OPENSHIFT_INSTALL_PATH/bin/openshift-install}

    # This is an URI so we can use curl for either the file on GitHub, or locally
    export OPENSHIFT_INSTALLER_MACHINE_OS=${OPENSHIFT_INSTALLER_MACHINE_OS:-file:///$OPENSHIFT_INSTALL_PATH/data/data/rhcos.json}

    # The installer defaults to origin releases when building from source
    export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="${OPENSHIFT_RELEASE_IMAGE}"
fi

if env | grep -q "_LOCAL_IMAGE=" ; then
    export MIRROR_IMAGES=true
fi

if [ -n "$MIRROR_IMAGES" ]; then
    # We're going to be using a locally modified release image
    export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE="${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/local-release-image:latest"
fi

# Set variables
# Additional DNS
ADDN_DNS=${ADDN_DNS:-}
# External interface for routing traffic through the host
EXT_IF=${EXT_IF:-}
# Provisioning interface
PRO_IF=${PRO_IF:-}
# Does libvirt manage the baremetal bridge (including DNS and DHCP)
MANAGE_BR_BRIDGE=${MANAGE_BR_BRIDGE:-y}
# Only manage bridges if is set
MANAGE_PRO_BRIDGE=${MANAGE_PRO_BRIDGE:-y}
MANAGE_INT_BRIDGE=${MANAGE_INT_BRIDGE:-y}
# Internal interface, to bridge virbr0
INT_IF=${INT_IF:-}
#Root disk to deploy coreOS - use /dev/sda on BM
ROOT_DISK_NAME=${ROOT_DISK_NAME-"/dev/sda"}

FILESYSTEM=${FILESYSTEM:="/"}

export NODES_FILE=${NODES_FILE:-"${WORKING_DIR}/${CLUSTER_NAME}/ironic_nodes.json"}
export EXTRA_NODES_FILE=${EXTRA_NODES_FILE:-"${WORKING_DIR}/${CLUSTER_NAME}/extra_ironic_nodes.json"}
NODES_PLATFORM=${NODES_PLATFORM:-"libvirt"}
BAREMETALHOSTS_FILE=${BAREMETALHOSTS_FILE:-"${OCP_DIR}/baremetalhosts.json"}
EXTRA_BAREMETALHOSTS_FILE=${EXTRA_BAREMETALHOSTS_FILE:-"${OCP_DIR}/extra_baremetalhosts.json"}
export BMO_WATCH_ALL_NAMESPACES=${BMO_WATCH_ALL_NAMESPACES:-"false"}

# Optionally set this to a path to use a local dev copy of
# metal3-dev-env, otherwise it's cloned to $WORKING_DIR
export METAL3_DEV_ENV=${METAL3_DEV_ENV:-}
if [ -z "${METAL3_DEV_ENV}" ]; then
  export METAL3_DEV_ENV_PATH="${WORKING_DIR}/metal3-dev-env"
else
  export METAL3_DEV_ENV_PATH="${METAL3_DEV_ENV}"
fi
export VM_SETUP_PATH="${METAL3_DEV_ENV_PATH}/vm-setup"
export CONTAINER_RUNTIME="podman"

export NUM_MASTERS=${NUM_MASTERS:-"3"}
export NUM_WORKERS=${NUM_WORKERS:-"2"}
export NUM_EXTRA_WORKERS=${NUM_EXTRA_WORKERS:-"0"}
export EXTRA_WORKERS_ONLINE_STATUS=${EXTRA_WORKERS_ONLINE_STATUS:-"true"}
export VM_EXTRADISKS=${VM_EXTRADISKS:-"false"}
export VM_EXTRADISKS_LIST=${VM_EXTRADISKS_LIST:-"vdb"}
export VM_EXTRADISKS_SIZE=${VM_EXTRADISKS_SIZE:-"8G"}
export MASTER_HOSTNAME_FORMAT=${MASTER_HOSTNAME_FORMAT:-"master-%d"}
export WORKER_HOSTNAME_FORMAT=${WORKER_HOSTNAME_FORMAT:-"worker-%d"}

export MASTER_MEMORY=${MASTER_MEMORY:-16384}
export MASTER_DISK=${MASTER_DISK:-30}
export MASTER_VCPU=${MASTER_VCPU:-8}

export WORKER_MEMORY=${WORKER_MEMORY:-8192}
export WORKER_DISK=${WORKER_DISK:-30}
export WORKER_VCPU=${WORKER_VCPU:-4}

export EXTRA_WORKER_MEMORY=${EXTRA_WORKER_MEMORY:-${WORKER_MEMORY}}
export EXTRA_WORKER_DISK=${EXTRA_WORKER_DISK:-${WORKER_DISK}}
export EXTRA_WORKER_VCPU=${EXTRA_WORKER_VCPU:-${WORKER_VCPU}}

# Ironic vars (Image can be use <NAME>_LOCAL_IMAGE to override)
export IRONIC_IMAGE="quay.io/metal3-io/ironic:master"
export IRONIC_DATA_DIR="${WORKING_DIR}/ironic"
export IRONIC_IMAGES_DIR="${IRONIC_DATA_DIR}/html/images"

# VBMC and Redfish images
export VBMC_IMAGE=${VBMC_IMAGE:-"quay.io/metal3-io/vbmc"}
export SUSHY_TOOLS_IMAGE=${SUSHY_TOOLS_IMAGE:-"quay.io/metal3-io/sushy-tools"}
export VBMC_BASE_PORT=${VBMC_BASE_PORT:-"6230"}
export VBMC_MAX_PORT=$((VBMC_BASE_PORT + NUM_MASTERS + NUM_WORKERS + NUM_EXTRA_WORKERS - 1))
export REDFISH_EMULATOR_IGNORE_BOOT_DEVICE="${REDFISH_EMULATOR_IGNORE_BOOT_DEVICE:-False}"

# Which docker registry image should we use?
export DOCKER_REGISTRY_IMAGE=${DOCKER_REGISTRY_IMAGE:-"quay.io/libpod/registry:2"}

export KUBECONFIG="${SCRIPTDIR}/ocp/$CLUSTER_NAME/auth/kubeconfig"

# Use a cloudy ssh that doesn't do Host Key checking
export SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"

# Verify requisites/permissions
# Connect to system libvirt
export LIBVIRT_DEFAULT_URI=qemu:///system

export PULL_SECRET_FILE=${PULL_SECRET_FILE:-$WORKING_DIR/pull_secret.json}

# Ensure a few variables are set, even if empty, to avoid undefined
# variable errors in the next 2 checks.
set +x
export CI_TOKEN=${CI_TOKEN:-}
set -x
export PERSONAL_PULL_SECRET=${PERSONAL_PULL_SECRET:-$SCRIPTDIR/pull_secret.json}

# Ensure working dir is always different than script dir. If not, some
# files may get overriden during deployment process.
if [ "$(realpath ${WORKING_DIR})" == "$(realpath ${SCRIPTDIR})" ]; then
  error "WORKING_DIR must not be the same as SCRIPTDIR, i.e. $(realpath ${WORKING_DIR})"
  error "is used for both. Please change one of them to another directory."
  error "WORKING_DIR will be created automatically if it does not exist."
  exit 1
fi

if [ ! -d "$WORKING_DIR" ]; then
  error "Creating Working Dir"
  sudo mkdir -p "$WORKING_DIR"
  sudo chown "${USER}:${GROUP}" "$WORKING_DIR"
  chmod 755 "$WORKING_DIR"
fi

mkdir -p "$WORKING_DIR/$CLUSTER_NAME"

if [ ! -d "$IRONIC_IMAGES_DIR" ]; then
  error "Creating Ironic Images Dir"
  sudo mkdir -p "$IRONIC_IMAGES_DIR"
fi

# Previously the directory was owned by root, we need to alter
# permissions to be owned by the user running dev-scripts.
if [ ! -f "$IRONIC_IMAGES_DIR/.permissions" ]; then
  error "Resetting permissions on Ironic Images Dir..."
  sudo chown -R "${USER}:${GROUP}" "$IRONIC_DATA_DIR"
  sudo find "$IRONIC_DATA_DIR" -type d -print0 | xargs -0 chmod 755
  sudo chmod -R +r "$IRONIC_DATA_DIR"
  touch "$IRONIC_IMAGES_DIR/.permissions"
fi

# Defaults the variable to enable testing a custom machine-api-operator image
export TEST_CUSTOM_MAO=${TEST_CUSTOM_MAO:-false}
