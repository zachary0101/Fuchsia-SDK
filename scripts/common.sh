#!/bin/bash
# Copyright 2019 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

set -eu # Error checking
err_print() {
  echo "Error on line $1"
}
trap 'err_print $LINENO' ERR
DEBUG_LINE() {
    $@
}

BUILD_TOOL_DIR_NAME=buildtools

function get_gn_root(){
  ROOT_DIR="$(pwd)"
  while [[ "${ROOT_DIR}" != "/" ]]; do
    if [[ -f "${ROOT_DIR}/.gn" ]]; then
      break
    fi
    ROOT_DIR="$(dirname ${ROOT_DIR})"
  done
  if [[ "${ROOT_DIR}" == "/" ]]; then
    echo "Error! could not find the root of the project. The current working directory needs to be under the root of the project"
    exit 2
  fi
  echo $ROOT_DIR
}

function get_buildtools_dir(){
  ROOT_DIR=$(get_gn_root)
  BUILD_TOOLS_DIR=$ROOT_DIR/$BUILD_TOOL_DIR_NAME
  if [ BUILD_TOOLS_DIR == "/" ]; then
    echo "Error: build tools directory cannot be \"/\""
    exit 1;
  fi
  echo $BUILD_TOOLS_DIR
}

function get_depot_tools_dir(){
  # Make the host os specific subdir
  # The directory structure is designed to be compatibile with
  # Chromium Depot tools
  # see https://chromium.googlesource.com/chromium/src/+/master/docs/linux_build_instructions.md#install
  case "$(uname -s)" in
    Linux*)   HOST_DIR="linux64";;
    *)        echo "Unsupported host os: $(uname -s)" && exit 1
  esac
  BUILD_TOOLS_DIR=$(get_buildtools_dir)
  echo $BUILD_TOOLS_DIR/$HOST_DIR
}
