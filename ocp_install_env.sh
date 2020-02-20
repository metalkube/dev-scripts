eval "$(go env)"

function extract_command() {
    local release_image
    local cmd
    local outdir
    local extract_dir

    cmd="$1"
    release_image="$2"
    outdir="$3"

    extract_dir=$(mktemp -d "installer--XXXXXXXXXX")
    pullsecret_file=$(mktemp "pullsecret--XXXXXXXXXX")

    echo "${PULL_SECRET}" > "${pullsecret_file}"
    oc adm release extract --registry-config "${pullsecret_file}" --command=$cmd --to "${extract_dir}" ${release_image}

    mv "${extract_dir}/${cmd}" "${outdir}"
    rm -rf "${extract_dir}"
    rm -rf "${pullsecret_file}"
}

# Let's always grab the `oc` from the release we're using.
function extract_oc() {
    extract_dir=$(mktemp -d "installer--XXXXXXXXXX")
    extract_command oc "$1" "${extract_dir}"
    sudo mv "${extract_dir}/oc" /usr/local/bin
    rm -rf "${extract_dir}"
}

function extract_installer() {
    local release_image
    local outdir

    release_image="$1"
    outdir="$2"

    extract_command openshift-baremetal-install "$1" "$2"
}

function clone_installer() {
  # Clone repo, if not already present
  if [[ ! -d $OPENSHIFT_INSTALL_PATH ]]; then
    sync_repo_and_patch go/src/github.com/openshift/installer https://github.com/openshift/installer.git
  fi
}

function build_installer() {
  # Build installer
  pushd .
  cd $OPENSHIFT_INSTALL_PATH
  TAGS="libvirt baremetal" hack/build.sh
  popd
}

# FIXME(stbenjam): This is not available in 4.3 (yet)
function network_configuration() {
  if [[ "$OPENSHIFT_VERSION" != "4.3" ]]; then
cat <<EOF
    provisioningNetworkCIDR: $PROVISIONING_NETWORK
    provisioningNetworkInterface: $CLUSTER_PRO_IF
EOF
  fi
}

function generate_ocp_install_config() {
    local outdir

    outdir="$1"

    # when using local mirror set pull secret to this mirror
    # also this should ensure we don't accidentally pull from upstream
    if [ ! -z "${MIRROR_IMAGES}" ]; then
        export PULL_SECRET=$(cat ${REGISTRY_CREDS})
    fi

    mkdir -p "${outdir}"

    # IPv6 network config validation
    if [[ "${EXTERNAL_SUBNET}" =~ .*:.* ]]; then
      if [[ "${NETWORK_TYPE}" != "OVNKubernetes" ]]; then
        echo "NETWORK_TYPE must be OVNKubernetes when using IPv6"
        exit 1
      fi
    fi
    cat > "${outdir}/install-config.yaml" << EOF
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
networking:
  networkType: ${NETWORK_TYPE}
  machineCIDR: ${EXTERNAL_SUBNET}
  clusterNetwork:
  - cidr: ${CLUSTER_SUBNET}
    hostPrefix: ${CLUSTER_HOST_PREFIX}
  serviceNetwork:
  - ${SERVICE_SUBNET}
metadata:
  name: ${CLUSTER_NAME}
compute:
- name: worker
  replicas: $NUM_WORKERS
controlPlane:
  name: master
  replicas: ${NUM_MASTERS}
  platform:
    baremetal: {}
platform:
  baremetal:
$(network_configuration)
    bootstrapOSImage: http://${MIRROR_IP}/images/${MACHINE_OS_BOOTSTRAP_IMAGE_NAME}?sha256=${MACHINE_OS_BOOTSTRAP_IMAGE_UNCOMPRESSED_SHA256}
    clusterOSImage: http://${MIRROR_IP}/images/${MACHINE_OS_IMAGE_NAME}?sha256=${MACHINE_OS_IMAGE_SHA256}
    dnsVIP: ${DNS_VIP}
    hosts:
$(node_map_to_install_config_hosts $NUM_MASTERS 0 master)
$(node_map_to_install_config_hosts $NUM_WORKERS $NUM_MASTERS worker)
$(image_mirror_config)
pullSecret: |
  $(echo $PULL_SECRET | jq -c .)
sshKey: |
  ${SSH_PUB_KEY}
EOF
}
