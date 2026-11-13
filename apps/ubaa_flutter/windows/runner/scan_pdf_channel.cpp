#include "scan_pdf_channel.h"

#include <winrt/Windows.Data.Pdf.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>

#include <algorithm>
#include <cmath>
#include <optional>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using Reply = flutter::MethodResult<EncodableValue>;
using namespace winrt::Windows;

winrt::fire_and_forget RenderPage(std::string path, uint32_t number,
                                 std::weak_ptr<bool> lifetime,
                                 std::unique_ptr<Reply> reply) {
  std::optional<EncodableMap> response;
  try {
    auto file = co_await Storage::StorageFile::GetFileFromPathAsync(
        winrt::to_hstring(path));
    auto document = co_await Data::Pdf::PdfDocument::LoadFromFileAsync(file);
    const auto total = document.PageCount();
    if (number <= total) {
      auto page = document.GetPage(number - 1);
      const auto size = page.Size();
      if (size.Width > 0 && size.Height > 0 && std::isfinite(size.Width) &&
          std::isfinite(size.Height)) {
        const double scale = 1800.0 / std::max(size.Width, size.Height);
        const auto pixels = [scale](double length) {
          return static_cast<uint32_t>(std::max(1.0, std::round(length * scale)));
        };
        Data::Pdf::PdfPageRenderOptions options;
        options.DestinationWidth(pixels(size.Width));
        options.DestinationHeight(pixels(size.Height));
        options.BitmapEncoderId(Graphics::Imaging::BitmapEncoder::PngEncoderId());
        Storage::Streams::InMemoryRandomAccessStream stream;
        co_await page.RenderToStreamAsync(stream, options);
        page.Close();
        const auto length = stream.Size();
        if (length != 0 && length <= 16 * 1024 * 1024) {
          const auto size_bytes = static_cast<uint32_t>(length);
          Storage::Streams::DataReader reader(stream.GetInputStreamAt(0));
          if (co_await reader.LoadAsync(size_bytes) == size_bytes) {
            std::vector<uint8_t> bytes(size_bytes);
            reader.ReadBytes(bytes);
            response = EncodableMap{
                {EncodableValue("totalPages"),
                 EncodableValue(static_cast<int64_t>(total))},
                {EncodableValue("image"), EncodableValue(std::move(bytes))}};
          }
        }
      }
    }
  } catch (...) {
    // 向 Dart 返回固定错误，避免泄露本地路径或系统诊断信息。
  }
  // WinRT 的异步操作恢复到发起调用的 UI apartment；引擎退出后不再回复。
  if (lifetime.expired()) {
    co_return;
  }
  if (response) {
    reply->Success(EncodableValue(std::move(*response)));
  } else {
    reply->Error("scan_pdf_render", "无法渲染该扫描 PDF");
  }
}

template <typename T>
const T* Argument(const EncodableMap& args, const char* name) {
  const auto found = args.find(EncodableValue(name));
  return found == args.end() ? nullptr : std::get_if<T>(&found->second);
}

}  // namespace

ScanPdfChannel::ScanPdfChannel(flutter::BinaryMessenger* messenger)
    : channel_(messenger, "cn.edu.buaa.ubaa/agenda-file",
               &flutter::StandardMethodCodec::GetInstance()) {
  channel_.SetMethodCallHandler(
      [lifetime = std::weak_ptr<bool>(lifetime_)](
          const flutter::MethodCall<EncodableValue>& call,
          std::unique_ptr<Reply> reply) {
        if (call.method_name() != "renderScanPdf") {
          reply->NotImplemented();
          return;
        }
        const auto* args = std::get_if<EncodableMap>(call.arguments());
        const auto* path = args ? Argument<std::string>(*args, "path") : nullptr;
        const auto* page = args ? Argument<int32_t>(*args, "page") : nullptr;
        if (!path || path->empty() || !page || *page < 1) {
          reply->Error("scan_pdf_arguments", "扫描 PDF 路径或页码无效");
          return;
        }
        RenderPage(*path, static_cast<uint32_t>(*page), lifetime,
                   std::move(reply));
      });
}

ScanPdfChannel::~ScanPdfChannel() {
  lifetime_.reset();
  channel_.SetMethodCallHandler(nullptr);
}
