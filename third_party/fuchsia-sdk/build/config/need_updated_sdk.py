# Copyright 2019 The Fuchsia Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

"""Helper script to determine if the Fuchsia Core SDK needs to be downloaded.
"""

import os
import sys

def main():
  sdk_path = sys.argv[1]
  host_os = sys.argv[2]
  target_id = sys.argv[3]

  if not os.path.exists(sdk_path):
      # sdk is not downloaded so it needs to be updated.
      print sys.argv
      return

  print sys.argv

if __name__ == '__main__':
  main()
