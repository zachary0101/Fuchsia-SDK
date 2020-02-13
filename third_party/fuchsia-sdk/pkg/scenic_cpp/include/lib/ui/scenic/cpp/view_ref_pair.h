// Copyright 2019 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef LIB_UI_SCENIC_CPP_VIEW_REF_PAIR_H_
#define LIB_UI_SCENIC_CPP_VIEW_REF_PAIR_H_

#include <fuchsia/ui/views/cpp/fidl.h>
#include <lib/zx/eventpair.h>

namespace scenic {

struct ViewRefPair {
  // Convenience function which allows clients to easily create a valid
  // |ViewRef| / |ViewRefControl| pair for use with the |View| resource.
  static ViewRefPair New();

  fuchsia::ui::views::ViewRefControl control_ref;
  fuchsia::ui::views::ViewRef view_ref;
};

}  // namespace scenic

#endif  // LIB_UI_SCENIC_CPP_VIEW_REF_PAIR_H_
