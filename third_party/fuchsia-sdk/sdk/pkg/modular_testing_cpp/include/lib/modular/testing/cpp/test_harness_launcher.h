// Copyright 2019 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef LIB_MODULAR_TESTING_CPP_TEST_HARNESS_LAUNCHER_H_
#define LIB_MODULAR_TESTING_CPP_TEST_HARNESS_LAUNCHER_H_

#include <fuchsia/modular/testing/cpp/fidl.h>
#include <fuchsia/sys/cpp/fidl.h>
#include <lib/async-loop/cpp/loop.h>
#include <lib/async-loop/default.h>
#include <lib/sys/cpp/service_directory.h>

namespace modular_testing {

// TestHarnessLauncher launches and manages an instance of the modular test
// harness component. Use this class to acquire an instance of the
// |fuchsia.modular.TestHarness| service.
class TestHarnessLauncher final {
 public:
  // Launches the modular test harness component.
  explicit TestHarnessLauncher(fuchsia::sys::LauncherPtr launcher);

  // Blocks the current thread until the modular test harness component is
  // destroyed.
  ~TestHarnessLauncher();

  // Not copyable.
  TestHarnessLauncher(const TestHarnessLauncher&) = delete;
  TestHarnessLauncher& operator=(const TestHarnessLauncher&) = delete;

  fuchsia::modular::testing::TestHarnessPtr& test_harness() { return test_harness_; }

 private:
  // This async loop is launched in a separate thread, and hosts |test_harness_ctrl_|. When
  // |test_harness_ctrl_| is closed, this loop exits and unblocks the destructor.
  async::Loop test_harness_loop_;

  std::shared_ptr<sys::ServiceDirectory> test_harness_svc_;

  fuchsia::sys::ComponentControllerPtr
      test_harness_ctrl_;  // Bound to |test_harness_loop_|'s dispatcher.

  fuchsia::modular::testing::TestHarnessPtr test_harness_;
  fuchsia::modular::LifecyclePtr lifecycle_;
};

}  // namespace modular_testing

#endif  // LIB_MODULAR_TESTING_CPP_TEST_HARNESS_LAUNCHER_H_
