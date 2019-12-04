#!/bin/bash
# Copyright 2019 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

err_exit() {
  echo "Error on line $1"
  popd
}
trap 'err_exit $LINENO' ERR
set -e # Error checking

DEBUG_LINE() {
    $@
}

BUILDTOOLS_DIR="$(dirname $0)/buildtools"

if [[ ! -d "${BUILDTOOLS_DIR}" ]]; then
  mkdir "${BUILDTOOLS_DIR}"
fi

pushd "${BUILDTOOLS_DIR}"
set -xv

# Specify the version of the tools to download
VER_CLANG=latest
VER_AEMU=latest
VER_NINJA=latest
VER_GN=latest
VER_GSUTIL=latest
ARCH=linux-amd64

# You can browse the CIPD repository from here to look for builds https://chrome-infra-packages.appspot.com/p/fuchsia
# You can get the instance ID and SHA256 from here: https://chrome-infra-packages.appspot.com/p/fuchsia/sdk/core/linux-amd64/+/latest
# You can use the cipd command-line tool to browse and search as well: cipd ls -r | grep $search

if [ ! -f clang-$ARCH-$VER_CLANG.zip ]; then
  curl -L https://chrome-infra-packages.appspot.com/dl/fuchsia/clang/$ARCH/+/$VER_CLANG -o clang-$ARCH-$VER_CLANG.zip
fi
if [ ! -f aemu-$ARCH-$VER_AEMU.zip ]; then
  curl -L https://chrome-infra-packages.appspot.com/dl/fuchsia/third_party/aemu/$ARCH/+/$VER_AEMU -o aemu-$ARCH-$VER_AEMU.zip
fi
if [ ! -f gn-$ARCH-$VER_GN.zip ]; then
  curl -L https://chrome-infra-packages.appspot.com/dl/gn/gn/$ARCH/+/$VER_GN -o gn-$ARCH-$VER_GN.zip
fi
if [ ! -f ninja-$ARCH-$VER_NINJA.zip ]; then
  curl -L https://chrome-infra-packages.appspot.com/dl/fuchsia/buildtools/ninja/$ARCH/+/$VER_NINJA -o ninja-$ARCH-$VER_NINJA.zip
fi
if [ ! -f gsutil-$VER_GSUTIL.zip ]; then
  curl -L https://chrome-infra-packages.appspot.com/dl/infra/gsutil/+/$VER_GSUTIL -o gsutil-$VER_GSUTIL.zip
fi

# Delete all the extracted directories to start over again
rm -rf clang-$ARCH aemu-$ARCH gn-$ARCH ninja-$ARCH gsutil-generic

unzip -q clang-$ARCH-$VER_CLANG.zip   -d clang-$ARCH
unzip -q aemu-$ARCH-$VER_AEMU.zip     -d aemu-$ARCH
unzip -q gn-$ARCH-$VER_GN.zip         -d gn-$ARCH
unzip -q ninja-$ARCH-$VER_NINJA.zip   -d ninja-$ARCH
unzip -q gsutil-$VER_GSUTIL.zip       -d gsutil-generic

# Set up symbolic links to important tools
ln -sf gn-$ARCH/gn gn
ln -sf ninja-$ARCH/ninja ninja
ln -sf gsutil-generic/gsutil gsutil
ln -sf ../../../buildtools/gsutil-generic/gsutil ../third_party/fuchsia-sdk/bin/gsutil

# Mark that this script completed successfully
touch .complete-cipd

popd
