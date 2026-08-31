cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "ubaa_bindings")
set(TARGET_LIB_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH})
project(${PROJECT_NAME} LANGUAGES CXX)

if (NOT DEFINED FLUTTER_TARGET_PLATFORM)
    if (OHOS_ARCH STREQUAL "arm64-v8a")
        set(FLUTTER_TARGET_PLATFORM "ohos-arm64")
    else()
        message(FATAL_ERROR "UBAA OHOS 只允许 arm64-v8a，实际为 ${OHOS_ARCH}")
    endif()
endif()

include("../../../../cargokit/cmake/cargokit.cmake")
apply_cargokit(
    ${PROJECT_NAME}
    ../../../../../../crates/ubaa-flutter-bridge
    ubaa_flutter_bridge
    ""
)
