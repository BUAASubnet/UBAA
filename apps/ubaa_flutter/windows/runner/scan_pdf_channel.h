#ifndef RUNNER_SCAN_PDF_CHANNEL_H_
#define RUNNER_SCAN_PDF_CHANNEL_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

// Windows 系统 PDF 渲染，仅用于本机扫描件预览。
class ScanPdfChannel {
 public:
  explicit ScanPdfChannel(flutter::BinaryMessenger* messenger);
  ~ScanPdfChannel();

 private:
  flutter::MethodChannel<flutter::EncodableValue> channel_;
  std::shared_ptr<bool> lifetime_ = std::make_shared<bool>(true);
};

#endif  // RUNNER_SCAN_PDF_CHANNEL_H_
