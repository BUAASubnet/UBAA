# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "ubaa_bindings")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../cargokit/cmake/cargokit.cmake")
get_filename_component(
  UBAA_RUST_CRATE_DIR
  "${CMAKE_SOURCE_DIR}/../../../crates/ubaa-flutter-bridge"
  ABSOLUTE
)
apply_cargokit(${PROJECT_NAME} "${UBAA_RUST_CRATE_DIR}" ubaa_flutter_bridge "")

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(ubaa_bindings_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
