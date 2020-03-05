#!/bin/bash
set -ex

# grabs files and puts them into $LOGDIR to be saved as jenkins artifacts
function getlogs(){
    LOGDIR=/home/notstack/dev-scripts/logs

    # Grab the host journal
    sudo journalctl > $LOGDIR/bootstrap-host-system.journal

    for c in httpd-${PROVISIONING_NETWORK_NAME} machine-os-downloader ipa-downloader ; do
        sudo podman logs $c > $LOGDIR/$c.log || true
    done

    # And the VM journals and staticpod container logs
    BM_SUB=$(echo "${EXTERNAL_SUBNET}" | cut -d"/" -f1 | sed "s/0$//")
    for HOST in $(sudo virsh net-dhcp-leases ${BAREMETAL_NETWORK_NAME} | grep -o "${BM_SUB}.*/" | cut -d"/" -f1) ; do
        sshpass -p notworking $SSH core@$HOST sudo journalctl > $LOGDIR/$HOST-system.journal || true
        sshpass -p notworking $SSH core@$HOST sudo journalctl -u ironic.service > $LOGDIR/$HOST-ironic.journal || true
	for c in $(sshpass -p notworking $SSH core@$HOST sudo podman ps -a | grep -e ironic -e downloader -e httpd -e dnsmasq -e mariadb | awk '{print $NF}'); do
		sshpass -p notworking $SSH core@$HOST sudo podman logs $c > $LOGDIR/${HOST}-${c}-container.log || true
	done
    done

    # openshift info
    export KUBECONFIG=ocp/$CLUSTER_NAME/auth/kubeconfig
    oc --request-timeout=5s get clusterversion/version > $LOGDIR/cluster_version.log || true
    oc --request-timeout=5s get clusteroperators > $LOGDIR/cluster_operators.log || true
    oc --request-timeout=5s get pods --all-namespaces | grep -v Running | grep -v Completed  > $LOGDIR/failing_pods.log || true

    # Baremetal Operator info
    mkdir -p $LOGDIR/baremetal-operator
    BMO_POD=$(oc --request-timeout=5s get pods --namespace openshift-machine-api | grep metal3 | awk '{print $1}')
    BMO_CONTAINERS=$(oc --request-timeout=5s get pods ${BMO_POD} -n openshift-machine-api -o jsonpath="{.spec['containers','initContainers'][*].name}")
    for c in ${BMO_CONTAINERS}; do
        oc --request-timeout=5s logs ${BMO_POD} -c ${c} --namespace openshift-machine-api > $LOGDIR/baremetal-operator/${c}.log
    done
}
trap getlogs EXIT

# Point at our CI custom config file (contains the PULL_SECRET)
export CONFIG=/opt/data/config_notstack.sh

sudo yum install -y jq golang make unzip

# Clone the project being tested, "dev-scripts" will have been cloned in the jenkins
# job definition, for all others we do it here
if [ -n "$REPO" -a -n "$BRANCH" ]  ; then
    pushd ~
    if [ ! -d ${BASE_REPO#*/} ] ; then
        git clone https://github.com/$BASE_REPO -b ${BASE_BRANCH:-master}
        cd ${BASE_REPO#*/}
        git pull --no-edit  https://github.com/$REPO $BRANCH
        git log --oneline -10 --graph
    fi
    popd
fi

# Project-specific actions. If these directories exist in $HOME, move
# them to the correct $GOPATH locations.
for PROJ in installer ; do
    [ ! -d /home/notstack/$PROJ ] && continue

    if [ "$PROJ" == "installer" ]; then
      export KNI_INSTALL_FROM_GIT=true
    fi

    # Set origin so that sync_repo_and_patch is rebasing against the correct source
    cd /home/notstack/$PROJ
    git branch -M master
    git remote set-url origin https://github.com/$BASE_REPO
    cd -

    mkdir -p $HOME/go/src/github.com/${BASE_REPO/\/*}
    mv /home/notstack/$PROJ $HOME/go/src/github.com/$BASE_REPO
done

# If directories for the containers exists then we build the images (as they are what triggered the job)
if [ -d "/home/notstack/ironic-image" ] ; then
    export IRONIC_LOCAL_IMAGE=https://github.com/metal3-io/ironic-image
    export UPSTREAM_IRONIC=true
fi
if [ -d "/home/notstack/ironic-inspector-image" ] ; then
    export IRONIC_INSPECTOR_LOCAL_IMAGE=https://github.com/metal3-io/ironic-inspector-image
    export UPSTREAM_IRONIC=true
fi
if [ -d "/home/notstack/baremetal-runtimecfg" ] ; then
    export BAREMETAL_RUNTIMECFG_LOCAL_IMAGE=https://github.com/openshift/baremetal-runtimecfg
fi
if [ -d "/home/notstack/mdns-publisher" ] ; then
    export MDNS_PUBLISHER_LOCAL_IMAGE=https://github.com/openshift/mdns-publisher
fi
# coredns-mdns is unique because it is vendored into the openshift/coredns project
# and that is where the image gets built.
if [ -d "/home/notstack/coredns-mdns" ] ; then
    pushd /home/notstack
    git clone https://github.com/openshift/coredns
    cd coredns
    # Update the vendoring with our local changes
    GO111MODULE=on go mod edit -replace github.com/openshift/coredns-mdns=/home/notstack/coredns-mdns
    GO111MODULE=on go mod vendor
    popd
    export COREDNS_LOCAL_IMAGE=https://github.com/openshift/coredns
    export COREDNS_DOCKERFILE=Dockerfile.openshift
fi

# Some of the setup done above needs to be done before we source common.sh
# in order for correct defaults to be set
source common.sh

if [ -n "$PS1" ]; then
    echo "This script is for running dev-script in our CI env, it is tailored to a"
    echo "very specific setup and unlikely to be usefull outside of CI"
    exit 1
fi

# Display the "/" filesystem mounted incase we need artifacts from it after the job
mount | grep root-

# Make dnf store its cache on /opt so packages don't need to be downloaded for each job
sudo mkdir -p /opt/data/dnfcache
echo keepcache=True | sudo tee -a /etc/dnf/dnf.conf
sudo mount -o bind /opt/data/dnfcache /var/cache/dnf

# Install terraform
if [ ! -f /usr/local/bin/terraform ]; then
    curl -O https://releases.hashicorp.com/terraform/0.12.2/terraform_0.12.2_linux_amd64.zip
    unzip terraform_*.zip
    sudo install terraform /usr/local/bin
    rm -f terraform_*.zip terraform
fi

# Run dev-scripts
set -o pipefail
timeout -s 9 120m make |& sed -e 's/.*auths.*/*** PULL_SECRET ***/g'

# Deployment is complete, but now wait to ensure the worker node comes up.
export KUBECONFIG=ocp/$CLUSTER_NAME/auth/kubeconfig

wait_for_worker() {
    worker=$1
    echo "Waiting for worker $worker to appear ..."
    while [ "$(oc get nodes | grep $worker)" = "" ]; do sleep 5; done
    TIMEOUT_MINUTES=15
    echo "$worker registered, waiting $TIMEOUT_MINUTES minutes for Ready condition ..."
    oc wait node/$worker --for=condition=Ready --timeout=$[${TIMEOUT_MINUTES} * 60]s
}
wait_for_worker worker-0

