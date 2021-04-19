#!/usr/bin/env bash
set -x

source logging.sh
source common.sh
source validation.sh

early_cleanup_validation

sudo podman image prune --all -f
sudo podman volume prune -f
