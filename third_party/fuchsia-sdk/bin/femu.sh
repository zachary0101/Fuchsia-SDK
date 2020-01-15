#!/bin/bash
# Copyright 2019 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

set -u

SCRIPT_SRC_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)"

# Fuchsia command common functions.
source "${SCRIPT_SRC_DIR}/fuchsia-common.sh" || exit $?

FUCHSIA_SDK_PATH="$(realpath "${SCRIPT_SRC_DIR}/../sdk")"
FUCHSIA_IMAGE_WORK_DIR="$(realpath "${SCRIPT_SRC_DIR}/../images")"


FUCHSIA_BUCKET="${DEFAULT_FUCHSIA_BUCKET}"

IMAGE_NAME="qemu-x64"
usage () {
  echo "Usage: $0"
  echo "  [--work-dir <directory to store image assets>]"
  echo "    Defaults to ${FUCHSIA_IMAGE_WORK_DIR}"
  echo "  [--bucket <fuchsia gsutil bucket>]"
  echo "    Defaults to ${FUCHSIA_BUCKET}"
  echo "  [--image <image name>]"
  echo "    Defaults to ${IMAGE_NAME}"
  echo "  [--authorized-keys <file>]"
  echo "    The authorized public key file for securing the device.  Defaults to "
  echo "    the output of 'ssh-add -L'"
}

AUTH_KEYS_FILE=""

# Parse command line
while (( "$#" )); do
case $1 in
    --work-dir)
    shift
    FUCHSIA_IMAGE_WORK_DIR="${1:-.}"
    ;;
    --bucket)
    shift
    FUCHSIA_BUCKET="${1}"
    ;;
    --image)
    shift
    IMAGE_NAME="${1}"
    ;;
    --authorized-keys)
    shift
    AUTH_KEYS_FILE="${1}"
    ;;
    *)
    # unknown option
    fx-error "Unknown option $1."
    usage
    exit 1
    ;;
esac
shift
done

# Prepare SSH authorized_keys file for adding to the system image
if [[ ! -f "${AUTH_KEYS_FILE}" ]]; then
    AUTH_KEYS_FILE="${FUCHSIA_SDK_PATH}/authkeys.txt"
fi

if [[ ! -f "${AUTH_KEYS_FILE}" ]]; then
  # Store the SSL auth keys to a file for sending to the device.
  if ! ssh-add -L > "${AUTH_KEYS_FILE}"; then
    fx-error "Cannot determine authorized keys: $(cat "${AUTH_KEYS_FILE}")."
    exit 1
  fi
fi

if [[ ! "$(wc -l < "${AUTH_KEYS_FILE}")" -ge 1 ]]; then
  fx-error "Cannot determine authorized keys: $(cat "${AUTH_KEYS_FILE}")."
  exit 2
fi

# Enable error checking for all commands
err_print() {
  echo "Error on line $1"
}
trap 'err_print $LINENO' ERR
set -e

# Download the system images and packages
echo "Checking for system images and packages"
"${SCRIPT_SRC_DIR}/fpave.sh"  --prepare --image "${IMAGE_NAME}" --bucket "${FUCHSIA_BUCKET}" --work-dir "${FUCHSIA_IMAGE_WORK_DIR}"
"${SCRIPT_SRC_DIR}/fserve.sh" --prepare --image "${IMAGE_NAME}" --bucket "${FUCHSIA_BUCKET}" --work-dir "${FUCHSIA_IMAGE_WORK_DIR}"

# Download aemu if it is not already present
echo "Checking for aemu binaries"
DOWNLOADS_DIR="${SCRIPT_SRC_DIR}/../images/emulator"
ARCH=linux-amd64
VER_AEMU=latest
if [ ! -f "${DOWNLOADS_DIR}/aemu-${ARCH}-${VER_AEMU}.zip" ]; then
  mkdir -p "${DOWNLOADS_DIR}"
  echo -e "Downloading aemu archive...\c"
  curl -sL "https://chrome-infra-packages.appspot.com/dl/fuchsia/third_party/aemu/${ARCH}/+/${VER_AEMU}" -o "${DOWNLOADS_DIR}/aemu-${ARCH}-${VER_AEMU}.zip"
  echo "complete."
fi
if [ ! -d "${DOWNLOADS_DIR}/aemu-${ARCH}" ]; then
  echo -e "Extracting aemu archive...\c"
  unzip -q "${DOWNLOADS_DIR}/aemu-${ARCH}-${VER_AEMU}.zip" -d "${DOWNLOADS_DIR}/aemu-${ARCH}"
  echo "complete."
fi

# Configure paths to the various tools needed
AEMU="${DOWNLOADS_DIR}/aemu-${ARCH}"
SDK="${SCRIPT_SRC_DIR}/../sdk"
FVMTOOL="${SDK}/tools/fvm"
ZBITOOL="${SDK}/tools/zbi"
SYSIMAGES="${SCRIPT_SRC_DIR}/../images/image"
TMPIMAGES="${SCRIPT_SRC_DIR}/../images/emulator"
INITRD="${TMPIMAGES}/tmp-fuchsia.zbi"
SYSTEM_FVM="${TMPIMAGES}/tmp-fvm.blk"
SYSTEM_QCOW="${TMPIMAGES}/tmp-qcow.blk"

# Add the public key into the ZBI disk image, so the emulator will allow us to connect in
echo "Creating initrd fuchsia.zbi with SSH keys from ${AUTH_KEYS_FILE}"
"${ZBITOOL}" -o "${INITRD}" "${SYSIMAGES}/zircon-a.zbi" -e "data/ssh/authorized_keys=${AUTH_KEYS_FILE}"

# Copy the FVM image and resize it to 1GB, since the default is to have zero free space
echo "Creating fvm blk and resizing it to 1GB"
cp -f "${SYSIMAGES}/storage-full.blk" "${SYSTEM_FVM}"
chmod u+w "${SYSTEM_FVM}"
"${FVMTOOL}" "${SYSTEM_FVM}" extend --length 1073741824

# Convert the image into QCOW2 format so we can create throwaway snapshots
echo "Creating qcow blk as copy-on-write snapshot"
"${AEMU}/qemu-img" convert -f raw -O qcow2 -c "${SYSTEM_FVM}" "${SYSTEM_QCOW}"

# MAC address configuration from $FUCHSIA/tools/devshell/emu script
echo "Configuring networking for qemu tun/tap device"
IFNAME="qemu"
HASH="$(echo $IFNAME | shasum)"
SUFFIX="$(for i in {0..2}; do echo -n :"${HASH:$(( 2 * i )):2}"; done)"
MACADDR="52:54:00${SUFFIX}"
TAP_IFS="$(ip tuntap show 2>/dev/null)"
if [[ ! "$TAP_IFS" =~ ${IFNAME}: ]]; then
  echo
  fx-error "ERROR! qemu network device not found"
  fx-error "To use aemu with networking on Linux, configure tun/tap:"
  echo
  fx-error "sudo ip tuntap add dev $IFNAME mode tap user $USER && sudo ip link set $IFNAME up"
  exit 1
fi

# Other qemu variables
KERNEL="${SYSIMAGES}/qemu-kernel.kernel"
ENTROPY="$(head -c 32 /dev/urandom | shasum -a 256 | awk '{ print $1 }')"

export LD_LIBRARY_PATH="${AEMU}/lib64/qt/lib:${AEMU}/lib64/"

echo "Starting aemu"
"${AEMU}/emulator" \
  -feature VirtioInput,RefCountPipe,KVM,GLDirectMem,Vulkan \
  -window-size 1280x800 \
  -gpu host \
  -fuchsia \
  -kernel "${KERNEL}" \
  -initrd "${INITRD}" \
  -m 2048 \
  -serial stdio \
  -vga none \
  -device virtio-keyboard-pci \
  -device virtio_input_multi_touch_pci_1 \
  -smp 4,threads=2 \
  -machine q35 \
  -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
  -enable-kvm \
  -cpu host,migratable=no,+invtsc \
  -netdev type=tap,ifname=qemu,script=no,downscript=no,id=net0 \
  -device e1000,netdev=net0,mac="${MACADDR}" \
  -snapshot \
  -drive file="${SYSTEM_QCOW},format=qcow2,if=none,id=blobstore,snapshot=on" \
  -device virtio-blk-pci,drive=blobstore \
  -append "TERM=xterm kernel.serial=legacy kernel.entropy-mixin=${ENTROPY} kernel.halt-on-panic=true "
