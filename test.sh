#!/bin/bash
# Copyright 2019 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

#
# TODO(fxb/41811): Refactor this script to make it more robust and useful.
#

err_print() {
  echo "Error on line $1"
}
trap 'err_print $LINENO' ERR
set -e # Error checking

DEBUG_LINE() {
    $@
}

cd `dirname $0`
set -xv

if [ ! -f buildtools/.complete-cipd ]; then
  ./download-cipd.sh
fi

rm -rf out

./buildtools/gn  gen out/arm64 --args='target_os="fuchsia" target_cpu="arm64"'
./buildtools/ninja -C out/arm64
./buildtools/ninja -C out/arm64 tests
./buildtools/gn  gen out/x64   --args='target_os="fuchsia" target_cpu="x64"'
./buildtools/ninja -C out/x64
./buildtools/ninja -C out/x64 tests
./buildtools/gn  gen out/local --args='target_os="linux"   target_cpu="x64"'
./buildtools/ninja -C out/local
./buildtools/ninja -C out/local tests

echo "==== All created FAR files and local executables ===="
ls -al out/arm64/*.far out/x64/*.far out/local/*.so out/local/*_bin
set +xv

echo
echo "==== Showing meta/package contents for each FAR files ===="
FAR="./third_party/fuchsia-sdk/sdk/tools/far"
for each in `ls -1 out/arm64/*.far out/x64/*.far`; do
  $FAR extract --archive=$each --output=.tmp-extracted-$each
  $FAR extract --archive=.tmp-extracted-$each/meta.far --output=.tmp-extracted-meta-$each
  echo
  echo "meta/package contents for $each"
  cat .tmp-extracted-meta-$each/meta/contents
done

echo
echo "==== Scanning FAR files to check for missing shared libraries ===="
echo
for each in `ls -1 out/arm64/*.far out/x64/*.far`; do
  LINES=`cat .tmp-extracted-meta-$each/meta/contents | egrep "ld\.so\.1|libc\+\+\.so|libfdio\.so" | wc --lines`
  if [ "$LINES" != "3" ]; then
    echo "**** Failed to find ld.so.1, libc++.so, and libfdio.so mentioned in $each with [$LINES] ****"
    cat .tmp-extracted-meta-$each/meta/contents
    exit 1
  fi
  rm -rf .tmp-extracted-$each
  rm -rf .tmp-extracted-meta-$each
done
rmdir .tmp-extracted-out/x64
rmdir .tmp-extracted-out/arm64
rmdir .tmp-extracted-out
rmdir .tmp-extracted-meta-out/x64
rmdir .tmp-extracted-meta-out/arm64
rmdir .tmp-extracted-meta-out

echo
echo "==== Run host tests ===="
for dir in `ls out`; do
  for i in `cat out/$dir/all_host_tests.txt`; do
    out/$dir/$i
  done
done

echo
echo "Success!"
