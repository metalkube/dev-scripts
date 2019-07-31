#!/usr/bin/env bash
set -x
set -e

source logging.sh
source utils.sh
source common.sh
source ocp_install_env.sh

# Do some PULL_SECRET sanity checking
if [[ "${OPENSHIFT_RELEASE_IMAGE}" == *"registry.svc.ci.openshift.org"* ]]; then
    if [[ "${PULL_SECRET}" != *"registry.svc.ci.openshift.org"* ]]; then
        echo "Please get a valid pull secret for registry.svc.ci.openshift.org."
        exit 1
    fi
fi

if [[ "${PULL_SECRET}" != *"cloud.openshift.com"* ]]; then
    echo "Please get a valid pull secret for cloud.openshift.com."
    exit 1
fi

# NOTE: This is equivalent to the external API DNS record pointing the API to the API VIP
if [ "$MANAGE_BR_BRIDGE" == "y" ] ; then
    API_VIP=$(dig +noall +answer "api.${CLUSTER_DOMAIN}" @$(network_ip baremetal) | awk '{print $NF}')
    INGRESS_VIP=$(python -c "from ansible.plugins.filter import ipaddr; print(ipaddr.nthhost('"$EXTERNAL_SUBNET"', 4))")
    echo "address=/api.${CLUSTER_DOMAIN}/${API_VIP}" | sudo tee /etc/NetworkManager/dnsmasq.d/openshift.conf
    echo "address=/.apps.${CLUSTER_DOMAIN}/${INGRESS_VIP}" | sudo tee -a /etc/NetworkManager/dnsmasq.d/openshift.conf
    sudo systemctl reload NetworkManager
else
    API_VIP=$(dig +noall +answer "api.${CLUSTER_DOMAIN}"  | awk '{print $NF}')
    INGRESS_VIP=$(dig +noall +answer "test.apps.${CLUSTER_DOMAIN}" | awk '{print $NF}')
fi

if [ ! -d ocp ]; then
    mkdir -p ocp

    if [ -z "$KNI_INSTALL_FROM_GIT" ]; then
      # Extract openshift-install from the release image
      extract_installer "${OPENSHIFT_RELEASE_IMAGE}" ocp/
    else
      # Clone and build the installer from source
      clone_installer
      build_installer
    fi

    # Validate there are enough nodes to avoid confusing errors later..
    NODES_LEN=$(jq '.nodes | length' ${NODES_FILE})
    if (( $NODES_LEN < ( $NUM_MASTERS + $NUM_WORKERS ) )); then
        echo "ERROR: ${NODES_FILE} contains ${NODES_LEN} nodes, but ${NUM_MASTERS} masters and ${NUM_WORKERS} workers requested"
        exit 1
    fi

    # Create a master_nodes.json file
    jq '.nodes[0:3] | {nodes: .}' "${NODES_FILE}" | tee "${MASTER_NODES_FILE}"

    # Create install config for openshift-installer
    generate_ocp_install_config ocp
fi

# Make sure Ironic is up
export OS_TOKEN=fake-token
export OS_URL=http://localhost:6385

wait_for_json ironic \
    "${OS_URL}/v1/nodes" \
    20 \
    -H "Accept: application/json" -H "Content-Type: application/json" -H "User-Agent: wait-for-json" -H "X-Auth-Token: $OS_TOKEN"

if [ $(sudo podman ps | grep -w -e "ironic-api$" -e "ironic-conductor$" -e "ironic-inspector$" -e "dnsmasq" -e "httpd" | wc -l) != 5 ]; then
    echo "Can't find required containers"
    exit 1
fi

# Run the fix_certs.sh script periodically as a workaround for
# https://github.com/openshift-metalkube/dev-scripts/issues/260
sudo systemd-run --on-active=30s --on-unit-active=1m --unit=fix_certs.service $(dirname $0)/fix_certs.sh

# Call openshift-installer to deploy the bootstrap node and masters
create_cluster ocp

echo "Cluster up, you can interact with it via oc --config ${KUBECONFIG} <command>"

# The deployment is complete, but we must manually add the IPs for the masters,
# as we don't have a way to do that automatically yet. This is required for
# CSRs to get auto approved for masters.
# https://github.com/openshift-metal3/dev-scripts/issues/260
# https://github.com/metal3-io/baremetal-operator/issues/242
./add-machine-ips.sh

# Bounce the machine approver to get it to notice the changes.
oc scale deployment -n openshift-cluster-machine-approver --replicas=0 machine-approver
while [ ! $(oc get deployment -n openshift-cluster-machine-approver machine-approver -o json | jq .spec.replicas) ]
do
  echo "Scaling down machine-approver..."
done
echo "Scaling up machine-approver..."
oc scale deployment -n openshift-cluster-machine-approver --replicas=1 machine-approver

# Wait a tiny bit, then list the csrs
sleep 5
oc get csr
# END Hack
