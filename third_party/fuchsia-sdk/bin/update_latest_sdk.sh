#!/bin/bash
# Copyright 2019 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# Source common functions
SCRIPT_SRC_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)"

# Fuchsia command common functions.
source "${SCRIPT_SRC_DIR}/fuchsia-common.sh" || exit $?


LATEST_ARCHIVE="$(run_gsutil cp gs://fuchsia/sdk/core/linux-amd64/LATEST_ARCHIVE -)"
echo "Found latest SDK version $LATEST_ARCHIVE, writing to linux.sdk.sha1"
echo $LATEST_ARCHIVE > "${SCRIPT_SRC_DIR}/../linux.sdk.sha1"
