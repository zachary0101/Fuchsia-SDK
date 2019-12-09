# Copyright 2019 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Script for downloading and processing the Fuchsia Core SDK tarball.
"""

import gen_build_defs

import os
import shutil
import subprocess
import sys
import tarfile
import json

# TODO(fxb/42375): Make dir paths saved from the expand
SDK_SUBDIRS = ["arch", "dart", "device", "fidl", "meta", "pkg", "qemu", "sysroot", "target",
               "toolchain_libs", "tools"]

# SDK elements to clean up becasuse we don't use them.
UNUSED_SDK_SUBDIRS = [ "dart" ]

# Fetches a tarball from GCS and uncompresses it to |output_dir|.
def download_and_unpack_from_gcs(url, sdk_path, output_dir):
  # Pass the compressed stream directly to 'tarfile'; don't bother writing it
  # to disk first.
  gsutil_path = os.path.normpath(os.path.join(sdk_path, "..", "bin", "gsutil"))
  if not os.path.exists(gsutil_path):
    gsutil_path = "gsutil"
  cmd = [gsutil_path, 'cp', url, '-']
  task = subprocess.Popen(cmd, stdout=subprocess.PIPE)
  tarfile.open(mode='r|gz', fileobj=task.stdout).extractall(path=output_dir)
  task.wait()
  assert task.returncode == 0


def download_sdk(host_os, target_id, sdk_path, output_dir):

    url = 'gs://fuchsia/sdk/core/{platform}-amd64/{target_id}'.format(
      platform = host_os, target_id = target_id)

    download_and_unpack_from_gcs(url, sdk_path, output_dir)


def check_platform_build(meta, host_os, target_id):
    if not host_os in meta['arch']["host"]:
        print '%s not in %s' % (host_os, meta['arch']['host'])
        return True
    if target_id != meta['id']:
        print '%s does not match id: %s' %(target_id, meta['id'])
        return True
    return False




# Removes previous SDK from the specified path if it's detected there.
def cleanup(sdk_path):
    print('Removing old SDK from %s.' % sdk_path)
    shutil.rmtree(sdk_path)


def cleanup_unneeded_paths(sdk_path):
    # Remove unneeded directories.
    # TODO(fxb/42375): make cleaning up unneeded stuff metadata driven.
    for d in UNUSED_SDK_SUBDIRS:
      to_remove = os.path.join(sdk_path, d)
      if os.path.isdir(to_remove):
        shutil.rmtree(to_remove)
      elif os.path.exists(to_remove):
        os.remove(to_remove)

def main():
  sdk_path = sys.argv[1]
  host_os = sys.argv[2]
  target_id = sys.argv[3]
  needs_download = True
  meta = None
  if not os.path.exists(sdk_path):
      os.mkdir(sdk_path)
  else:
      metadata_file = os.path.join(sdk_path,'meta','manifest.json')
      if os.path.exists(metadata_file):
          meta = json.load(open(metadata_file))
          needs_download = check_platform_build(meta, host_os, target_id)

  if needs_download:
      cleanup(sdk_path)
      download_sdk(host_os, target_id, sdk_path, sdk_path)

  if not meta:
    metadata_file = os.path.join(sdk_path,'meta','manifest.json')
    if os.path.exists(metadata_file):
      meta = json.load(open(metadata_file))


  root_build = os.path.join(sdk_path,'BUILD.gn')
  if not os.path.exists(root_build):
      gen_build_defs.ConvertSdkManifests(sdk_path, meta)

  cleanup_unneeded_paths(sdk_path)


if __name__ == '__main__':
  main()
