#!/bin/bash
# Copyright 2019 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# Helper functions, no environment specific functions should be included below
# this line.

SCRIPT_SRC_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)"
DEFAULT_FUCHSIA_BUCKET="fuchsia"

# fx-warn prints a line to stderr with a yellow WARNING: prefix.
function fx-warn {
  if [[ -t 2 ]]; then
    echo -e >&2 "\033[1;33mWARNING:\033[0m $*"
  else
    echo -e >&2 "WARNING: $*"
  fi
}

# fx-error prints a line to stderr with a red ERROR: prefix.
function fx-error {
  if [[ -t 2 ]]; then
    echo -e >&2 "\033[1;31mERROR:\033[0m $*"
  else
    echo -e >&2 "ERROR: $*"
  fi
}

function ssh-cmd {
  # Run SSH command. We use unquoted $@ here so splitting globbing works as expected.
  # shellcheck disable=SC2068
  ssh -F "${SCRIPT_SRC_DIR}/sshconfig" $@
}

function get-device-ip {
  "${1}/tools/dev_finder" "list" "-netboot" "-device-limit" "1"
}

function get-device-name {
  # $1 is the SDK_PATH.
  "${1}/tools/dev_finder" list -netboot -device-limit 1 -full | cut -d\  -f2
}

function get-host-ip {
  # $1 is the SDK_PATH.
  local DEVICE_NAME
  DEVICE_NAME=$(get-device-name "${1}")
  "${1}/tools/dev_finder" resolve -local "${DEVICE_NAME}" | head -1
}

function get-sdk-version {
# Get the Fuchsia SDK id
# $1 is the SDK_PATH.
  local FUCHSIA_SDK_METADATA="${1}/meta/manifest.json"
  grep \"id\": "${FUCHSIA_SDK_METADATA}" | cut -d\" -f4
}

function get-package-src-path {
  # $1 is the SDK ID.  See #get-sdk-version.
  # $2 is the image name.
  echo "gs://${FUCHSIA_BUCKET}/development/${1}/packages/${2}.tar.gz"
}

function get-image-src-path {
  # $1 is the SDK ID.  See #get-sdk-version.
  # $2 is the image name.
  echo "gs://${FUCHSIA_BUCKET}/development/${1}/images/${2}.tgz"
}

# Run gsutil from a symlink in the directory of this script if exists, otherwise
# use the path.
function run-gsutil {
  GSUTIL_BIN="${SCRIPT_SRC_DIR}/gsutil"
  if [[ ! -e "${GSUTIL_BIN}" ]]; then
    GSUTIL_BIN="$(command -v gsutil)"
  fi

  if [[ "${GSUTIL_BIN}" == "" ]]; then
    fx-error "Cannot find gsutil."
    exit 2
  fi
  "${GSUTIL_BIN}" "$@"
}

function get-available-images {
  # $1 is the SDK ID.
  local IMAGES=()
  for f in $(run-gsutil "ls" "gs://${FUCHSIA_BUCKET}/development/${1}/images" | cut -d/ -f7)
  do
    IMAGES+=("${f%.*}")
  done
  if [[ "${FUCHSIA_BUCKET}" != "${DEFAULT_FUCHSIA_BUCKET}" ]]; then
      for f in $(run-gsutil "ls" "gs://${DEFAULT_FUCHSIA_BUCKET}/development/${1}/images" | cut -d/ -f7)
      do
        IMAGES+=("${f%.*}")
      done
  fi
  echo "${IMAGES[@]}"
}

function kill-running-pm {
  local PM_PROCESS=()
  IFS=" " read -r -a PM_PROCESS <<< "$(pgrep -ax pm)"
  if [[ -n "${PM_PROCESS[*]}" ]]; then
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


