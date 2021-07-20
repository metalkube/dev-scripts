if $OPENSHIFT_INSTALLER coreos print-stream-json >/dev/null 2>&1; then
    $OPENSHIFT_INSTALLER coreos print-stream-json > $OCP_DIR/rhcos.json
    export MACHINE_OS_INSTALLER_IMAGE_URL=$(jq -r '.architectures.x86_64.artifacts.openstack.formats["qcow2.gz"].disk.location' $OCP_DIR/rhcos.json)
    export MACHINE_OS_INSTALLER_IMAGE_SHA256=$(jq -r '.architectures.x86_64.artifacts.openstack.formats["qcow2.gz"].disk["sha256"]' $OCP_DIR/rhcos.json)
    export MACHINE_OS_IMAGE_URL=${MACHINE_OS_IMAGE_URL:-${MACHINE_OS_INSTALLER_IMAGE_URL}}
    export MACHINE_OS_IMAGE_NAME=$(basename ${MACHINE_OS_IMAGE_URL})
    export MACHINE_OS_IMAGE_SHA256=${MACHINE_OS_IMAGE_SHA256:-${MACHINE_OS_INSTALLER_IMAGE_SHA256}}

    export MACHINE_OS_INSTALLER_BOOTSTRAP_IMAGE_URL=$(jq -r '.architectures.x86_64.artifacts.qemu.formats["qcow2.gz"].disk.location' $OCP_DIR/rhcos.json)
    export MACHINE_OS_INSTALLER_BOOTSTRAP_IMAGE_SHA256=$(jq -r '.architectures.x86_64.artifacts.qemu.formats["qcow2.gz"].disk["sha256"]' $OCP_DIR/rhcos.json)
    export MACHINE_OS_BOOTSTRAP_IMAGE_URL=${MACHINE_OS_BOOTSTRAP_IMAGE_URL:-${MACHINE_OS_INSTALLER_BOOTSTRAP_IMAGE_URL}}
    export MACHINE_OS_BOOTSTRAP_IMAGE_NAME=$(basename ${MACHINE_OS_BOOTSTRAP_IMAGE_URL})
    export MACHINE_OS_BOOTSTRAP_IMAGE_URL=${MACHINE_OS_BOOTSTRAP_IMAGE_URL:-${MACHINE_OS_INSTALLER_BOOTSTRAP_IMAGE_URL}}
    export MACHINE_OS_BOOTSTRAP_IMAGE_SHA256=${MACHINE_OS_BOOTSTRAP_IMAGE_SHA256:-${MACHINE_OS_INSTALLER_BOOTSTRAP_IMAGE_SHA256}}

    export MACHINE_OS_INSTALLER_BOOTSTRAP_IMAGE_UNCOMPRESSED_SHA256=$(jq -r '.architectures.x86_64.artifacts.qemu.formats["qcow2.gz"].disk["uncompressed-sha256"]' $OCP_DIR/rhcos.json)
    export MACHINE_OS_BOOTSTRAP_IMAGE_UNCOMPRESSED_SHA256=${MACHINE_OS_BOOTSTRAP_IMAGE_UNCOMPRESSED_SHA256:-${MACHINE_OS_INSTALLER_BOOTSTRAP_IMAGE_UNCOMPRESSED_SHA256}}
else
  if [[ ! -f "$OCP_DIR/rhcos.json" ]]; then
    if [[ -v JOB_NAME ]] && [[ "$JOB_NAME" =~ "openshift-installer" ]]; then
      # Get the SHA from the PR if we're in CI
      OPENSHIFT_INSTALL_COMMIT=${PULL_PULL_SHA:-$(echo "$JOB_SPEC" | jq -r '.refs.pulls[0].sha')}
    else
      # Get the git commit that the openshift installer was built from
      OPENSHIFT_INSTALL_COMMIT=$($OPENSHIFT_INSTALLER version | grep commit | cut -d' ' -f4)
    fi
  
    # Get the git commit that the openshift installer was built from
    OPENSHIFT_INSTALL_COMMIT=$($OPENSHIFT_INSTALLER version | grep commit | cut -d' ' -f4)
  
    # Get the rhcos.json for that commit
    OPENSHIFT_INSTALLER_MACHINE_OS=${OPENSHIFT_INSTALLER_MACHINE_OS:-https://raw.githubusercontent.com/openshift/installer/$OPENSHIFT_INSTALL_COMMIT/data/data/rhcos.json}
  
    # Get the rhcos.json for that commit, and find the baseURI and openstack image path
    curl -o $OCP_DIR/rhcos.json "${OPENSHIFT_INSTALLER_MACHINE_OS}"
  fi
  
  export MACHINE_OS_INSTALLER_IMAGE_URL=$(jq -r '.baseURI + .images.openstack.path' $OCP_DIR/rhcos.json)
  export MACHINE_OS_INSTALLER_IMAGE_SHA256=$(jq -r '.images.openstack.sha256' $OCP_DIR/rhcos.json)
  export MACHINE_OS_IMAGE_URL=${MACHINE_OS_IMAGE_URL:-${MACHINE_OS_INSTALLER_IMAGE_URL}}
  export MACHINE_OS_IMAGE_NAME=$(basename ${MACHINE_OS_IMAGE_URL})
  export MACHINE_OS_IMAGE_SHA256=${MACHINE_OS_IMAGE_SHA256:-${MACHINE_OS_INSTALLER_IMAGE_SHA256}}
  
  export MACHINE_OS_INSTALLER_BOOTSTRAP_IMAGE_URL=$(jq -r '.baseURI + .images.qemu.path' $OCP_DIR/rhcos.json)
  export MACHINE_OS_INSTALLER_BOOTSTRAP_IMAGE_SHA256=$(jq -r '.images.qemu.sha256' $OCP_DIR/rhcos.json)
  export MACHINE_OS_BOOTSTRAP_IMAGE_URL=${MACHINE_OS_BOOTSTRAP_IMAGE_URL:-${MACHINE_OS_INSTALLER_BOOTSTRAP_IMAGE_URL}}
  export MACHINE_OS_BOOTSTRAP_IMAGE_NAME=$(basename ${MACHINE_OS_BOOTSTRAP_IMAGE_URL})
  export MACHINE_OS_BOOTSTRAP_IMAGE_SHA256=${MACHINE_OS_BOOTSTRAP_IMAGE_SHA256:-${MACHINE_OS_INSTALLER_BOOTSTRAP_IMAGE_SHA256}}
  
  # FIXME the installer cache expects an uncompressed sha256
  # https://github.com/openshift/installer/issues/2845
  export MACHINE_OS_INSTALLER_BOOTSTRAP_IMAGE_UNCOMPRESSED_SHA256=$(jq -r '.images.qemu["uncompressed-sha256"]' $OCP_DIR/rhcos.json)
  export MACHINE_OS_BOOTSTRAP_IMAGE_UNCOMPRESSED_SHA256=${MACHINE_OS_BOOTSTRAP_IMAGE_UNCOMPRESSED_SHA256:-${MACHINE_OS_INSTALLER_BOOTSTRAP_IMAGE_UNCOMPRESSED_SHA256}}
fi

if [ "${RHCOS_LIVE_IMAGES}"  == "true" ]; then
	export LIVE_ISO_IMAGE_URL=$(jq -r '.architectures.x86_64.artifacts.metal.formats["iso"].disk.location' $OCP_DIR/rhcos.json)
	export LIVE_KERNEL_IMAGE_URL=$(jq -r '.architectures.x86_64.artifacts.metal.formats["pxe"].kernel.location' $OCP_DIR/rhcos.json)
	export LIVE_ROOTFS_IMAGE_URL=$(jq -r '.architectures.x86_64.artifacts.metal.formats["pxe"].rootfs.location' $OCP_DIR/rhcos.json)
	export LIVE_INITRAMFS_IMAGE_URL=$(jq -r '.architectures.x86_64.artifacts.metal.formats["pxe"].initramfs.location' $OCP_DIR/rhcos.json)

	MACHINE_OS_INSTALLER_LIVE_URLS=""
	for URL in $LIVE_ISO_IMAGE_URL \
		   $LIVE_KERNEL_IMAGE_URL \
		   $LIVE_ROOTFS_IMAGE_URL \
		   $LIVE_INITRAMFS_IMAGE_URL; do
		MACHINE_OS_INSTALLER_LIVE_URLS+="${URL},"
	done
	# Trim tailing ','
	MACHINE_OS_INSTALLER_LIVE_URLS=$(echo $MACHINE_OS_INSTALLER_LIVE_URLS | sed 's/,*$//')

	export MACHINE_OS_IMAGE_URL=${LIVE_ISO_IMAGE_URL}
	export MACHINE_OS_IMAGE_NAME=$(basename ${MACHINE_OS_IMAGE_URL})
	export MACHINE_OS_IMAGE_SHA256=$(jq -r '.architectures.x86_64.artifacts.metal.formats["iso"].disk.sha256' $OCP_DIR/rhcos.json)
	export MACHINE_OS_LIVE_KERNEL=$(basename ${LIVE_KERNEL_IMAGE_URL})
	export MACHINE_OS_LIVE_KERNEL_SHA256=$(jq -r '.architectures.x86_64.artifacts.metal.formats["pxe"].kernel.sha256' $OCP_DIR/rhcos.json)
	export MACHINE_OS_LIVE_ROOTFS=$(basename ${LIVE_ROOTFS_IMAGE_URL})
	export MACHINE_OS_LIVE_ROOTFS_SHA256=$(jq -r '.architectures.x86_64.artifacts.metal.formats["pxe"].rootfs.sha256' $OCP_DIR/rhcos.json)
	export MACHINE_OS_LIVE_INITRAMFS=$(basename ${LIVE_INITRAMFS_IMAGE_URL})
	export MACHINE_OS_LIVE_INITRAMFS_SHA256=$(jq -r '.architectures.x86_64.artifacts.metal.formats["pxe"].initramfs.sha256' $OCP_DIR/rhcos.json)
fi
