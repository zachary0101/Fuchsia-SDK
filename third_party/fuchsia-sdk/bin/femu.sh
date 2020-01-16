#!/bin/bash
# Copyright 2019 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Parts of this script are copied from https://fuchsia.googlesource.com/fuchsia/+/1f396a7516e216c210d1713250b3bb824ea5d7f4/tools/devshell/emu
# This is annotated with "#begin fx emu" and "#end fx emu" to track the common lines

# Enable error checking for all commands, and clean up
err_print() {
  echo "Error on line $1"
  stty sane
}
trap 'err_print $LINENO' ERR
set -eu

SCRIPT_SRC_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)"
source "${SCRIPT_SRC_DIR}/fuchsia-common.sh" || exit $?
FUCHSIA_SDK_PATH="$(realpath "${SCRIPT_SRC_DIR}/../sdk")"
FUCHSIA_IMAGE_WORK_DIR="$(realpath "${SCRIPT_SRC_DIR}/../images")"
FUCHSIA_BUCKET="${DEFAULT_FUCHSIA_BUCKET}"
IMAGE_NAME="qemu-x64"
# TODO(fxb/43807): Replace FUCHSIA_ARCH with detecting the architecture, currently only tested with *-x64 images
FUCHSIA_ARCH="x64"

usage () {
  echo "Usage: $0 [--work-dir <dir>] [--bucket <name>] [--image <name>] [--authorized-keys <file>] [-a <mode>] [-c <text>] [-N [-I <ifname>]] [-u <path>] [-g <port> [-r <fps>] [-t <cmd>]] [-x <port> [-X <directory>]] [-e <directory>] [-w <size>] [-s <cpus>] [-k <authorized_keys_file>] [--audio] [--headless] [--software-gpu] [--debugger] [--help|-h]"
  echo "  --help|-h this usage information"
  echo "  --work-dir <directory to store image assets> defaults to ${FUCHSIA_IMAGE_WORK_DIR}"
  echo "  --bucket <fuchsia gsutil bucket> defaults to ${FUCHSIA_BUCKET}"
  echo "  --image <image name> defaults to to ${IMAGE_NAME}"
  echo "  --authorized-keys <file> public key file for accesssing the device. Defaults to output of 'ssh-add -L'"
  echo "  -a <mode> acceleration mode (auto, off, kvm, hvf, hax), default is auto"
  echo "  -c <text> add item to kernel command line"
  echo "  -ds <size> extends the fvm image size to <size> bytes. Default is twice the system image size."
  echo "  -N run with emulated nic via tun/tap"
  echo "  -I <ifname> uses the tun/tap interface named ifname"
  echo "  -u <path> execute aemu if-up script, default is no script"
  echo "  -g <port> enable gRPC service on port to control the emulator, default is 5556 when WebRTC service is enabled"
  echo "  -r <fps> webrtc frame rate when using gRPC service, default is 30"
  echo "  -t <cmd> execute the given command to obtain turn configuration"
  echo "  -x <port> enable WebRTC HTTP service on port"
  echo "  -w <size> window size, default is 1280x800"
  echo "  -s <cpus> number of cpus, 1 for uniprocessor, default is 4"
  echo "  --audio run with audio hardware added to the virtual machine"
  echo "  --headless run in headless mode"
  echo "  --software-gpu run without host GPU acceleration"
  echo "  --debugger pause on launch and wait for a debugger process to attach before resuming"
}

AUTH_KEYS_FILE=""
ACCEL="auto"
NET=0
DEBUGGER=0
IFNAME=""
AUDIO=0
HEADLESS=0
AEMU="emulator"
UPSCRIPT=no
WINDOW_SIZE="1280x800"
GRPC=
RTCFPS="30"
TURNCFG=""
GPU="host"
VULKAN=1
HTTP=0
CMDLINE=""
SMP=4
IMAGE_SIZE=
EXPERIMENT_ARM64=false

case $(uname -m) in
x86_64)
  HOST_ARCH=x64
  ;;
aarch64)
  HOST_ARCH=arm64
  ;;
*)
  fx-error "Unsupported host architecture: $(uname -m)"
  exit 1
esac

if [[ "$FUCHSIA_ARCH" != "$HOST_ARCH" ]]; then
  ACCEL=off
fi

# Propagate our TERM environment variable as a kernel command line
# argument.  This is first so that an explicit -c TERM=foo argument
# goes into CMDLINE later and overrides this.
if [[ -n $TERM ]]; then
    CMDLINE+="TERM=$TERM "
fi

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
#begin fx emu
  -a)
    shift
    ACCEL="$1"
    ;;
  -c)
    shift
    CMDLINE+="$1 "
    ;;
  -ds)
    shift
    IMAGE_SIZE="$1"
    ;;
  -N)
    NET=1
    ;;
  -I)
    shift
    IFNAME="$1"
    ;;
  -u)
    shift
    UPSCRIPT="$1"
    ;;
  -x)
    shift
    HTTP="$1"
    ;;
  -g)
    shift
    GRPC="$1"
    ;;
  -r)
    shift
    RTCFPS="$1"
    ;;
  -t)
    shift
    TURNCFG="$1"
    ;;
  -w)
    shift
    WINDOW_SIZE="$1"
    ;;
  -s)
    shift
    SMP="$1"
    ;;
  --audio)
    AUDIO=1
    ;;
  --headless)
    HEADLESS=1
    ;;
  --debugger)
    DEBUGGER=1
    ;;
  --software-gpu)
    GPU="swiftshader_indirect"
    ;;
  --experiment-arm64)
    EXPERIMENT_ARM64=true
    ;;
#end fx emu
  --help|-h)
    usage
    exit 0
    ;;
  *)
    # Remaining args are passed on to the emulator
    ;;
esac
shift
done

if [[ "$FUCHSIA_ARCH" == "arm64" ]]; then
  if ! "$EXPERIMENT_ARM64"; then
    fx-error "arm64 support is still experimental, requires --experiment-arm64"
    exit 1
  fi
fi


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
KERNEL="${SYSIMAGES}/qemu-kernel.kernel"


# Add the public key into the ZBI disk image, so the emulator will allow us to connect in
echo "Creating initrd fuchsia.zbi with SSH keys from ${AUTH_KEYS_FILE}"
"${ZBITOOL}" -o "${INITRD}" "${SYSIMAGES}/zircon-a.zbi" -e "data/ssh/authorized_keys=${AUTH_KEYS_FILE}"

# We resize the image to twice the system image size if no value is provided
if [[ "${IMAGE_SIZE}" == "" ]]; then
  #begin fvm.sh
  fvmraw="${SYSIMAGES}/storage-full.blk"
  stat_flags=()
  if [[ $(uname) == "Darwin" ]]; then
    stat_flags+=("-x")
  fi
  stat_output=$(stat "${stat_flags[@]}" "${fvmraw}")
  if [[ "$stat_output" =~ Size:\ ([0-9]+) ]]; then
    size="${BASH_REMATCH[1]}"
    recommended_size=$((2*size))
    if [[ $# -gt 2 && -n "${IMAGE_SIZE}" ]]; then
      IMAGE_SIZE="${IMAGE_SIZE}"
      if [[ "${IMAGE_SIZE}" -le "${size}" ]]; then
        fx-error "Image size has to be greater than ${size} bytes.  Recommended value is ${recommended_size} bytes."
        return 1
      fi
    else
      echo "Selected recommended size ${recommended_size} as twice system image size ${size}"
      IMAGE_SIZE="${recommended_size}"
    fi
  #end fvm.sh
  fi
fi

# Copy the FVM image and resize it since the default is to have zero free space
echo "Creating fvm blk and resizing it to ${IMAGE_SIZE}"
cp -f "${SYSIMAGES}/storage-full.blk" "${SYSTEM_FVM}"
chmod u+w "${SYSTEM_FVM}"
"${FVMTOOL}" "${SYSTEM_FVM}" extend --length "${IMAGE_SIZE}"

# Convert the image into QCOW2 format so we can create throwaway snapshots and not modify the original system image
echo "Creating qcow blk as copy-on-write snapshot"
"${AEMU}/qemu-img" convert -f raw -O qcow2 -c "${SYSTEM_FVM}" "${SYSTEM_QCOW}"


#begin fx emu

# construct the args for aemu
ARGS=()
ARGS+=("-m" "2048")
ARGS+=("-serial" "stdio")
ARGS+=("-vga" "none")
ARGS+=("-device" "virtio-keyboard-pci")
ARGS+=("-device" "virtio_input_multi_touch_pci_1")

if [[ $SMP != 1 ]]; then
  ARGS+=("-smp" "${SMP},threads=2")
fi

# TODO(raggi): do we want to use hda on arm64?
if (( AUDIO )); then
  ARGS+=("-soundhw" "hda")
fi

FEATURES="VirtioInput,RefCountPipe"

if [[ "$ACCEL" == "auto" ]]; then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    ACCEL="hvf"
  else
    ACCEL="kvm"
  fi
fi

case "$FUCHSIA_ARCH" in
x64)
  ARGS+=("-machine" "q35")
  ARGS+=("-device" "isa-debug-exit,iobase=0xf4,iosize=0x04")
;;
arm64)
  ARGS+=("-machine" "virt")
;;
esac

if [[ "$ACCEL" == "kvm" ]]; then
  ARGS+=("-enable-kvm" "-cpu" "host,migratable=no,+invtsc")
  FEATURES+=",KVM,GLDirectMem"
elif [[ "$ACCEL" == "hvf" ]]; then
  ARGS+=("-enable-hvf" "-cpu" "Haswell")
  FEATURES+=",HVF,GLDirectMem"
elif [[ "$ACCEL" == "hax" ]]; then
  ARGS+=("-enable-hax" "-cpu" "Haswell")
  FEATURES+=",HAXM,GLDirectMem"
elif [[ "$ACCEL" == "off" ]]; then
  case "$FUCHSIA_ARCH" in
  x64)
    ARGS+=("-cpu" "Haswell,+smap,-check,-fsgsbase")
    ;;
  arm64)
    ARGS+=("-cpu" "cortex-a53")
    ;;
  esac
  # disable vulkan as not useful without kvm,hvf,hax and support
  # for coherent host visible memory.
  VULKAN=0
  FEATURES+=",-GLDirectMem"
else
  fx-error Unsupported acceleration mode
  exit 1
fi

if (( VULKAN )); then
  FEATURES+=",Vulkan"
else
  FEATURES+=",-Vulkan"
fi

OPTIONS=()
OPTIONS+=("-feature" "$FEATURES")
OPTIONS+=("-window-size" "$WINDOW_SIZE")
OPTIONS+=("-gpu" "$GPU")
if (( DEBUGGER )); then
    OPTIONS+=("-wait-for-debugger")
fi

if (( HEADLESS )); then
    OPTIONS+=("-no-window")
fi

# use port 5556 by default
if (( HTTP )); then
  GRPC="${GRPC:-5556}"
fi

if (( GRPC )); then
  OPTIONS+=("-grpc" "$GRPC")
  OPTIONS+=("-rtcfps" "$RTCFPS")
  if [[ -n "$TURNCFG" ]]; then
    OPTIONS+=("-turncfg" "$TURNCFG")
  fi
fi

if (( NET )); then
  if [[ "$(uname -s)" == "Darwin" ]]; then
    if [[ -z "$IFNAME" ]]; then
      IFNAME="tap0"
    fi
    if [[ ! -c "/dev/$IFNAME" ]]; then
      echo "To use aemu with networking on macOS, install the tun/tap driver:"
      echo "http://tuntaposx.sourceforge.net/download.xhtml"
      exit 1
    fi
    if [[ ! -w "/dev/$IFNAME" ]]; then
      echo "For networking /dev/$IFNAME must be owned by $USER. Please run:"
      echo "  sudo chown $USER /dev/$IFNAME"
      exit 1
    fi
  else
    if [[ -z "$IFNAME" ]]; then
      IFNAME="qemu"
    fi
    TAP_IFS=$(ip tuntap show 2>/dev/null)
    if [[ ! "$TAP_IFS" =~ ${IFNAME}: ]]; then
      echo "To use aemu with networking on Linux, configure tun/tap:"
      echo
      echo "sudo ip tuntap add dev $IFNAME mode tap user $USER && \\"
      echo "sudo ip link set $IFNAME up"
      exit 1
    fi
    # Try to detect if a firewall is active. There are only few ways to do that
    # without being root. Unfortunately, using systemd or systemctl does not work
    # (at least on Debian), so use the following hack instead:
    if (command -v ufw && grep -q "^ENABLED=yes" /etc/ufw/ufw.conf) >/dev/null 2>&1; then
      fx-warn "Active firewall detected: If this emulator is unreachable, run: fx setup-ufw"
    fi
  fi
  ARGS+=("-netdev" "type=tap,ifname=$IFNAME,script=$UPSCRIPT,downscript=no,id=net0")
  HASH="$(echo $IFNAME | shasum)"
  SUFFIX=$(for i in {0..2}; do echo -n ":${HASH:$(( 2 * i )):2}"; done)
  MAC=",mac=52:54:00$SUFFIX"
  ARGS+=("-device" "e1000,netdev=net0${MAC}")
else
  ARGS+=("-net" "none")
fi

ARGS+=("-drive" "file=${SYSTEM_FVM},format=raw,if=none,id=vdisk")
ARGS+=("-device" "virtio-blk-pci,drive=vdisk")

# construct the kernel cmd line for aemu
CMDLINE+="kernel.serial=legacy "

# Add entropy to the kernel
CMDLINE+="kernel.entropy-mixin=$(head -c 32 /dev/urandom | shasum -a 256 | awk '{ print $1 }') "

# Don't 'reboot' the emulator if the kernel crashes
CMDLINE+="kernel.halt-on-panic=true "

#end fx emu

set -x
"${AEMU}/emulator" \
  "${OPTIONS[@]}" \
  -fuchsia \
  -kernel "${KERNEL}" \
  -initrd "${INITRD}" \
  "${ARGS[@]}" \
  -append "$CMDLINE" "$@"
