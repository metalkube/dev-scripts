#!/usr/bin/bash

set -ex

source logging.sh
#source common.sh
eval "$(go env)"

# Get the latest bits for baremetal-operator
export BMOPATH="$GOPATH/src/github.com/metalkube/baremetal-operator"

# Make a local copy of the baremetal-operator code to make changes
cp -r $BMOPATH/deploy ocp/.
sed -i 's/namespace: .*/namespace: openshift-machine-api/g' ocp/deploy/role_binding.yaml

# Start deploying on the new cluster
oc --config ocp/auth/kubeconfig apply -f ocp/deploy/service_account.yaml --namespace=openshift-machine-api
oc --config ocp/auth/kubeconfig apply -f ocp/deploy/role.yaml --namespace=openshift-machine-api
oc --config ocp/auth/kubeconfig apply -f ocp/deploy/role_binding.yaml
oc --config ocp/auth/kubeconfig apply -f ocp/deploy/crds/metalkube_v1alpha1_baremetalhost_crd.yaml
oc --config ocp/auth/kubeconfig apply -f ocp/deploy/operator.yaml --namespace=openshift-machine-api
