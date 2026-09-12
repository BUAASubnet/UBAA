import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 仅在原生层读取用户选中的图片，不把路径或 URL 交给 Flutter。
@available(iOS 14.0, macOS 11.0, *)
struct PhotoPayload {
  static let maxBytes = 10 * 1024 * 1024
  let bytes: Data
  let fileName: String
  let mimeType: String

  enum ReadError: Error { case unavailable, tooLarge, invalidImage }

  static func read(_ url: URL, suggestedName: String? = nil) throws -> PhotoPayload {
    guard let stream = InputStream(url: url) else { throw ReadError.unavailable }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count >= 0 else { throw ReadError.unavailable }
      if count == 0 { break }
      guard data.count + count <= maxBytes else { throw ReadError.tooLarge }
      data.append(buffer, count: count)
    }
    guard !data.isEmpty,
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let identifier = CGImageSourceGetType(source),
          let type = UTType(identifier as String), type.conforms(to: .image),
          let mime = type.preferredMIMEType else { throw ReadError.invalidImage }
    let proposed = suggestedName ?? url.lastPathComponent
    let invalid = proposed != proposed.trimmingCharacters(in: .whitespacesAndNewlines) ||
      proposed.isEmpty || proposed == "." || proposed == ".." ||
      proposed.unicodeScalars.count > 128 || proposed.unicodeScalars.contains {
        $0.value <= 0x1f || (0x7f...0x9f).contains($0.value) || "/\\\"".unicodeScalars.contains($0)
      }
    guard !invalid else { throw ReadError.invalidImage }
    return PhotoPayload(bytes: data, fileName: proposed, mimeType: mime)
  }
}
