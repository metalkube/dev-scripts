#!/bin/bash

set -ex

source logging.sh
source common.sh

# Either pull or build the ironic images
# To build the IRONIC image set
# IRONIC_IMAGE=https://github.com/metalkube/metalkube-ironic
for IMAGE_VAR in IRONIC_IMAGE IRONIC_INSPECTOR_IMAGE IPA_DOWNLOADER_IMAGE COREOS_DOWNLOADER_IMAGE ; do
    IMAGE=${!IMAGE_VAR}
    # Is it a git repo?
    if [[ "$IMAGE" =~ "://" ]] ; then
        REPOPATH=~/${IMAGE##*/}
        # Clone to ~ if not there already
        [ -e "$REPOPATH" ] || git clone $IMAGE $REPOPATH
        cd $REPOPATH
        export $IMAGE_VAR=localhost/${IMAGE##*/}:latest
        sudo podman build -t ${!IMAGE_VAR} .
        cd -
    else
        sudo podman pull "$IMAGE"
    fi
done

for name in ironic ironic-api ironic-conductor ironic-inspector dnsmasq httpd mariadb ipa-downloader coreos-downloader; do
    sudo podman ps | grep -w "$name$" && sudo podman kill $name
    sudo podman ps --all | grep -w "$name$" && sudo podman rm $name -f
done

# Remove existing pod
if  sudo podman pod exists ironic-pod ; then 
    sudo podman pod rm ironic-pod -f
fi

# set password for mariadb
mariadb_password=$(echo $(date;hostname)|sha256sum |cut -c-20)

# Create pod
sudo podman pod create -n ironic-pod 

# Start dnsmasq, http, mariadb, and ironic containers using same image
sudo podman run -d --net host --privileged --name dnsmasq  --pod ironic-pod \
     -v $IRONIC_DATA_DIR:/shared --entrypoint /bin/rundnsmasq ${IRONIC_IMAGE}

sudo podman run -d --net host --privileged --name httpd --pod ironic-pod \
     -v $IRONIC_DATA_DIR:/shared --entrypoint /bin/runhttpd ${IRONIC_IMAGE}

sudo podman run -d --net host --privileged --name mariadb --pod ironic-pod \
     -v $IRONIC_DATA_DIR:/shared --entrypoint /bin/runmariadb \
     --env MARIADB_PASSWORD=$mariadb_password ${IRONIC_IMAGE}

sudo podman run -d --net host --privileged --name ironic-conductor --pod ironic-pod \
     --env MARIADB_PASSWORD=$mariadb_password \
     --env OS_CONDUCTOR__HEARTBEAT_TIMEOUT=120 \
     --entrypoint /bin/runironic-conductor \
     -v $IRONIC_DATA_DIR:/shared ${IRONIC_IMAGE}

sudo podman run -d --net host --privileged --name ironic-api --pod ironic-pod \
     --env MARIADB_PASSWORD=$mariadb_password \
     --entrypoint /bin/runironic-api \
     -v $IRONIC_DATA_DIR:/shared ${IRONIC_IMAGE}

sudo podman run -d --net host --privileged --name ipa-downloader --pod ironic-pod \
     -v $IRONIC_DATA_DIR:/shared ${IPA_DOWNLOADER_IMAGE} /usr/local/bin/get-resource.sh

sudo podman run -d --net host --privileged --name coreos-downloader --pod ironic-pod \
     -v $IRONIC_DATA_DIR:/shared ${COREOS_DOWNLOADER_IMAGE} /usr/local/bin/get-resource.sh $RHCOS_IMAGE_URL

# Start Ironic Inspector
sudo podman run -d --net host --privileged --name ironic-inspector \
     --pod ironic-pod -v $IRONIC_DATA_DIR:/shared "${IRONIC_INSPECTOR_IMAGE}"

# Wait for images to be downloaded/ready
while ! curl --fail http://localhost/images/rhcos-ootpa-latest.qcow2.md5sum ; do sleep 1 ; done
while ! curl --fail --head http://localhost/images/ironic-python-agent.initramfs ; do sleep 1; done
while ! curl --fail --head http://localhost/images/ironic-python-agent.tar.headers ; do sleep 1; done
while ! curl --fail --head http://localhost/images/ironic-python-agent.kernel ; do sleep 1; done
