#!/bin/bash
# Copyright 2019 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# Helper functions, no environment specific functions should be included below
# this line.

DEFAULT_FUCHSIA_BUCKET="fuchsia"

# fx-warn prints a line to stderr with a yellow WARNING: prefix.
function fx-warn () {
  if [[ -t 2 ]]; then
    echo -e >&2 "\033[1;33mWARNING:\033[0m $@"
  else
    echo -e >&2 "WARNING: $@"
  fi
}

# fx-error prints a line to stderr with a red ERROR: prefix.
function fx-error {
  if [[ -t 2 ]]; then
    echo -e >&2 "\033[1;31mERROR:\033[0m $@"
  else
    echo -e >&2 "ERROR: $@"
  fi
}

function configure-ssh {
  # $1 is "${PRIVATE_KEY_FILE}"
  local SSH_ARGS=('ssh')
  SSH_ARGS+=('-o' 'StrictHostKeyChecking=no'
            '-o' 'UserKnownHostsFile=/dev/null'
            '-o' 'ConnectTimeout=1'
            '-o' 'ServerAliveInterval=1'
            '-o' 'ControlPersist=yes'
            '-o' 'ControlMaster=auto'
            '-o' 'ControlPath=/tmp/fuchsia--%r@%h:%p'
            )
  if [[ -n "${1}" ]]; then
    SSH_ARGS+=("-i" "${1}")
  fi
  echo "${SSH_ARGS[@]}"
}


function ssh_cmd() {
  # Configure the SSH command
  local SSH_ARGS=('ssh')
  SSH_ARGS+=('-o' 'StrictHostKeyChecking=no'
            '-o' 'UserKnownHostsFile=/dev/null'
            '-o' 'ConnectTimeout=1'
            '-o' 'ServerAliveInterval=1'
            '-o' 'ControlPersist=yes'
            '-o' 'ControlMaster=auto'
            '-o' 'ControlPath=/tmp/fuchsia--%r@%h:%p'
            )
  echo "${SSH_ARGS[@]}"
}

function get_device_ip() {
  local DEVICE_IP=$("${FUCHSIA_SDK_PATH}/tools/dev_finder" "list" "-netboot" "-device-limit" "1")
  if [[ $? -ne 0 ]]; then
    fx-error "Error finding device"
    echo ""
  else
    echo "${DEVICE_IP}"
  fi
}

function get_device_name() {
  # $1 is the SDK_PATH.
  local DEVICE_NAME=$("${1}/tools/dev_finder" list -netboot -device-limit 1 -full | cut -d\  -f2)
  if [[ $? -ne 0 ]]; then
    fx-error "Error finding device"
    echo ""
  else
    echo "${DEVICE_NAME}"
  fi
}

function get_host_ip() {
  # $1 is the SDK_PATH.
  local DEVICE_NAME=$(get_device_name "${1}")
  local HOST_IP=$("${1}/tools/dev_finder" resolve -local "${DEVICE_NAME}" | head -1)
  if [[ $? -ne 0 ]]; then
    fx-error "Error finding device"
    echo ""
  else
    echo "${HOST_IP}"
  fi
}

function get_sdk_version() {
# Get the Fuchsia SDK id
# $1 is the SDK_PATH.
  local FUCHSIA_SDK_METADATA="${1}/meta/manifest.json"
  local SDK_ID=$(grep \"id\": "${FUCHSIA_SDK_METADATA}" | cut -d\" -f4)
  echo "${SDK_ID}"
}

function get_package_src_path() {
  # $1 is the SDK ID.  See #get_sdk_version.
  # $2 is the image name.
  local FUCHSIA_TARGET_IMAGE="gs://${FUCHSIA_BUCKET}/development/${1}/packages/${2}.tar.gz"
  echo "${FUCHSIA_TARGET_IMAGE}"
}

function get_image_src_path() {
  # $1 is the SDK ID.  See #get_sdk_version.
  # $2 is the image name.
  local FUCHSIA_TARGET_IMAGE="gs://${FUCHSIA_BUCKET}/development/${1}/images/${2}.tgz"
  echo "${FUCHSIA_TARGET_IMAGE}"
}

# Run gsutil from a symlink in the directory of this script if exists, otherwise
# use the path.
function run_gsutil() {
  GSUTIL_BIN="$(dirname ${BASH_SOURCE[0]})/gsutil"
  if [[ ! -e "${GSUTIL_BIN}" ]]; then
    GSUTIL_BIN="$(which gsutil)"
  fi

  if [[ "${GSUTIL_BIN}" == "" ]]; then
    fx-error "Cannot find gsutil. Add to path or symlink in $(dirname ${BASH_SOURCE[0]})"
    exit 2
  fi
  "${GSUTIL_BIN}" "$@"
}

function get_available_images() {
  # $1 is the SDK ID.
  local IMAGES=()
  for f in $(run_gsutil "ls" "gs://${FUCHSIA_BUCKET}/development/${1}/images" | cut -d/ -f7)
  do
    IMAGES+=("${f%.*}")
  done
  if [[ "${FUCHSIA_BUCKET}" != "${DEFAULT_FUCHSIA_BUCKET}" ]]; then
      for f in $(run_gsutil "ls" "gs://${DEFAULT_FUCHSIA_BUCKET}/development/${1}/images" | cut -d/ -f7)
      do
        IMAGES+=("${f%.*}")
      done
  fi
  echo "${IMAGES[@]}"
}

function kill_running_pm() {
  local PM_PROCESS=($(pgrep -a pm))
  if [[ -n "${PM_PROCESS[@]}" ]]; then
    if [[ "${PM_PROCESS[1]}" == *"tools/pm" ]]; then
      fx-warn "Killing existing pm process"
      kill "${PM_PROCESS[0]}"
      return $?
    fi
  else
    fx-warn "existing pm process not found"
  fi
  return 0
}


