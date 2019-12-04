#!/bin/bash
# Copyright 2019 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.
#
# Command to publish a package to make is accessible to a Fuchsia device.

# note: set -e is not used in order to have custom error handling.
set -u

# Source common functions
SCRIPT_SRC_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)"

# Fuchsia command common functions.
source "${SCRIPT_SRC_DIR}/fuchsia-common.sh" || exit $?

FUCHSIA_SDK_PATH="$(realpath ${SCRIPT_SRC_DIR}/../sdk)"
FUCHSIA_IMAGE_WORK_DIR="$(realpath ${SCRIPT_SRC_DIR}/../images)"


usage () {
  echo "Usage: $0 <files.far>"
  echo "  [--tool-home=<directory to store image assets>]"
  echo "    Defaults to ${FUCHSIA_IMAGE_WORK_DIR}"
  echo "  [--sdk-path=<fuchsia sdk path>]"
  echo "    Defaults to ${FUCHSIA_SDK_PATH}"
}

POSITIONAL=()

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

"${FUCHSIA_SDK_PATH}/tools/pm" publish  -a -r "${FUCHSIA_IMAGE_WORK_DIR}/packages/amber-files" -f "${POSITIONAL[@]}";
