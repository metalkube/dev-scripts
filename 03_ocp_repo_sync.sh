#!/bin/bash

set -ex
source logging.sh
source common.sh
source utils.sh

eval "$(go env)"
echo "GOPATH: $GOPATH" # should print $HOME/go or something like that
# REPO_PATH is used in sync_repo_and_patch from utils.sh
export REPO_PATH="$GOPATH/src"

# Install baremetal-operator
sync_repo_and_patch github.com/metal3-io/baremetal-operator https://github.com/metal3-io/baremetal-operator.git

# Rebase machine-api-operator if it is present
MAO_DIR="${GOPATH}/src/github.com/openshift/machine-api-operator"
if [ -d "${MAO_DIR}" ]; then
    pushd ${MAO_DIR}
    git pull --rebase
    popd
fi
