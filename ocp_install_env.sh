eval "$(go env)"

function extract_command() {
    local release_image
    local cmd
    local outdir
    local extract_dir

    cmd="$1"
    release_image="$2"
    outdir="$3"

    extract_dir=$(mktemp --tmpdir -d "installer--XXXXXXXXXX")
    _tmpfiles="$_tmpfiles $extract_dir"

    oc adm release extract --registry-config "${PULL_SECRET_FILE}" --command=$cmd --to "${extract_dir}" ${release_image}

    mv "${extract_dir}/${cmd}" "${outdir}"
}

# Let's always grab the `oc` from the release we're using.
function extract_oc() {
    extract_dir=$(mktemp --tmpdir -d "installer--XXXXXXXXXX")
    _tmpfiles="$_tmpfiles $extract_dir"
    extract_command oc "$1" "${extract_dir}"
    sudo mv "${extract_dir}/oc" /usr/local/bin
}

function extract_installer() {
    local release_image
    local outdir

    release_image="$1"
    outdir="$2"

    extract_command openshift-baremetal-install "$1" "$2"
}

function save_release_info() {
    local release_image
    local outdir

    release_image="$1"
    outdir="$2"

    oc adm release info --registry-config "$PULL_SECRET_FILE" "$release_image" -o json > ${outdir}/release_info.json
}

# Gives e.g 4.7.0-0.nightly-2020-10-27-051128
function openshift_release_version() {
    jq -r ".metadata.version" ${OCP_DIR}/release_info.json
}

# Gives us e.g 4.7 because although OPENSHIFT_VERSION is set by users,
# but is not set in CI
function openshift_version() {
    jq -r ".metadata.version" ${OCP_DIR}/release_info.json | grep -oP "\d\.\d+"
}

function extract_rhcos_json() {
    local release_image
    local outdir

    release_image="$1"
    outdir="$2"

    baremetal_image=$(image_for baremetal-installer)
    baremetal_container=$(podman create --authfile "$PULL_SECRET_FILE" "$baremetal_image")

    # This is OK to fail as rhcos.json isn't available in every release,
    # we'll download it from github if it's not available
    podman cp "$baremetal_container":/var/cache/rhcos.json "$outdir" || true

    podman rm -f "$baremetal_container"
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
  cp "$OPENSHIFT_INSTALL_PATH/data/data/rhcos.json" "$OCP_DIR"
}

function baremetal_network_configuration() {
  if [[ "$(openshift_version $OCP_DIR)" == "4.3" ]]; then
    return
  fi

  if [[ "$PROVISIONING_NETWORK_PROFILE" == "Disabled" ]]; then
cat <<EOF
    provisioningNetwork: "${PROVISIONING_NETWORK_PROFILE}"
EOF
  if printf '%s\n4.6\n' "$(openshift_version)" | sort -V -C; then
cat <<EOF
    provisioningHostIP: "${CLUSTER_PROVISIONING_IP}"
    bootstrapProvisioningIP: "${BOOTSTRAP_PROVISIONING_IP}"
EOF
    fi
  else
cat <<EOF
    provisioningBridge: ${PROVISIONING_NETWORK_NAME}
    provisioningNetworkCIDR: $PROVISIONING_NETWORK
    provisioningNetworkInterface: $CLUSTER_PRO_IF
EOF
  fi
}

function dnsvip() {
  # dnsVIP was removed from 4.5
  if printf '%s\n4.4\n' "$(openshift_version)" | sort -V -C; then
cat <<EOF
    dnsVIP: ${DNS_VIP}
EOF
  fi
}

function libvirturi() {
    if [[ "$REMOTE_LIBVIRT" -ne 0 ]]; then
cat <<EOF
    libvirtURI: qemu+ssh://${PROVISIONING_HOST_USER}@$(wrap_if_ipv6 ${PROVISIONING_HOST_IP})/system
EOF
    fi
}

function additional_trust_bundle() {
  if [[ ! -z "$ADDITIONAL_TRUST_BUNDLE" ]]; then
    if [[ -z "${MIRROR_IMAGES}" && -z "${ENABLE_LOCAL_REGISTRY}" ]]; then
      echo "additionalTrustBundle: |"
    fi
    awk '{ print " ", $0 }' "${ADDITIONAL_TRUST_BUNDLE}"
  fi
}

function cluster_network() {
  if [[ "${IP_STACK}" == "v4" ]]; then
cat <<EOF
  machineNetwork:
  - cidr: ${EXTERNAL_SUBNET_V4}
  clusterNetwork:
  - cidr: ${CLUSTER_SUBNET_V4}
    hostPrefix: ${CLUSTER_HOST_PREFIX_V4}
  serviceNetwork:
  - ${SERVICE_SUBNET_V4}
EOF
  elif [[ "${IP_STACK}" == "v6" ]]; then
cat <<EOF
  machineNetwork:
  - cidr: ${EXTERNAL_SUBNET_V6}
  clusterNetwork:
  - cidr: ${CLUSTER_SUBNET_V6}
    hostPrefix: ${CLUSTER_HOST_PREFIX_V6}
  serviceNetwork:
  - ${SERVICE_SUBNET_V6}
EOF
  elif [[ "${IP_STACK}" == "v4v6" ]]; then
cat <<EOF
  machineNetwork:
  - cidr: ${EXTERNAL_SUBNET_V4}
  - cidr: ${EXTERNAL_SUBNET_V6}
  clusterNetwork:
  - cidr: ${CLUSTER_SUBNET_V4}
    hostPrefix: ${CLUSTER_HOST_PREFIX_V4}
  - cidr: ${CLUSTER_SUBNET_V6}
    hostPrefix: ${CLUSTER_HOST_PREFIX_V6}
  serviceNetwork:
  - ${SERVICE_SUBNET_V4}
  - ${SERVICE_SUBNET_V6}
EOF
  else
    echo "Unexpected IP_STACK value: '${IP_STACK}'"
    exit 1
  fi
}

function os_images() {
	# If using the live images, fetch the kernel, rootfs and initramfs images also
	if [ "${RHCOS_LIVE_IMAGES}"  == "true" ]; then
cat <<EOF
    bootstrapOSImage: http://$(wrap_if_ipv6 $MIRROR_IP)/images/${MACHINE_OS_BOOTSTRAP_IMAGE_NAME}?sha256=${MACHINE_OS_BOOTSTRAP_IMAGE_UNCOMPRESSED_SHA256}
    clusterOSImage: http://$(wrap_if_ipv6 $MIRROR_IP)/images/${MACHINE_OS_IMAGE_NAME}?sha256=${MACHINE_OS_IMAGE_SHA256},http://$(wrap_if_ipv6 $MIRROR_IP)/images/${MACHINE_OS_LIVE_KERNEL}?sha256=${MACHINE_OS_LIVE_KERNEL_SHA256},http://$(wrap_if_ipv6 $MIRROR_IP)/images/${MACHINE_OS_LIVE_ROOTFS}?sha256=${MACHINE_OS_LIVE_ROOTFS_SHA256},http://$(wrap_if_ipv6 $MIRROR_IP)/images/${MACHINE_OS_LIVE_INITRAMFS}?sha256=${MACHINE_OS_LIVE_INITRAMFS_SHA256}
EOF
	else
cat <<EOF
    bootstrapOSImage: http://$(wrap_if_ipv6 $MIRROR_IP)/images/${MACHINE_OS_BOOTSTRAP_IMAGE_NAME}?sha256=${MACHINE_OS_BOOTSTRAP_IMAGE_UNCOMPRESSED_SHA256}
    clusterOSImage: http://$(wrap_if_ipv6 $MIRROR_IP)/images/${MACHINE_OS_IMAGE_NAME}?sha256=${MACHINE_OS_IMAGE_SHA256}
EOF
	fi
}

function generate_ocp_install_config() {
    local outdir

    outdir="$1"

    # when using local mirror set pull secret to just this mirror to
    # ensure we don't accidentally pull from upstream
    if [ ! -z "${MIRROR_IMAGES}" ]; then
        install_config_pull_secret="${REGISTRY_CREDS}"
    else
        install_config_pull_secret="${PULL_SECRET_FILE}"
    fi

    mkdir -p "${outdir}"

    # IPv6 network config validation
    if [[ -n "${EXTERNAL_SUBNET_V6}" ]]; then
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
$(cluster_network)
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
$(libvirturi)
$(baremetal_network_configuration)
    externalBridge: ${BAREMETAL_NETWORK_NAME}
$(os_images)
    apiVIP: ${API_VIP}
    ingressVIP: ${INGRESS_VIP}
$(dnsvip)
    hosts:
$(node_map_to_install_config_hosts $NUM_MASTERS 0 master)
$(node_map_to_install_config_hosts $NUM_WORKERS $NUM_MASTERS worker)
$(image_mirror_config)
$(additional_trust_bundle)
pullSecret: |
  $(jq -c . $install_config_pull_secret)
sshKey: |
  ${SSH_PUB_KEY}
fips: ${FIPS_MODE:-false}
EOF

    cp "${outdir}/install-config.yaml" "${outdir}/install-config.yaml.save"
}

function generate_ocp_host_manifest() {
    local outdir

    outdir="$1"
    host_input="$2"
    host_output="$3"
    namespace="$4"

    mkdir -p "${outdir}"
    rm -f "${outdir}/extra_hosts.yaml"

    jq --raw-output '.[] | .name + " " + .ports[0].address + " " + .driver_info.username + " " + .driver_info.password + " " + .driver_info.address' $host_input \
       | while read name mac username password address ; do

        encoded_username=$(echo -n "$username" | base64)
        encoded_password=$(echo -n "$password" | base64)

    cat >> "${outdir}/${host_output}" << EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: ${name}-bmc-secret
  namespace: $namespace
type: Opaque
data:
  username: $encoded_username
  password: $encoded_password

---
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: $name
  namespace: $namespace
spec:
  online: ${EXTRA_WORKERS_ONLINE_STATUS}
  bootMACAddress: $mac
  bmc:
    address: $address
    credentialsName: ${name}-bmc-secret
EOF

    done
}
