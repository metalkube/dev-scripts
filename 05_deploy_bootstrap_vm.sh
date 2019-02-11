#!/usr/bin/env bash
set -x
set -e

source ocp_install_env.sh
source common.sh
source get_rhcos_image.sh
source utils.sh

# FIXME this is configuring for the libvirt backend which is dev-only ref
# https://github.com/openshift/installer/blob/master/docs/dev/libvirt-howto.md
# We may need some additional steps from that doc in 02* and also to make the
# qemu endpoint configurable?
if [ ! -d ocp ]; then
    mkdir -p ocp
    export CLUSTER_ID=$(uuidgen --random)
    cat > ocp/install-config.yaml << EOF
apiVersion: v1beta1
baseDomain: ${BASE_DOMAIN}
clusterID:  ${CLUSTER_ID}
machines:
- name:     master
  platform: {}
  replicas: null
- name:     worker
  platform: {}
  replicas: null
metadata:
  creationTimestamp: null
  name: ${CLUSTER_NAME}
networking:
  clusterNetworks:
  - cidr: 10.128.0.0/14
    hostSubnetLength: 9
  machineCIDR: 192.168.126.0/24
  serviceCIDR: 172.30.0.0/16
  type: OpenshiftSDN
platform:
  libvirt:
    URI: qemu:///system
    network:
      if: tt0
pullSecret: |
  ${PULL_SECRET}
sshKey: |
  ${SSH_PUB_KEY}
EOF
fi


$GOPATH/src/github.com/openshift/installer/bin/openshift-install --dir ocp --log-level=debug create ignition-configs

# Here we can make any necessary changes to the ignition configs/manifests
# they can later be sync'd back into the installer via a new baremetal target

# Now re create the cluster (using the existing install-config and ignition-configs)
# Since we set the replicas to null, we should only get the bootstrap VM
# FIXME(shardy) this doesn't work, it creates the bootstrap and one master
#$GOPATH/src/github.com/openshift/installer/bin/openshift-install --dir ocp --log-level=debug create cluster
#exit 1

# ... so for now lets create the bootstrap VM manually and use the generated ignition config
# See https://coreos.com/os/docs/latest/booting-with-libvirt.html
IGN_FILE="/var/lib/libvirt/images/${CLUSTER_NAME}-bootstrap.ign"
sudo cp ocp/bootstrap.ign ${IGN_FILE}

# Apply patches to bootstrap ignition
apply_ignition_patches bootstrap "$IGN_FILE"

# Run a fake boostrap instance
sudo podman rm -f ostest-bootstrap || true
sudo podman run --name="ostest-bootstrap" \
  -d --privileged --net=host --systemd=true \
  --tmpfs /var/lib/containers/storage:rw,size=2G \
  -v $(pwd)/bootstrap/bootstrap.sh:/usr/local/bin/bootstrap.sh \
  -v $(pwd)/bootstrap/prepare-bootstrap.service:/etc/systemd/system/prepare-bootstrap.service \
  -v $(pwd)/ocp:/ocp \
  -ti centos:7 /sbin/init
sudo podman exec ostest-bootstrap systemctl start prepare-bootstrap
# Wait until prepare-bootstrap service completes. It attempts to reboot the container, so it exists with error
sudo podman exec -ti ostest-bootstrap journalctl -b -f -u prepare-bootstrap; rc=$?
# Start prepared bootstrap container again
sudo podman start ostest-bootstrap
# Mount container in bootstrap_mnt
bootstrap_mnt=$(sudo podman mount ostest-bootstrap)

# Internal dnsmasq should reserve IP addresses for each master
cp -f ironic/dnsmasq.conf /tmp
for i in 0 1 2; do
  NODE_MAC=$(cat "${WORKING_DIR}/ironic_nodes.json" | jq -r ".nodes[${i}].ports[0].address")
  NODE_IP="172.22.0.2${i}"
  HOSTNAME="${CLUSTER_NAME}-etcd-${i}.${BASE_DOMAIN}"
  # Make sure internal dnsmasq would assign an expected IP
  echo "dhcp-host=${NODE_MAC},${HOSTNAME},${NODE_IP}" >> /tmp/dnsmasq.conf
  # Reconfigure "external" dnsmasq
  echo "${NODE_IP} ${HOSTNAME} ${CLUSTER_NAME}-api.${BASE_DOMAIN}" | sudo tee -a /etc/hosts.openshift
  echo "srv-host=_etcd-server-ssl._tcp.${CLUSTER_NAME}.${BASE_DOMAIN},${HOSTNAME},2380,0,0" | sudo tee -a /etc/NetworkManager/dnsmasq.d/openshift.conf
done
sudo systemctl reload NetworkManager
cp /tmp/dnsmasq.conf ${bootstrap_mnt}/home/core
cp ${RHCOS_IMAGE_FILENAME_OPENSTACK} ${bootstrap_mnt}/home/core
# Build and start the ironic container
IRONIC_IMAGE=${IRONIC_IMAGE:-"quay.io/metalkube/metalkube-ironic"}
sudo podman exec -ti ostest-bootstrap podman pull "${IRONIC_IMAGE}"

sudo podman exec -ti ostest-bootstrap sudo podman run \
    -d --net host --privileged --name ironic \
    -v /home/core/dnsmasq.conf:/etc/dnsmasq.conf \
    -v "/home/core/${RHCOS_IMAGE_FILENAME_OPENSTACK}:/var/www/html/images/${RHCOS_IMAGE_FILENAME_OPENSTACK}" \
    "${IRONIC_IMAGE}"

# Create a master_nodes.json file
jq '.nodes[0:3] | {nodes: .}' "${WORKING_DIR}/ironic_nodes.json" | tee ocp/master_nodes.json

echo "You can now run 'podman exec -ti ostest-bootstrap sh' to enter bootstrap container"
