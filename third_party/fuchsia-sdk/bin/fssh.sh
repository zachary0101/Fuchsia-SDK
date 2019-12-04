#!/bin/bash
# Copyright 2019 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# Command to SSH to a Fuchsia device.
set -eu

# Source common functions
SCRIPT_SRC_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)"

# Fuchsia command common functions.
source "${SCRIPT_SRC_DIR}/fuchsia-common.sh" || exit $?

FUCHSIA_SDK_PATH="$(realpath ${SCRIPT_SRC_DIR}/../sdk)"
FUCHSIA_IMAGE_WORK_DIR="$(realpath ${SCRIPT_SRC_DIR}/../images)"


function usage {
  echo "Usage: $0"
  echo "  [--sdk-path=<fuchsia sdk path>]"
  echo "    Defaults to ${FUCHSIA_SDK_PATH}"
  echo "  [--private-key=<identity file>]"
  echo "    Uses additional rsa private key when using ssh to access the device."
}

PRIVATE_KEY_FILE=""
declare -a POSITIONAL

# Parse command line
for i in "$@"
do
case $i in
    -s=*|--sdk-path=*)
    FUCHSIA_SDK_PATH="${i#*=}"
    ;;
    --private-key=*)
    PRIVATE_KEY_FILE="${i#*=}"
    ;;
    -*)
    if [[ "${#POSITIONAL[@]}" -eq 0 ]]; then
      echo "Unknown option ${i}"
      usage
      exit 1
    else
      POSITIONAL+=("${i}")
    fi
    ;;
    *)
      POSITIONAL+=("${i}")
    ;;
esac
done

# Check for core SDK being present
if [[ ! -d "${FUCHSIA_SDK_PATH}" ]]; then
  fx-error "Fuchsia Core SDK not found at ${FUCHSIA_SDK_PATH}."
  exit 2
fi

# Get the device IP address.
DEVICE_IP="$(get_device_ip "${FUCHSIA_SDK_PATH}")"
if [[ -z ${DEVICE_IP} ]]; then
  fx-error "Error finding device"
  exit 2
fi

# Configure the SSH command
SSH_ARGS="$(configure-ssh "${PRIVATE_KEY_FILE}")"

${SSH_ARGS[@]} "${DEVICE_IP}" "${POSITIONAL[@]}"
