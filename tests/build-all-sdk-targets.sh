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
    "$@"
}

TEST_SRC_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Common functions.
source "${TEST_SRC_DIR}/../scripts/common.sh" || exit $?
REPO_ROOT=$(get_gn_root) # finds path to REPO_ROOT
DEPOT_TOOLS_DIR=$(get_depot_tools_dir) # finds path to DEPOT_TOOLS_DIR

OUT_DIRS=( 'out/arm64' 'out/x64' )

for DIR in "${OUT_DIRS[@]}"; do
  echo "==== Building all Fuchsia SDK targets in ${DIR} ===="
  "${DEPOT_TOOLS_DIR}/ninja" -C "${REPO_ROOT}/${DIR}" third_party/fuchsia-sdk:all_fidl_targets
done