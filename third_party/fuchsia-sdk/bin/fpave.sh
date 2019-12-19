#!/bin/bash
# Copyright 2019 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# Command to pave a Fuchsia device.

# note: set -e is not used in order to have custom error handling.
set -u

# Source common functions
SCRIPT_SRC_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)"

# Fuchsia command common functions.
source "${SCRIPT_SRC_DIR}/fuchsia-common.sh" || exit $?

FUCHSIA_SDK_PATH="$(realpath "${SCRIPT_SRC_DIR}/../sdk")"
FUCHSIA_IMAGE_WORK_DIR="$(realpath "${SCRIPT_SRC_DIR}/../images")"
FUCHSIA_BUCKET="${DEFAULT_FUCHSIA_BUCKET}"
IMAGE_NAME="generic-x64"

function usage {
  echo "Usage: $0"
  echo "  [--work-dir <working directory to store image assets>]"
  echo "    Defaults to ${FUCHSIA_IMAGE_WORK_DIR}"
  echo "  [--bucket <fuchsia gsutil bucket>]"
  echo "    Defaults to ${FUCHSIA_BUCKET}"
  echo "  [--image <image name>]"
  echo "    Defaults to ${IMAGE_NAME}"
  echo "  [--authorized-keys <file>]"
  echo "    The authorized public key file for securing the device.  Defaults to "
  echo "    the output of 'ssh-agent -L'"
  echo "  [--private-key <identity file>]"
  echo "    Uses additional rsa private key when using ssh to access the device."
}

PRIVATE_KEY_FILE=""
AUTH_KEYS_FILE=""

# Parse command line
while (( "$#" )); do
case $1 in
    --work-dir)
      shift
      FUCHSIA_IMAGE_WORK_DIR="$1"
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
    --private-key)
      shift
      PRIVATE_KEY_FILE="${1}"
    ;;
    *)
    # unknown option
    fx-error "Unknown option $1"
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

if [[ ! -f "${AUTH_KEYS_FILE}" ]]; then
    AUTH_KEYS_FILE="${FUCHSIA_SDK_PATH}/authkeys.txt"
fi

SDK_ID=$(get-sdk-version "${FUCHSIA_SDK_PATH}")

# Get the device IP address.  If we can't find it, it could be at the zedboot
# page, so it is not fatal.
DEVICE_IP=$(get-device-ip "${FUCHSIA_SDK_PATH}")

# The image tarball.  We add the SDK ID to the filename to make them
# unique.
#
# Consider cleaning up old tarballs when getting a new one?
#
if [[ ! -v  IMAGE_NAME ]]; then
  IMAGES=("$(get-available-images "${SDK_ID}")")
  fx-error "IMAGE_NAME not set. Valid images for this SDK version are:" "${IMAGES[@]}"
  exit 1
fi

FUCHSIA_TARGET_IMAGE="$(get-image-src-path "${SDK_ID}" "${IMAGE_NAME}")"
IMAGE_FILENAME="${SDK_ID}_${IMAGE_NAME}.tgz"

# Validate the image is found
if [[ ! -f "${FUCHSIA_IMAGE_WORK_DIR}/${IMAGE_FILENAME}" ]] ; then
  if ! run-gsutil ls "${FUCHSIA_TARGET_IMAGE}"; then
    echo "Image ${IMAGE_NAME} not found. Valid images for this SDK version are:"
    IMAGES=("$(get-available-images "${SDK_ID}")")
    echo "${IMAGES[@]}"
    exit 2
  fi

  if ! run-gsutil cp "${FUCHSIA_TARGET_IMAGE}" "${FUCHSIA_IMAGE_WORK_DIR}/${IMAGE_FILENAME}"; then
    fx-error "Could not copy image from ${FUCHSIA_TARGET_IMAGE} to ${FUCHSIA_IMAGE_WORK_DIR}/${IMAGE_FILENAME}"
    exit 2
  fi
  if ! rm -rf "${FUCHSIA_IMAGE_WORK_DIR}/image"; then
    fx-error "Could not clean up old image"
    exit 2
  fi
else
  echo "Skipping download, image exists"
fi

  if ! mkdir -p "${FUCHSIA_IMAGE_WORK_DIR}/image"; then
    fx-error "Could not create image directory"
    exit 2
  fi

# if the tarball is not untarred, do it.
if [[ ! -f "${FUCHSIA_IMAGE_WORK_DIR}/image/pave.sh" ]]; then
  if !  tar xzf "${FUCHSIA_IMAGE_WORK_DIR}/${IMAGE_FILENAME}" --directory "${FUCHSIA_IMAGE_WORK_DIR}/image"; then
    fx-error "Could not extract image from ${FUCHSIA_IMAGE_WORK_DIR}/${IMAGE_FILENAME}"
    exit 1
  fi
fi

if [[ ! -f "${AUTH_KEYS_FILE}" ]]; then
  # Store the SSL auth keys to a file for sending to the device.
  if ! ssh-add -L > "${AUTH_KEYS_FILE}"; then
    fx-error "Cannot determine authorized keys: $(cat "${AUTH_KEYS_FILE}")"
    exit 1
  fi
fi

if [[ ! "$(wc -l < "${AUTH_KEYS_FILE}")" -ge 1 ]]; then
  fx-error "Cannot determine authorized keys: $(cat "${AUTH_KEYS_FILE}")"
  exit 2
fi

PRIVATE_KEY_ARG=""
if [[ "${PRIVATE_KEY_FILE}" != "" ]]; then
  PRIVATE_KEY_ARG="-i ${PRIVATE_KEY_FILE}"
fi

if [[ -n "${DEVICE_IP}" ]]; then
    ssh-cmd "${PRIVATE_KEY_ARG}" "${DEVICE_IP}" dm reboot-recovery
    fx-warn "Confirm device is rebooting into recovery mode.  Paving may fail if device is not in Zedboot"
else
    fx-warn "Device not detected.  Make sure the device is connected and at the 'Zedboot' screen."
fi

PAVE_CMD=("${FUCHSIA_IMAGE_WORK_DIR}/image/pave.sh" "--authorized-keys" "${AUTH_KEYS_FILE}" "-1")
if ! "${PAVE_CMD[@]}"; then
  # Currently there is a bug on the first attempt of paving, so retry.
  sleep .33
  if ! "${PAVE_CMD[@]}"; then
    exit 2
  fi
fi

