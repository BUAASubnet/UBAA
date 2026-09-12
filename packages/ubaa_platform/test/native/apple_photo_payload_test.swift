import Foundation

/// 使用合成文件验证两端共享的原生字节边界，不访问用户照片。
@main
struct ApplePhotoPayloadTest {
  static func main() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ubaa-photo-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAO0lEQVR4nO3RQREAMAjEwKMW66K2MFoJ4cMvK+CYCXVfZ9NZXY8HBvwBMhEyETIRMhEyETIRMhEyUcgHOh4BoA8A/HAAAAAASUVORK5CYII=")!
    let file = directory.appendingPathComponent("合成图片.jpg")
    try png.write(to: file)
    let photo = try PhotoPayload.read(file)
    precondition(photo.bytes == png && photo.mimeType == "image/png", "MIME必须来自图片内容")
    precondition(photo.fileName == "合成图片.jpg", "合法展示名必须保留")
    let original = try Data(contentsOf: file)
    precondition(original == png, "读取不得改写原文件")
    for name in ["../合成路径", "bad\"name", "\u{0010}name", " spaced.png", String(repeating: "字", count: 129)] {
      var rejected = false
      do { _ = try PhotoPayload.read(file, suggestedName: name) } catch { rejected = true }
      precondition(rejected, "不应修剪或洗白非法展示名")
    }
    let boundary = directory.appendingPathComponent("boundary.png")
    var full = png
    full.append(Data(count: PhotoPayload.maxBytes - png.count))
    try full.write(to: boundary)
    let atLimit = try PhotoPayload.read(boundary)
    precondition(atLimit.bytes.count == PhotoPayload.maxBytes, "应接受10MiB边界")
    let invalid = directory.appendingPathComponent("invalid.png")
    for data in [Data(), Data("合成非图片".utf8), Data(count: PhotoPayload.maxBytes + 1)] {
      try data.write(to: invalid)
      var rejected = false
      do { _ = try PhotoPayload.read(invalid) } catch { rejected = true }
      precondition(rejected, "空内容、非图片或超限数据必须拒绝")
    }
    print("原生图片读取：MIME、原文件只读、展示名、10MiB边界及拒绝分支全部通过")
  }
}
