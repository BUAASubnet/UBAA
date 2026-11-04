import Cocoa
import Darwin
import FlutterMacOS

let commandArguments = Array(CommandLine.arguments.dropFirst())
let invokedAsCommand = (CommandLine.arguments.first! as NSString).lastPathComponent == "ubaa"
if invokedAsCommand || commandArguments.first == "--command" {
  let arguments = invokedAsCommand ? commandArguments : Array(commandArguments.dropFirst())
  runCommand(arguments)
  exit(7)
}

// GUI 独占角色锁；命令消费者不参与 GUI 单实例判断。
let user = getpwuid(geteuid())!
let userHome = String(cString: user.pointee.pw_dir)
let roleDirectory = userHome + "/Library/Application Support/UBAA"
try FileManager.default.createDirectory(atPath: roleDirectory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
let roleLock = open(roleDirectory + "/gui_role.lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
if roleLock < 0 { exit(7) }
if flock(roleLock, LOCK_EX | LOCK_NB) != 0 {
  DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("cn.edu.ubaa.activate_gui"), object: String(geteuid()),
    userInfo: nil, deliverImmediately: true)
  exit(0)
}
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
