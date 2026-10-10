//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K   P R O
//
// `ssh-import`: import an SSH config, keys and known_hosts that were copied
// into the app's Documents/ssh-sync folder (for example by
// tools/sync-ssh-to-ipad.sh from a Mac) into Blink's ~/.ssh and keychain.
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation
import ArgumentParser
import BlinkConfig
import SSH

import ios_system


struct SSHImport: NonStdIOCommand {
  static var configuration = CommandConfiguration(
    commandName: "ssh-import",
    abstract: "Import ssh config, keys and known_hosts from Documents/ssh-sync",
    discussion: """
    Copies `config` to ~/.ssh/config, merges `known_hosts` into ~/.ssh/known_hosts and
    imports every private key file into the Blink keychain under its file name, so that
    `IdentityFile <name>` lines in the config resolve. Imported private key files are
    deleted from the sync folder afterwards.
    """
  )

  @OptionGroup var verboseOptions: VerboseOptions
  var io = NonStdIO.standard

  @Argument(help: "Folder to import from. Defaults to Documents/ssh-sync.")
  var folder: String?

  @Flag(name: .shortAndLong, help: "Replace keys that already exist with the same name.")
  var force = false

  @Flag(name: .long, help: "Only report what would be imported.")
  var dryRun = false

  static var defaultFolder: String {
    (NSHomeDirectory() as NSString).appendingPathComponent("Documents/ssh-sync")
  }

  func run() throws {
    let fm = FileManager.default
    let source = (folder.map { ($0 as NSString).expandingTildeInPath } ?? Self.defaultFolder)

    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: source, isDirectory: &isDir), isDir.boolValue else {
      throw CommandError(message: "Nothing to import: \(source) does not exist. Run tools/sync-ssh-to-ipad.sh on your Mac first.")
    }

    let sshDir = BlinkPaths.ssh()!
    let entries = try fm.contentsOfDirectory(atPath: source).sorted()
    var imported = 0, skipped = 0

    for name in entries where !name.hasPrefix(".") {
      let path = (source as NSString).appendingPathComponent(name)
      guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { continue }

      switch name {
      case "config":
        let dest = (sshDir as NSString).appendingPathComponent("config")
        print("config  -> ~/.ssh/config")
        guard !dryRun else { continue }
        if fm.fileExists(atPath: dest) {
          let backup = dest + ".bak"
          try? fm.removeItem(atPath: backup)
          try fm.moveItem(atPath: dest, toPath: backup)
        }
        try fm.copyItem(atPath: path, toPath: dest)
        imported += 1

      case "known_hosts":
        let dest = BlinkPaths.knownHostsFile()!
        let incoming = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let existing = (try? String(contentsOfFile: dest, encoding: .utf8)) ?? ""
        let known = Set(existing.split(separator: "\n").map(String.init))
        let new = incoming.split(separator: "\n").map(String.init).filter { !$0.isEmpty && !known.contains($0) }
        print("known_hosts -> ~/.ssh/known_hosts (\(new.count) new entries)")
        guard !dryRun, !new.isEmpty else { continue }
        var merged = existing
        if !merged.isEmpty && !merged.hasSuffix("\n") { merged += "\n" }
        merged += new.joined(separator: "\n") + "\n"
        try merged.write(toFile: dest, atomically: true, encoding: .utf8)
        imported += 1

      default:
        if name.hasSuffix(".pub") { continue }
        guard let blob = fm.contents(atPath: path) else { continue }

        let key: SSHKey
        do {
          key = try SSHKey(fromFileBlob: blob, passphrase: "")
        } catch SSHKeyError.wrongPassphrase {
          print("\(name): encrypted with a passphrase, skipped. Import it from Settings › Keys.")
          skipped += 1
          continue
        } catch {
          printDebug("\(name): not an SSH private key (\(error.localizedDescription)), ignored")
          continue
        }

        let comment = Self.comment(forKeyAt: path) ?? key.comment ?? name
        if let existing = BKPubKey.withID(name) {
          if force {
            print("\(name): replacing existing key")
            if !dryRun { existing.removeCard() }
          } else {
            print("\(name): already exists, skipped (use --force to replace)")
            if !dryRun { try? fm.removeItem(atPath: path) }
            skipped += 1
            continue
          }
        }

        print("\(name): \(key.sshKeyType.shortName) key -> keychain")
        guard !dryRun else { continue }
        try BKPubKey.addKeychainKey(id: name, key: key, comment: comment)
        try? fm.removeItem(atPath: path)
        imported += 1
      }
    }

    if !dryRun {
      BKPubKey.loadIDS()
    }
    print("Done. \(imported) item(s) imported, \(skipped) skipped.")
  }

  /// The comment from the matching .pub file, if there is one.
  private static func comment(forKeyAt path: String) -> String? {
    guard let pub = try? String(contentsOfFile: path + ".pub", encoding: .utf8) else { return nil }
    let parts = pub.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", maxSplits: 2)
    return parts.count == 3 ? String(parts[2]) : nil
  }
}

@_cdecl("ssh_import_main")
public func ssh_import_main(argc: Int32, argv: Argv) -> Int32 {
  setvbuf(thread_stdin, nil, _IONBF, 0)
  setvbuf(thread_stdout, nil, _IONBF, 0)
  setvbuf(thread_stderr, nil, _IONBF, 0)

  let io = NonStdIO.standard
  io.out = OutputStream(file: thread_stdout)
  io.err = OutputStream(file: thread_stderr)

  return SSHImport.main(Array(argv.args(count: argc)[1...]), io: io)
}
