#!/bin/bash

set -euxo pipefail

source logging.sh
source common.sh
source network.sh
source rhcos.sh
source ocp_install_env.sh
source utils.sh
source validation.sh

early_deploy_validation

# Account for differences in 1.* and 2.* version reporting.
PODMAN_VERSION=$(sudo podman version -f json | jq -r '.Version,.Client.Version|strings')

# To replace an image entry in the openshift releae image, set
# <ENTRYNAME>_LOCAL_IMAGE - where ENTRYNAME matches an uppercase version of the name in the release image
# with "-" converted to "_" e.g. to use a custom ironic image
#export IRONIC_LOCAL_IMAGE=https://github.com/metal3-io/ironic-image
#export IRONIC_MACHINE_OS_DOWNLOADER_LOCAL_IMAGE=https://github.com/openshift-metal3/ironic-rhcos-downloader
#export BAREMETAL_OPERATOR_LOCAL_IMAGE=192.168.111.1:5000/localimages/bmo:latest
# The use of IRONIC_INSPECTOR_LOCAL_IMAGE is limited to Openshift up to Version 4.8,
# starting from Openshift 4.9 the ironic-inspector container is not used anymore
rm -f assets/templates/99_local-registry.yaml $OPENSHIFT_INSTALL_PATH/data/data/bootstrap/baremetal/files/etc/containers/registries.conf

write_pull_secret

DOCKERFILE=$(mktemp --tmpdir "release-update--XXXXXXXXXX")
_tmpfiles="$_tmpfiles $DOCKERFILE"
echo "FROM $OPENSHIFT_RELEASE_IMAGE" > $DOCKERFILE

# To build custom images is highly recommended to build a base image first.
# Build a base image if we set a custom repo file in the config file and
# the file exists
if [[ -n ${CUSTOM_REPO_FILE:-} ]]; then
    ./build-base-image.sh ${BASE_IMAGE_DIR:-base-image} $CUSTOM_REPO_FILE
fi

for IMAGE_VAR in $(env | grep "_LOCAL_IMAGE=" | grep -o "^[^=]*") ; do
    IMAGE=${!IMAGE_VAR}
    BUILD_COMMAND_ARGS=""

    sudo -E podman pull --authfile $PULL_SECRET_FILE $OPENSHIFT_RELEASE_IMAGE

    # Is it a git repo?
    if [[ "$IMAGE" =~ "://" ]] ; then
        REPOPATH=~/${IMAGE##*/}
        # Clone to ~ if not there already
        [ -e "$REPOPATH" ] || git clone $IMAGE $REPOPATH
        cd $REPOPATH
        export $IMAGE_VAR=${IMAGE##*/}:latest
        export $IMAGE_VAR=$LOCAL_REGISTRY_DNS_NAME:$LOCAL_REGISTRY_PORT/localimages/${!IMAGE_VAR}
        # Some repos need to build with a non-default Dockerfile name
        IMAGE_DOCKERFILE_NAME=${IMAGE_VAR/_LOCAL_IMAGE}_DOCKERFILE
        IMAGE_DOCKERFILE=${!IMAGE_DOCKERFILE_NAME:-}
        if [[ -z "$IMAGE_DOCKERFILE" ]]; then
            for IMAGE_DOCKERFILE in Dockerfile.ocp Dockerfile; do
                if [[ -e "$IMAGE_DOCKERFILE" ]]; then
                    break
                fi
            done
        fi

        # If we set a specific PR number for the image, we can test it locally
        IMAGE_PR_VAR=${IMAGE_VAR/_LOCAL_IMAGE}_PR
        IMAGE_PR=${!IMAGE_PR_VAR:-}
        if [[ -n ${IMAGE_PR:-} ]]; then
                git fetch origin pull/${IMAGE_PR}/head:pr${IMAGE_PR}
                git checkout pr${IMAGE_PR}
        fi

        # If we want to install extra packages, we set the path to a
        # file containing the packages (one per line) we want to install
        EXTRA_PKGS_FILE_PATH=${IMAGE_VAR/_LOCAL_IMAGE}_EXTRA_PACKAGES
        EXTRA_PKGS_FILE=${!EXTRA_PKGS_FILE_PATH:-}
        if [[ -n $EXTRA_PKGS_FILE ]]; then
            EXTRA_PKGS_FILE=$(cd $OLDPWD; realpath $EXTRA_PKGS_FILE)
            cp $EXTRA_PKGS_FILE "$REPOPATH"
            EXTRA_PKGS_FILE_NAME=$(basename $EXTRA_PKGS_FILE)
            BUILD_COMMAND_ARGS+=" --build-arg EXTRA_PKGS_LIST=$EXTRA_PKGS_FILE_NAME"
        fi

        # If we built a custom base image, we should use it as a new base in
        # the Dockerfile to prevent discrepancies between locally built images.
        # Replace all FROM entries with the base-image.
        if [[ -n ${BASE_IMAGE_DIR:-} ]]; then
            sed -i "s/^FROM [^ ]*/FROM ${BASE_IMAGE_DIR}/g" ${IMAGE_DOCKERFILE}
        fi

        sudo podman build --authfile $PULL_SECRET_FILE $BUILD_COMMAND_ARGS -t ${!IMAGE_VAR} -f $IMAGE_DOCKERFILE .
        cd -
        sudo podman push --tls-verify=false --authfile $PULL_SECRET_FILE ${!IMAGE_VAR} ${!IMAGE_VAR}
    fi

    IMAGE_NAME=$(echo ${IMAGE_VAR/_LOCAL_IMAGE} | tr '[:upper:]_' '[:lower:]-')
    OLDIMAGE=$(sudo podman run --rm $OPENSHIFT_RELEASE_IMAGE image $IMAGE_NAME)
    echo "RUN sed -i 's%$OLDIMAGE%${!IMAGE_VAR}%g' /release-manifests/*" >> $DOCKERFILE
done

if [ ! -z "${MIRROR_IMAGES}" ]; then

    # combine global and local secrets
    # pull from one registry and push to local one
    # hence credentials are different

    EXTRACT_DIR=$(mktemp --tmpdir -d "mirror-installer--XXXXXXXXXX")
    _tmpfiles="$_tmpfiles $EXTRACT_DIR"

    oc adm release mirror \
       --insecure=true \
        -a ${PULL_SECRET_FILE}  \
        --from ${OPENSHIFT_RELEASE_IMAGE} \
        --to-release-image ${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/local-release-image:${OPENSHIFT_RELEASE_TAG} \
        --to ${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/local-release-image 2>&1 | tee ${MIRROR_LOG_FILE}
    echo "export MIRRORED_RELEASE_IMAGE=$OPENSHIFT_RELEASE_IMAGE" > /tmp/mirrored_release_image

    #To ensure that you use the correct images for the version of OpenShift Container Platform that you selected,
    #you must extract the installation program from the mirrored content:
    if [ -z "$KNI_INSTALL_FROM_GIT" ]; then
      oc adm release extract --registry-config "${PULL_SECRET_FILE}" \
        --command=openshift-baremetal-install --to "${EXTRACT_DIR}" \
        "${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/local-release-image:${OPENSHIFT_RELEASE_TAG}"

      mv -f "${EXTRACT_DIR}/openshift-baremetal-install" ${OCP_DIR}
    fi

    # Build a local release image, if no *_LOCAL_IMAGE env variables are set then this is just a copy of the release image
    sudo podman image build --authfile $PULL_SECRET_FILE -t $OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE -f $DOCKERFILE
    sudo podman push --tls-verify=false --authfile $PULL_SECRET_FILE $OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE $OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE

    IRONIC_RELEASE_IMAGE=$(image_for ironic | cut -d '@' -f2)
    LOCAL_REGISTRY_PREFIX="${LOCAL_REGISTRY_DNS_NAME}:${LOCAL_REGISTRY_PORT}/localimages/local-release-image"
    IRONIC_LOCAL_IMAGE=${IRONIC_LOCAL_IMAGE:-"${LOCAL_REGISTRY_PREFIX}@${IRONIC_RELEASE_IMAGE}"}
fi

for name in ironic ironic-api ironic-conductor ironic-inspector dnsmasq httpd-${PROVISIONING_NETWORK_NAME} mariadb ipa-downloader; do
    sudo podman ps | grep -w "$name$" && sudo podman kill $name
    sudo podman ps --all | grep -w "$name$" && sudo podman rm $name -f
done

# Remove existing pod
if  sudo podman pod exists ironic-pod ; then
    sudo podman pod rm ironic-pod -f
fi

# Create pod
sudo podman pod create -n ironic-pod

IRONIC_IMAGE=${IRONIC_LOCAL_IMAGE:-$IRONIC_IMAGE}

for IMAGE in ${IRONIC_IMAGE} ${VBMC_IMAGE} ${SUSHY_TOOLS_IMAGE} ; do
    sudo -E podman pull --authfile $PULL_SECRET_FILE $IMAGE || echo "WARNING: Could not pull latest $IMAGE; will try to use cached images instead"
done

CACHED_MACHINE_OS_IMAGE="${IRONIC_DATA_DIR}/html/images/${MACHINE_OS_IMAGE_NAME}"
if [ ! -f "${CACHED_MACHINE_OS_IMAGE}" ]; then
  curl -g --insecure -L -o "${CACHED_MACHINE_OS_IMAGE}" "${MACHINE_OS_IMAGE_URL}"
  echo "${MACHINE_OS_IMAGE_SHA256} $(basename ${CACHED_MACHINE_OS_IMAGE})" | tee ${CACHED_MACHINE_OS_IMAGE}.sha256sum
  pushd $(dirname ${CACHED_MACHINE_OS_IMAGE})
  sha256sum --strict --check ${CACHED_MACHINE_OS_IMAGE}.sha256sum || ( rm -f "${CACHED_MACHINE_OS_IMAGE}" ; exit 1 )
  popd
fi

CACHED_MACHINE_OS_BOOTSTRAP_IMAGE="${IRONIC_DATA_DIR}/html/images/${MACHINE_OS_BOOTSTRAP_IMAGE_NAME}"
if [ ! -f "${CACHED_MACHINE_OS_BOOTSTRAP_IMAGE}" ]; then
  curl -g --insecure -L -o "${CACHED_MACHINE_OS_BOOTSTRAP_IMAGE}" "${MACHINE_OS_BOOTSTRAP_IMAGE_URL}"
  pushd $(dirname ${CACHED_MACHINE_OS_BOOTSTRAP_IMAGE})
  echo "${MACHINE_OS_BOOTSTRAP_IMAGE_SHA256} $(basename ${CACHED_MACHINE_OS_BOOTSTRAP_IMAGE})" | tee ${CACHED_MACHINE_OS_BOOTSTRAP_IMAGE}.sha256sum
  sha256sum --strict --check ${CACHED_MACHINE_OS_BOOTSTRAP_IMAGE}.sha256sum || ( rm -f "${CACHED_MACHINE_OS_BOOTSTRAP_IMAGE}" ; exit 1 )
  popd
fi

# cached images to the bootstrap VM
sudo podman run -d --net host --privileged --name httpd-${PROVISIONING_NETWORK_NAME} --pod ironic-pod \
     --env PROVISIONING_INTERFACE=${PROVISIONING_NETWORK_NAME} \
     -v $IRONIC_DATA_DIR:/shared --entrypoint /bin/runhttpd ${IRONIC_IMAGE}

# IPA Downloader - for testing
if [ -n "${IRONIC_IPA_DOWNLOADER_LOCAL_IMAGE:-}" ];
then
  sudo -E podman pull --authfile $PULL_SECRET_FILE $IRONIC_IPA_DOWNLOADER_LOCAL_IMAGE

  sudo podman run -d --net host --privileged --name ipa-downloader --pod ironic-pod \
     -v $IRONIC_DATA_DIR:/shared ${IRONIC_IPA_DOWNLOADER_LOCAL_IMAGE} /usr/local/bin/get-resource.sh

  # Units have been introduced in 2.x
  if printf '2.0.0\n%s\n' "$PODMAN_VERSION" | sort -V -C; then
      sudo podman wait -i 1000ms ipa-downloader
  else
      sudo podman wait -i 1000 ipa-downloader
  fi
fi

function is_running() {
    local podname="$1"
    local ids

    ids=$(sudo podman ps -a --filter "name=${podname}" --filter status=running -q)
    if [[ -z "$ids" ]]; then
        return 1
    fi
    return 0
}

if [ "$NODES_PLATFORM" = "libvirt" ]; then
    if ! is_running vbmc; then
        # Force remove the pid file before restarting because podman
        # has told us the process isn't there but sometimes when it
        # dies it leaves the file.
        sudo rm -f $WORKING_DIR/virtualbmc/vbmc/master.pid
        sudo podman run -d --net host --privileged --name vbmc --pod ironic-pod \
             -v "$WORKING_DIR/virtualbmc/vbmc":/root/.vbmc -v "/root/.ssh":/root/ssh \
             "${VBMC_IMAGE}"
    fi

    if ! is_running sushy-tools; then
        sudo podman run -d --net host --privileged --name sushy-tools --pod ironic-pod \
             -v "$WORKING_DIR/virtualbmc/sushy-tools":/root/sushy -v "/root/.ssh":/root/ssh \
             "${SUSHY_TOOLS_IMAGE}"
    fi
fi



# Wait for images to be downloaded/ready
while ! curl --fail -g http://$(wrap_if_ipv6 ${PROVISIONING_HOST_IP})/images/${MACHINE_OS_IMAGE_NAME}.sha256sum ; do sleep 1 ; done
while ! curl --fail -g http://$(wrap_if_ipv6 ${PROVISIONING_HOST_IP})/images/${MACHINE_OS_BOOTSTRAP_IMAGE_NAME}.sha256sum ; do sleep 1 ; done

if [ -n "${IRONIC_IPA_DOWNLOADER_LOCAL_IMAGE:-}" ];
then
  while ! curl --fail --head -g http://$(wrap_if_ipv6 ${PROVISIONING_HOST_IP})/images/ironic-python-agent.initramfs ; do sleep 1; done
  while ! curl --fail --head -g http://$(wrap_if_ipv6 ${PROVISIONING_HOST_IP})/images/ironic-python-agent.kernel ; do sleep 1; done
fi
