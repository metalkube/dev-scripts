#!/bin/bash

set -ex

source common.sh

figlet "Building the Installer" | lolcat

eval "$(go env)"
echo "$GOPATH" | lolcat # should print $HOME/go or something like that

pushd "$GOPATH/src/github.com/metalkube/kni-installer"
export MODE=release
export TAGS=libvirt
./hack/build.sh
popd
