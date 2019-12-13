// Copyright 2018 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "lib/fidl/cpp/encoder.h"

#include <lib/fidl/txn_header.h>
#include <lib/fidl/runtime_flag.h>
#include <zircon/assert.h>
#include <zircon/fidl.h>

namespace fidl {
namespace {

size_t Align(size_t size) {
  constexpr size_t alignment_mask = FIDL_ALIGNMENT - 1;
  return (size + alignment_mask) & ~alignment_mask;
}

}  // namespace

Encoder::Encoder(uint64_t ordinal, bool should_encode_union_as_xunion)
    : should_encode_union_as_xunion_(should_encode_union_as_xunion) {
  EncodeMessageHeader(ordinal);
}

Encoder::~Encoder() = default;

size_t Encoder::Alloc(size_t size) {
  size_t offset = bytes_.size();
  size_t new_size = bytes_.size() + Align(size);
  ZX_ASSERT(new_size >= offset);
  bytes_.resize(new_size);
  return offset;
}

#ifdef __Fuchsia__
void Encoder::EncodeHandle(zx::object_base* value, size_t offset) {
  if (value->is_valid()) {
    *GetPtr<zx_handle_t>(offset) = FIDL_HANDLE_PRESENT;
    handles_.push_back(value->release());
  } else {
    *GetPtr<zx_handle_t>(offset) = FIDL_HANDLE_ABSENT;
  }
}
#endif

Message Encoder::GetMessage() {
  return Message(BytePart(bytes_.data(), bytes_.size(), bytes_.size()),
                 HandlePart(handles_.data(), handles_.size(), handles_.size()));
}

void Encoder::Reset(uint64_t ordinal) {
  bytes_.clear();
  handles_.clear();
  EncodeMessageHeader(ordinal);
}

void Encoder::EncodeMessageHeader(uint64_t ordinal) {
  size_t offset = Alloc(sizeof(fidl_message_header_t));
  fidl_message_header_t* header = GetPtr<fidl_message_header_t>(offset);
  fidl_init_txn_header(header, 0, ordinal);
  if (should_encode_union_as_xunion_) {
    header->flags[0] |= FIDL_TXN_HEADER_UNION_FROM_XUNION_FLAG;
  }
}

}  // namespace fidl
