#!/bin/bash
# Copyright 2020 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Enable error checking for all commands
err_print() {
  echo "Error at $1"
  stty sane
}
trap 'err_print $0:$LINENO' ERR
set -e

SCRIPT_SRC_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)"
source "${SCRIPT_SRC_DIR}/fuchsia-common.sh" || exit $?

export FUCHSIA_SDK_PATH="$(realpath "${SCRIPT_SRC_DIR}/..")"
export FUCHSIA_IMAGE_WORK_DIR="$(realpath "${SCRIPT_SRC_DIR}/../images")"

usage () {
  echo "Usage: $0"
  echo "  [--work-dir <directory to store image assets>]"
  echo "    Defaults to ${FUCHSIA_IMAGE_WORK_DIR}"
  echo "  [--authorized-keys <file>]"
  echo "    The authorized public key file for securing the device.  Defaults to "
  echo "    the output of 'ssh-add -L'"
}
AUTH_KEYS_FILE=""
FDT_ARGS=()

# Parse command line
while (( "$#" )); do
case $1 in
  --work-dir)
    shift
    FUCHSIA_IMAGE_WORK_DIR="${1:-.}"
    ;;
  --authorized-keys)
    shift
    AUTH_KEYS_FILE="${1}"
    ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    # Unknown options are passed to Fuchsia DevTools
    FDT_ARGS+=( "$1" )
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
  if [[ "${AUTH_KEYS_FILE}" == "" ]]; then
    AUTH_KEYS_FILE="${FUCHSIA_SDK_PATH}/authkeys.txt"
    # Store the SSL auth keys to a file for sending to the device.
    if ! ssh-add -L > "${AUTH_KEYS_FILE}"; then
      fx-error "Cannot determine authorized keys: $(cat "${AUTH_KEYS_FILE}")."
      exit 1
    fi
  else
    fx-error "Argument --authorized-keys was specified as ${AUTH_KEYS_FILE} but it does not exist"
    exit 1
  fi
fi

if [[ ! "$(wc -l < "${AUTH_KEYS_FILE}")" -ge 1 ]]; then
  fx-error "Cannot determine authorized keys: $(cat "${AUTH_KEYS_FILE}")."
  exit 2
fi

# Can download Fuchsia DevTools from CIPD with either "latest" or a CIPD hash
echo "Downloading latest Fuchsia DevTools with CIPD"
FDT_VERSION="latest"
TEMP_ENSURE=$(mktemp /tmp/fuchsia_devtools_cipd_XXXXXX.ensure)
cat << end > "${TEMP_ENSURE}"
\$ServiceURL https://chrome-infra-packages.appspot.com/
fuchsia_internal/gui_tools/fuchsia_devtools/\${platform} $FDT_VERSION
end

FDT_DIR="${FUCHSIA_IMAGE_WORK_DIR}/fuchsia_devtools"
if ! $(run-cipd ensure -ensure-file "${TEMP_ENSURE}" -root "${FDT_DIR}"); then
  rm "$TEMP_ENSURE"
  echo "Failed to download Fuchsia DevTools ${FDT_VERSION}."
  exit 1
fi
rm "${TEMP_ENSURE}"

export FDT_TOOLCHAIN="GN"
export FDT_GN_SSH="$(command -v ssh)"
export FDT_SSH_CONFIG="${SCRIPT_SRC_DIR}/sshconfig"
export FDT_SSH_KEY="${AUTH_KEYS_FILE}"
export FDT_GN_DEVFIND="${FUCHSIA_SDK_PATH}/tools/device-finder"
export FDT_DEBUG="true"
echo "Starting system_monitor with FDT_ARGS=[${FDT_ARGS[*]}] and FDT_DIR=${FDT_DIR}, FDT_TOOLCHAIN=${FDT_TOOLCHAIN}, FDT_GN_SSH=${FDT_GN_SSH}, FDT_SSH_CONFIG=${FDT_SSH_CONFIG}, FDT_SSH_KEY=${FDT_SSH_KEY}, FDT_GN_DEVFIND=${FDT_GN_DEVFIND}, FDT_DEBUG=${FDT_DEBUG}"
"${FDT_DIR}/system_monitor/linux/system_monitor" "${FDT_ARGS[@]}"
