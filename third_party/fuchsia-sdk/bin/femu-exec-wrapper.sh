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

SCRIPT_SRC_DIR="$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)"
source "${SCRIPT_SRC_DIR}/fuchsia-common.sh" || exit $?

# This is only used after femu.sh has been started
function cleanup {
  echo "Cleaning up femu pid $FEMU_PID, qemu child processes, and package server for exit ..."
  # The qemu child needs to be terminated separately since it is detached from the script
  kill $(ps -o pid= --ppid "${FEMU_PID}") &> /dev/null
  kill "${FEMU_PID}" &> /dev/null
  "${SCRIPT_SRC_DIR}/fserve.sh" --kill &> /dev/null
}

HEADLESS=""
INTERACTIVE=""
EXEC_SCRIPT=""
IMAGE_NAME="qemu-x64"
FEMU_LOG="/dev/null"

function usage() {
  echo "Usage: $0"
  echo
  echo "  Starts up femu.sh, runs a script, captures the result, and terminates the emulator"
  echo
  echo "  [--exec <script>]"
  echo "    Executes the specified script or command that can access the emulator"
  echo "  [--femu-log <file>]"
  echo "    Writes femu output to log file, can also be /dev/null or /dev/stdout"
  echo "    Default log output is ${FEMU_LOG}"
  echo "  [--headless]"
  echo "    Do not use any graphics support, do not open any new windows"
  echo "  [--interactive]"
  echo "    Opens up xterm window with femu serial console"
  echo "  [--image <name>]"
  echo "    System image to use with femu.sh, defaults to ${IMAGE_NAME}"
  echo
  echo "  All other arguments are passed on, see femu.sh --help for more info"
}

# Check for some of the emu flags, but pass everything else on to femu.sh
while (( "$#" )); do
case $1 in
  --help|-h)
    usage
    exit 0
    ;;
  --headless)
    HEADLESS="yes"
    ;;
  --interactive)
    INTERACTIVE="yes"
    ;;
  --exec)
    shift
    EXEC_SCRIPT="${1}"
    ;;
  --femu-log)
    shift
    FEMU_LOG="${1}"
    ;;
  --image)
    shift
    IMAGE_NAME="${1}"
    ;;
  *)
    # Everything else is passed on to the emulator
    EMU_ARGS+=( "${1}" )
    ;;
esac
shift
done

# This IPv6 address is always generated according to the hash of the qemu network interface in femu.sh
EMULATOR_ADDRESS="fe80::5054:ff:fe63:5e7a%qemu"

# Always start with -N for SSH access to the emulator
echo "Starting emulator"
if [[ "${INTERACTIVE}" == "yes" ]]; then
  if [[ "${FEMU_LOG}" != "" && "${FEMU_LOG}" != "/dev/null" ]]; then
    fx-error "--interactive does not write to --femu-log"
    exit 1
  fi
  # Start up the emulator in the background within a new window, useful for interactive debugging
  xterm -T "femu" -e "${SCRIPT_SRC_DIR}/femu.sh --image ${IMAGE_NAME} -N ${EMU_ARGS[@]}" &
elif [[ "${HEADLESS}" == "yes" ]]; then
  # When there is no graphics support, run femu in the background with no output visible, and use a software GPU
  "${SCRIPT_SRC_DIR}/femu.sh" --image "${IMAGE_NAME}" -N --headless --software-gpu "${EMU_ARGS[@]}" &> "${FEMU_LOG}" < /dev/null &
else
  # Allow femu to open up a window for the emulator and use hardware Vulkan support
  "${SCRIPT_SRC_DIR}/femu.sh" --image "${IMAGE_NAME}" -N "${EMU_ARGS[@]}" &> "${FEMU_LOG}" < /dev/null &
fi
FEMU_PID=$!
trap cleanup EXIT

# Wait for the emulator to start, and check if emu is still running in the background or this will never complete
echo "Waiting for emulator to start"
while true ; do
  kill -0 ${FEMU_PID} &> /dev/null || ( echo "ERROR: Emulator pid $FEMU_PID has exited, cannot connect"; exit 1; )
  "${SCRIPT_SRC_DIR}/fssh.sh" --device-ip "${EMULATOR_ADDRESS}" "echo hello" &> /dev/null && break
  echo "Waiting for emulator SSH server ${EMULATOR_ADDRESS} ..."
  sleep 1s
done
echo "Emulator pid ${FEMU_PID} is running and accepting connections"

# Start the package server after the emulator is ready, so we know it is configured when we run commands
echo "Starting package server"
"${SCRIPT_SRC_DIR}/fserve.sh" --image qemu-x64 &> /dev/null

# Execute the script specified on the command-line
EXEC_RESULT=0
if [[ "${EXEC_SCRIPT}" == "" ]]; then
  echo "No --exec script specified, will now clean up"
else
  echo "Executing bash -c \"${EXEC_SCRIPT}\""
  bash -c "${EXEC_SCRIPT}" || EXEC_RESULT=$?
fi

if [[ "${EXEC_RESULT}" != "0" ]]; then
  echo "ERROR: \"${EXEC_SCRIPT}\" returned ${EXEC_RESULT}"
fi

# Exit with the result of the test script, and also run the cleanup function
exit $EXEC_RESULT
