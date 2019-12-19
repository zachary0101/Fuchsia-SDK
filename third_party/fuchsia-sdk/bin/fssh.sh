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

FUCHSIA_SDK_PATH="$(realpath "${SCRIPT_SRC_DIR}/../sdk")"

function usage {
  echo "Usage: $0"
  echo "  [--private-key <identity file>]"
  echo "    Uses additional rsa private key when using ssh to access the device."
}

PRIVATE_KEY_FILE=""
declare -a POSITIONAL

# Parse command line
while (( "$#" )); do
case $1 in
    --private-key)
    shift
    PRIVATE_KEY_FILE="${1}"
    ;;
    -*)
    if [[ "${#POSITIONAL[@]}" -eq 0 ]]; then
      echo "Unknown option ${1}"
      usage
      exit 1
    else
      POSITIONAL+=("${1}")
    fi
    ;;
    *)
      POSITIONAL+=("${1}")
    ;;
esac
shift
done

# Check for core SDK being present
if [[ ! -d "${FUCHSIA_SDK_PATH}" ]]; then
  fx-error "Fuchsia Core SDK not found at ${FUCHSIA_SDK_PATH}."
  exit 2
fi

# Get the device IP address.
DEVICE_IP="$(get-device-ip "${FUCHSIA_SDK_PATH}")"
if [[ -z ${DEVICE_IP} ]]; then
  fx-error "Error finding device"
  exit 2
fi

PRIVATE_KEY_ARG=""
if [[ "${PRIVATE_KEY_FILE}" != "" ]]; then
  PRIVATE_KEY_ARG="-i ${PRIVATE_KEY_FILE}"
fi

ssh-cmd "${PRIVATE_KEY_ARG}" "${DEVICE_IP}" "${POSITIONAL[@]}"
