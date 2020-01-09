#!/bin/bash
# Copyright 2019 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# This is a test script that can be run inside femu-exec-wrapper.sh or on a local device
# It verifies that the system image has basic functionality and that it works as expected

set -eu # Error checking
err_print() {
  echo "Error on line $1"
}
trap 'err_print $LINENO' ERR
DEBUG_LINE() {
    "$@"
}

TEST_SRC_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
SDK_BIN_DIR="${TEST_SRC_DIR}/../third_party/fuchsia-sdk/bin"

ERROR_COUNT="0"
ERROR_LIST=""

# Check that a remote command can run and check the exit code, it should not block for longer than $TIMEOUT seconds
function wait_command {
  echo "Running wait_command: $*"
  RESULT=0
  TIMEOUT=10s
  timeout "$TIMEOUT" "${SDK_BIN_DIR}/fssh.sh" "${@}" || RESULT="$?"
  if [ "${RESULT}" == "0" ]; then
    echo "OK: $*"
  elif [ "${RESULT}" == "124" ]; then
    echo "TIMEOUT: Did not reach exit of command: $*"
  else
    echo "ERROR: Result ${RESULT} for $*"
    ERROR_COUNT=$((ERROR_COUNT+1))
    ERROR_LIST="${ERROR_LIST} \"$*\""
  fi
}

# Useful for remote commands that never normally terminate, just check that they run for a while without exiting
function timeout_command {
  TIMEOUT="$1"
  shift
  echo "Running timeout_command for $TIMEOUT: $*"
  RESULT=0
  timeout "${TIMEOUT}" "${SDK_BIN_DIR}/fssh.sh" "${@}" || RESULT="$?"
  if [ "${RESULT}" == "0" ]; then
    echo "ERROR: Exited with 0 but was expecting to wait"
  elif [ "${RESULT}" == "124" ]; then
    # This is the expected result if the timeout command terminates the shell
    echo "OK: $*"
  else
    echo "ERROR: Result ${RESULT} for command: $*"
    ERROR_COUNT=$((ERROR_COUNT+1))
    ERROR_LIST="${ERROR_LIST} \"$*\""
  fi

}

# Check if tiles_ctl is running
wait_command tiles_ctl list
# Run some basic Fuchsia commands
wait_command echo hello
wait_command date
# Check if the web view is working
wait_command present_view "https://fuchsia.dev"

if [ "${ERROR_COUNT}" == "0" ]; then
  echo "OK: All tests passed!"
else
  echo "ERROR: ${ERROR_COUNT} tests failed, see log output"
  echo "ERROR: List${ERROR_LIST}"
  exit 1
fi
