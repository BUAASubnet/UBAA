import Cocoa
import Darwin
import FlutterMacOS
import flutter_secure_storage_darwin

func runCommand(_ arguments: [String]) {
  var terminalMode = termios()
  let hasTerminal = isatty(STDIN_FILENO) == 1 && tcgetattr(STDIN_FILENO, &terminalMode) == 0
  func restoreTerminal() {
    if hasTerminal { tcsetattr(STDIN_FILENO, TCSANOW, &terminalMode) }
  }
  let started = ProcessInfo.processInfo.systemUptime
  let output = dup(STDOUT_FILENO)
  let diagnostics = dup(STDERR_FILENO)
  guard output >= 0, diagnostics >= 0 else { exit(7) }
  dup2(STDERR_FILENO, STDOUT_FILENO)
  signal(SIGPIPE, SIG_IGN)
  _ = NSApplication.shared
  let project = FlutterDartProject()
  project.dartEntrypointArguments = ["ubaa"] + arguments
  let engine = FlutterEngine(name: "ubaa_command", project: project, allowHeadlessExecution: true)
  FlutterSecureStorageDarwinPlugin.register(with: engine.registrar(forPlugin: "FlutterSecureStorageDarwinPlugin"))
  let channel = FlutterMethodChannel(name: "cn.edu.ubaa/command", binaryMessenger: engine.binaryMessenger)
  var localCommand = false
  channel.setMethodCallHandler { call, result in
    if call.method == "configure", let local = call.arguments as? Bool { localCommand = local; result(nil); return }
    if call.method == "config" {
      result(["remainingMillis": max(0, Int((120 - (ProcessInfo.processInfo.systemUptime - started)) * 1000))])
      return
    }
    if call.method == "complete", let code = call.arguments as? Int {
      result(nil)
      DispatchQueue.main.async { restoreTerminal(); engine.shutDownEngine(); exit(Int32(code)) }
      return
    }
    if call.method == "stdout" || call.method == "stderr" {
      guard let bytes = call.arguments as? FlutterStandardTypedData else {
        result(FlutterError(code: "io_error", message: "输出数据无效", details: nil)); return
      }
      let descriptor = call.method == "stdout" ? output : diagnostics
      DispatchQueue.global(qos: .userInitiated).async {
        let success = writeCommandBytes(descriptor, bytes.data)
        DispatchQueue.main.async {
          result(success ? nil : FlutterError(code: "io_error", message: "终端写入失败", details: nil))
        }
      }
      return
    }
    if call.method == "readLine" || call.method == "readBody" {
      let line = call.method == "readLine"
      let secret = line && (call.arguments as? Bool == true)
      DispatchQueue.global(qos: .userInitiated).async {
        let value = readCommandBytes(line: line, secret: secret, diagnostics: diagnostics)
        DispatchQueue.main.async {
          switch value {
          case .success(let bytes): result(bytes.map { FlutterStandardTypedData(bytes: $0) })
          case .failure: result(FlutterError(code: "io_error", message: "终端读取失败", details: nil))
          }
        }
      }
      return
    }
    result(FlutterMethodNotImplemented)
  }
  var sources: [DispatchSourceSignal] = []
  var stopping = false
  func stop(_ deadline: Bool) {
    if stopping { return }
    stopping = true
    restoreTerminal()
    channel.invokeMethod(deadline ? "deadline" : "cancel", arguments: nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(deadline && !localCommand ? 5 : 7) }
  }
  for number in [SIGINT, SIGTERM] {
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler { stop(false) }
    source.resume()
    sources.append(source)
  }
  DispatchQueue.main.asyncAfter(deadline: .now() + max(0, 120 - (ProcessInfo.processInfo.systemUptime - started))) { stop(true) }
  guard engine.run(withEntrypoint: "commandMain") else { exit(7) }
  withExtendedLifetime(sources) { RunLoop.main.run() }
}

private func writeCommandBytes(_ descriptor: Int32, _ bytes: Data) -> Bool {
  bytes.withUnsafeBytes { raw in
    guard let base = raw.baseAddress else { return true }
    var written = 0
    while written < raw.count {
      let count = Darwin.write(descriptor, base.advanced(by: written), raw.count - written)
      if count < 0 && errno == EINTR { continue }
      if count <= 0 { return false }
      written += count
    }
    return true
  }
}
private enum CommandReadError: Error { case input }
private func readCommandBytes(line: Bool, secret: Bool, diagnostics: Int32) -> Result<Data?, CommandReadError> {
  var original = termios()
  let terminal = secret && isatty(STDIN_FILENO) == 1 && tcgetattr(STDIN_FILENO, &original) == 0
  if terminal {
    var hidden = original
    hidden.c_lflag &= ~tcflag_t(ECHO)
    if tcsetattr(STDIN_FILENO, TCSANOW, &hidden) != 0 { return .failure(.input) }
  }
  defer {
    if terminal {
      tcsetattr(STDIN_FILENO, TCSANOW, &original)
      _ = writeCommandBytes(diagnostics, Data([10]))
    }
  }
  var data = Data()
  var buffer = [UInt8](repeating: 0, count: line ? 1 : 4096)
  while true {
    let count = Darwin.read(STDIN_FILENO, &buffer, buffer.count)
    if count < 0 && errno == EINTR { continue }
    if count < 0 { return .failure(.input) }
    if count == 0 { return .success(data.isEmpty && line ? nil : data) }
    data.append(contentsOf: buffer.prefix(count))
    if data.count > 1_048_576 { return .failure(.input) }
    if line && buffer[count - 1] == 10 { return .success(data) }
  }
}
