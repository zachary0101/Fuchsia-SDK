#!/bin/bash
# Copyright 2019 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

set -eu # Error checking
err_print() {
  cleanup
  echo "Error on line $1"
}
trap 'err_print $LINENO' ERR
DEBUG_LINE() {
    "$@"
}

SCRIPT_SRC_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
FORCE=0

# Common functions.
source "${SCRIPT_SRC_DIR}/common.sh" || exit $?
REPO_ROOT="$(get_gn_root)" # finds path to REPO_ROOT
BUILD_TOOLS_DIR="$(get_buildtools_dir)" # finds path to BUILD_TOOLS_DIR
DEPOT_TOOLS_DIR="$(get_depot_tools_dir)" # finds path to DEPOT_TOOLS_DIR
DOWNLOADS_DIR="${BUILD_TOOLS_DIR}/downloads"

cleanup() {
  echo "Cleaning up downloaded build tools..."
  # Remove the build tools directory
  rm -rf "${BUILD_TOOLS_DIR}"
}

function usage {
  echo "Usage: $0"
  echo "  [--force]"
  echo "    Delete build tools directory before downloading"
}

# Parse command line
for i in "$@"
do
case "${i}" in
    -f|--force)
    FORCE=1
    ;;
    *)
    # unknown option
    usage
    exit 1
    ;;
esac
done

# If force option is set, cleanup build tools
if [ ! "${FORCE}" == 0 ]; then
  cleanup
fi

# Create build tools directory if it doesn't exist
if [ ! -d "${BUILD_TOOLS_DIR}" ]; then
  mkdir "${BUILD_TOOLS_DIR}"
fi

# Create depot tools directory if it doesn't exist
if [[ ! -d "${DEPOT_TOOLS_DIR}" ]]; then
  mkdir "${DEPOT_TOOLS_DIR}"
fi

# Create build tools download directory if it doesn't exist
if [ ! -d "${DOWNLOADS_DIR}" ]; then
  mkdir "${DOWNLOADS_DIR}"
fi

# Specify the version of the tools to download
VER_CLANG=latest
VER_NINJA=latest
VER_GN=latest
VER_GSUTIL=latest
ARCH=linux-amd64

# You can browse the CIPD repository from here to look for builds https://chrome-infra-packages.appspot.com/p/fuchsia
# You can get the instance ID and SHA256 from here: https://chrome-infra-packages.appspot.com/p/fuchsia/sdk/core/linux-amd64/+/latest
# You can use the cipd command-line tool to browse and search as well: cipd ls -r | grep $search

# Check if downloaded ZIPs exist, if not download them.
echo "==== Downloading needed archives ===="
if [ ! -f "${DOWNLOADS_DIR}/clang-${ARCH}-${VER_CLANG}.zip" ]; then
  echo -e "Downloading clang archive...\c"
  curl -sL "https://chrome-infra-packages.appspot.com/dl/fuchsia/clang/${ARCH}/+/${VER_CLANG}" -o "${DOWNLOADS_DIR}/clang-${ARCH}-${VER_CLANG}.zip"
  echo "complete."
fi
if [ ! -f "${DOWNLOADS_DIR}/gn-${ARCH}-${VER_GN}.zip" ]; then
  echo -e "Downloading gn archive...\c"
  curl -sL "https://chrome-infra-packages.appspot.com/dl/gn/gn/${ARCH}/+/${VER_GN}" -o "${DOWNLOADS_DIR}/gn-${ARCH}-${VER_GN}.zip"
  echo "complete."
fi
if [ ! -f "${DOWNLOADS_DIR}/ninja-${ARCH}-${VER_NINJA}.zip" ]; then
  echo -e "Downloading ninja archive...\c"
  curl -sL "https://chrome-infra-packages.appspot.com/dl/fuchsia/buildtools/ninja/${ARCH}/+/${VER_NINJA}" -o "${DOWNLOADS_DIR}/ninja-${ARCH}-${VER_NINJA}.zip"
  echo "complete."
fi
if [ ! -f "${DOWNLOADS_DIR}/gsutil-${VER_GSUTIL}.zip" ]; then
  echo -e "Downloading gsutil archive...\c"
  curl -sL "https://chrome-infra-packages.appspot.com/dl/infra/gsutil/+/${VER_GSUTIL}" -o "${DOWNLOADS_DIR}/gsutil-${VER_GSUTIL}.zip"
  echo "complete."
fi

# Check if unzipped folders exist, if not unzip them.
echo
echo "==== Extracting needed archives ===="
if [ ! -d "${DEPOT_TOOLS_DIR}/clang-${ARCH}" ]; then
  echo -e "Extracting clang archive...\c"
  unzip -q "${DOWNLOADS_DIR}/clang-${ARCH}-${VER_CLANG}.zip" -d "${DEPOT_TOOLS_DIR}/clang-${ARCH}"
  echo "complete."
fi
if [ ! -e "${DEPOT_TOOLS_DIR}/clang-format" ]; then
  ln -sf "${DEPOT_TOOLS_DIR}/clang-${ARCH}/bin/clang-format" "${DEPOT_TOOLS_DIR}/clang-format"
fi
if [ ! -d "${DEPOT_TOOLS_DIR}/gn-${ARCH}" ]; then
  echo -e "Extracting gn archive...\c"
  unzip -q "${DOWNLOADS_DIR}/gn-${ARCH}-${VER_GN}.zip" -d "${DEPOT_TOOLS_DIR}/gn-${ARCH}"
  ln -sf "${DEPOT_TOOLS_DIR}/gn-${ARCH}/gn" "${DEPOT_TOOLS_DIR}/gn"
  echo "complete."
fi
if [ ! -d "${DEPOT_TOOLS_DIR}/ninja-${ARCH}" ]; then
  echo -e "Extracting ninja archive...\c"
  unzip -q "${DOWNLOADS_DIR}/ninja-${ARCH}-${VER_NINJA}.zip" -d "${DEPOT_TOOLS_DIR}/ninja-${ARCH}"
  ln -sf "${DEPOT_TOOLS_DIR}/ninja-${ARCH}/ninja" "${DEPOT_TOOLS_DIR}/ninja"
  echo "complete."
fi
if [ ! -d "${DEPOT_TOOLS_DIR}/gsutil-generic" ]; then
  echo -e "Extracting gsutil archive...\c"
  unzip -q "${DOWNLOADS_DIR}/gsutil-${VER_GSUTIL}.zip" -d "${DEPOT_TOOLS_DIR}/gsutil-generic"
  ln -sf "${DEPOT_TOOLS_DIR}/gsutil-generic/gsutil" "${DEPOT_TOOLS_DIR}/gsutil"
  if [ ! -x "$(command -v gsutil)" ]; then
    ln -sf "${DEPOT_TOOLS_DIR}/gsutil-generic/gsutil" "${REPO_ROOT}/third_party/fuchsia-sdk/bin/gsutil"
  fi
  echo "complete."
fi

echo
echo "All build tools downloaded and extracted successfully to ${BUILD_TOOLS_DIR}."
