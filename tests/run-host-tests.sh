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

TEST_SRC_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Common functions.
source "${TEST_SRC_DIR}/../scripts/common.sh" || exit $?
REPO_ROOT=$(get_gn_root) # finds path to REPO_ROOT

echo
echo "==== Run host tests ===="
for dir in `ls out`; do
  for i in `cat out/$dir/all_host_tests.txt`; do
    out/$dir/$i
  done
done

echo
echo "Success!"
