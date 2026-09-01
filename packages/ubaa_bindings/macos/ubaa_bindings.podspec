#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint ubaa_flutter_bridge.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'ubaa_bindings'
  s.version          = '0.1.0'
  s.summary          = 'UBAA Flutter Rust bridge.'
  s.description      = <<-DESC
UBAA Flutter Rust bridge generated bindings.
                       DESC
  s.homepage         = 'https://github.com/BUAASubnet/UBAA'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'BUAASubnet'
  s.module_name      = 'ubaa_flutter_bridge'

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  # reqwest/hyper 的 macOS 系统代理探测依赖此系统框架；显式声明避免 arm64
  # 链接时遗漏 SCDynamicStore/SCNetworkReachability 符号。
  s.frameworks = 'SystemConfiguration'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'

  s.script_phase = {
    :name => 'Build Rust library',
    # First argument is relative path to the `rust` folder, second is name of rust library
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../../../crates/ubaa-flutter-bridge ubaa_flutter_bridge',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    # Let XCode know that the static library referenced in -force_load below is
    # created by this build step.
    :output_files => ["${PODS_CONFIGURATION_BUILD_DIR}/ubaa_flutter_bridge/libubaa_flutter_bridge.a"],
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # Flutter.framework does not contain a i386 slice.
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-force_load ${PODS_CONFIGURATION_BUILD_DIR}/ubaa_flutter_bridge/libubaa_flutter_bridge.a',
  }
  # 静态 Rust archive 的系统框架依赖需要传递到最终 Runner target。
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -framework SystemConfiguration',
  }
end
