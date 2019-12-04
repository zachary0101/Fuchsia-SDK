#!/bin/bash
# Copyright 2019 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

set -u

SCRIPT_SRC_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)"

# Fuchsia command common functions.
source "${SCRIPT_SRC_DIR}/fuchsia-common.sh" || exit $?

FUCHSIA_SDK_PATH="$(realpath ${SCRIPT_SRC_DIR}/../sdk)"
FUCHSIA_IMAGE_WORK_DIR="$(realpath ${SCRIPT_SRC_DIR}/../images)"
FUCHSIA_BUCKET="${DEFAULT_FUCHSIA_BUCKET}"

FUCHSIA_SERVER_PORT="8083"
IMAGE_NAME="generic-x64"
usage () {
  echo "Usage: $0"
  echo "  [--tool-home=<directory to store image assets>]"
  echo "    Defaults to ${FUCHSIA_IMAGE_WORK_DIR}"
  echo "  [--sdk-path=<fuchsia sdk path>]"
  echo "    Defaults to ${FUCHSIA_SDK_PATH}"
  echo "  [--bucket=<fuchsia gsutil bucket>]"
  echo "    Defaults to ${FUCHSIA_BUCKET}"
  echo "  [--image=<image name>]"
  echo "    Defaults to ${IMAGE_NAME}"
  echo "  [--private-key=<identity file>]"
  echo "    Uses additional rsa private key when using ssh to access the device."
  echo "  [--server-port=<port>]"
  echo "    Port number to use when serving the packages.  Defaults to ${FUCHSIA_SERVER_PORT}."
  echo "  [--kill]"
  echo "    Kills any existing package manager server"
}
PRIVATE_KEY_FILE=""
# Parse command line
for i in "$@"
do
case $i in
    -w=*|--work-dir=*)
    FUCHSIA_IMAGE_WORK_DIR="${i#*=}"
    ;;
    -s=*|--sdk-path=*)
    FUCHSIA_SDK_PATH="${i#*=}"
    ;;
    --bucket=*)
    FUCHSIA_BUCKET="${i#*=}"
    ;;
    --image=*)
    IMAGE_NAME="${i#*=}"
    ;;
    --private-key=*)
    PRIVATE_KEY_FILE="${i#*=}"
    ;;
    --server-port=*)
    FUCHSIA_SERVER_PORT="${i#*=}"
    ;;
    --kill)
    exit $(kill_running_pm)
    ;;
    *)
    # unknown option
    usage
    exit 1
    ;;
esac
done

# Check for core SDK being present
if [[ ! -d "${FUCHSIA_SDK_PATH}" ]]; then
  fx-error "Fuchsia Core SDK not found at ${FUCHSIA_SDK_PATH}."
  exit 2
fi


# Configure the SSH command
SSH_ARGS=$(configure-ssh "${PRIVATE_KEY_FILE}")

SDK_ID=$(get_sdk_version "${FUCHSIA_SDK_PATH}")

# Get the device IP address.
DEVICE_IP=$(get_device_ip "${FUCHSIA_SDK_PATH}")
DEVICE_NAME=$(get_device_name "${FUCHSIA_SDK_PATH}")
HOST_IP=$(get_host_ip "${FUCHSIA_SDK_PATH}")

kill_child_processes() {
  child_pids=$(jobs -p)
  if [[ -n "${child_pids}" ]]; then
    # Note: child_pids must be expanded to args here.
    kill ${child_pids} 2> /dev/null
    wait 2> /dev/null
  fi
}
trap kill_child_processes EXIT

# The package tarball.  We add the SDK ID to the filename to make them
# unique.
#
# Consider cleaning up old tarballs when getting a new one?
#
if [[ ! -v  IMAGE_NAME ]]; then
  IMAGES=("$(get_available_images "${SDK_ID}")")
  fx-error "IMAGE_NAME not set. Valid images for this SDK version are:" "${IMAGES[@]}"
  exit 1
fi

FUCHSIA_TARGET_PACKAGES=$(get_package_src_path "${SDK_ID}" "${IMAGE_NAME}")
IMAGE_FILENAME="${SDK_ID}_${IMAGE_NAME}.tar.gz"

# Validate the image is found
if [[ ! -f "${FUCHSIA_IMAGE_WORK_DIR}/${IMAGE_FILENAME}" ]] ; then
  if ! run_gsutil ls "${FUCHSIA_TARGET_PACKAGES}"; then
    echo "Packages for ${IMAGE_NAME} not found. Valid images for this SDK version are:"
    IMAGES=("$(get_available_images "${SDK_ID}")")
    echo "${IMAGES[@]}"
    exit 2
  fi

  if ! run_gsutil cp "${FUCHSIA_TARGET_PACKAGES}" "${FUCHSIA_IMAGE_WORK_DIR}/${IMAGE_FILENAME}"; then
    fx-error "Could not copy image from ${FUCHSIA_TARGET_PACKAGES} to ${FUCHSIA_IMAGE_WORK_DIR}/${IMAGE_FILENAME}"
    exit 2
  fi
  if ! rm -rf "${FUCHSIA_IMAGE_WORK_DIR}/packages"; then
    fx-error "Could not clean up old image"
    exit 2
  fi
else
  echo "Skipping download, packages tarball exists"
fi

  if ! mkdir -p "${FUCHSIA_IMAGE_WORK_DIR}/packages"; then
    fx-error "Could not create packages directory"
    exit 2
  fi

# if the tarball is not untarred, do it.
if [[ ! -d "${FUCHSIA_IMAGE_WORK_DIR}/packages/amber-files" ]]; then
  if ! tar xzf "${FUCHSIA_IMAGE_WORK_DIR}/${IMAGE_FILENAME}" --directory "${FUCHSIA_IMAGE_WORK_DIR}/packages"; then
    fx-error "Could not extract image from ${FUCHSIA_IMAGE_WORK_DIR}/${IMAGE_FILENAME}"
    exit 1
  fi
fi

# kill existing pm if present
$(kill_running_pm)

# Start the package server
echo "** Starting package server in the background**"
"${FUCHSIA_SDK_PATH}/tools/pm" serve -repo "${FUCHSIA_IMAGE_WORK_DIR}/packages/amber-files" -l "${HOST_IP}:${FUCHSIA_SERVER_PORT}"&
serve_pid=$!

# Update the device to point to the server
if ! ${SSH_ARGS[@]} "${DEVICE_IP}" amber_ctl add_src -f "http://${HOST_IP}:${FUCHSIA_SERVER_PORT}/config.json"; then
  echo "Error: could not update device"
fi

while true; do
  sleep 1

  if ! kill -0 ${serve_pid} 2> /dev/null; then
      exit
  fi
done


