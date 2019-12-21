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

FUCHSIA_SERVER_PORT="8083"
IMAGE_NAME="generic-x64"
usage () {
  echo "Usage: $0"
  echo "  [--tool-home <directory to store image assets>]"
  echo "    Defaults to ${FUCHSIA_IMAGE_WORK_DIR}"
  echo "  [--bucket <fuchsia gsutil bucket>]"
  echo "    Defaults to ${FUCHSIA_BUCKET}"
  echo "  [--image <image name>]"
  echo "    Defaults to ${IMAGE_NAME}"
  echo "  [--private-key <identity file>]"
  echo "    Uses additional rsa private key when using ssh to access the device."
  echo "  [--server-port <port>]"
  echo "    Port number to use when serving the packages.  Defaults to ${FUCHSIA_SERVER_PORT}."
  echo "  [--kill]"
  echo "    Kills any existing package manager server"
}
PRIVATE_KEY_FILE=""
# Parse command line
while (( "$#" )); do
case $1 in
    --work-dir)
    shift
    FUCHSIA_IMAGE_WORK_DIR="${1}"
    ;;
    --bucket)
    shift
    FUCHSIA_BUCKET="${1}"
    ;;
    --image)
    shift
    IMAGE_NAME="${1}"
    ;;
    --private-key)
    shift
    PRIVATE_KEY_FILE="${1}"
    ;;
    --server-port)
    shift
    FUCHSIA_SERVER_PORT="${1}"
    ;;
    --kill)
    kill-running-pm
    exit 0
    ;;
    *)
    # unknown option
    usage
    exit 1
    ;;
esac
shift
done

# Check for core SDK being present
if [[ ! -d "${FUCHSIA_SDK_PATH}" ]]; then
  fx-error "Fuchsia Core SDK not found at ${FUCHSIA_SDK_PATH}."
  exit 2
fi

SDK_ID=$(get-sdk-version "${FUCHSIA_SDK_PATH}")

# Get the device IP address.
DEVICE_IP=$(get-device-ip "${FUCHSIA_SDK_PATH}")
HOST_IP=$(get-host-ip "${FUCHSIA_SDK_PATH}")

# The package tarball.  We add the SDK ID to the filename to make them
# unique.
#
# Consider cleaning up old tarballs when getting a new one?
#
if [[ ! -v  IMAGE_NAME ]]; then
  IMAGES=("$(get-available-images "${SDK_ID}")")
  fx-error "IMAGE_NAME not set. Valid images for this SDK version are:" "${IMAGES[@]}"
  exit 1
fi

FUCHSIA_TARGET_PACKAGES=$(get-package-src-path "${SDK_ID}" "${IMAGE_NAME}")
IMAGE_FILENAME="${SDK_ID}_${IMAGE_NAME}.tar.gz"

# Validate the image is found
if [[ ! -f "${FUCHSIA_IMAGE_WORK_DIR}/${IMAGE_FILENAME}" ]] ; then
  if ! run-gsutil ls "${FUCHSIA_TARGET_PACKAGES}"; then
    echo "Packages for ${IMAGE_NAME} not found. Valid images for this SDK version are:"
    IMAGES=("$(get-available-images "${SDK_ID}")")
    echo "${IMAGES[@]}"
    exit 2
  fi

  if ! run-gsutil cp "${FUCHSIA_TARGET_PACKAGES}" "${FUCHSIA_IMAGE_WORK_DIR}/${IMAGE_FILENAME}"; then
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
kill-running-pm

# Start the package server
echo "** Starting package server in the background**"
# `:port` syntax is valid for Go programs that intend to serve on every
# interface on a given port. For example, if $FUCHSIA_SERVER_PORT is 54321,
# this is similar to serving on [::]:54321 or 0.0.0.0:54321.
"${FUCHSIA_SDK_PATH}/tools/pm" serve -repo "${FUCHSIA_IMAGE_WORK_DIR}/packages/amber-files" -l ":${FUCHSIA_SERVER_PORT}"&

PRIVATE_KEY_ARG=""
if [[ "${PRIVATE_KEY_FILE}" != "" ]]; then
  PRIVATE_KEY_ARG="-i ${PRIVATE_KEY_FILE}"
fi

# Update the device to point to the server
# Because the URL to config.json contains an IPv6 address, the address needs
# to be escaped in square brackets. This is not necessary for the ssh target,
# since that's just an address and not a full URL.
if ! ssh-cmd "${PRIVATE_KEY_ARG}" "${DEVICE_IP}" amber_ctl add_src -f "http://[${HOST_IP}]:$FUCHSIA_SERVER_PORT/config.json"; then
  echo "Error: could not update device"
fi
