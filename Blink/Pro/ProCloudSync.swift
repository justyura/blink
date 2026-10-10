//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K   P R O
//
// iCloud sync for the Pro features:
//  - voice / Blink Pro settings  -> NSUbiquitousKeyValueStore
//  - API keys                    -> iCloud Keychain (see VoiceInputSettings)
//  - ~/.ssh/config, known_hosts  -> iCloud Drive container, Documents/BlinkPro
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation

final class ProCloudSync {
  static let shared = ProCloudSync()
  static let settingsDidChange = Notification.Name("ProCloudSyncSettingsDidChange")

  private static let prefixes = ["voiceInput.", "blinkpro."]
  private static let files = ["config", "known_hosts"]

  private let _kvs = NSUbiquitousKeyValueStore.default
  private let _queue = DispatchQueue(label: "sh.blink.pro.cloudsync", qos: .utility)
  private var _applyingRemote = false
  private var _snapshot: [String: Any] = [:]
  private(set) var lastSync: Date?
  private(set) var lastError: String?

  private init() {}

  var isAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }

  var statusDescription: String {
    guard isAvailable else { return "Not signed in to iCloud" }
    if let err = lastError { return err }
    if let t = lastSync {
      let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
      return "Synced \(f.string(from: t))"
    }
    return "Ready"
  }

  // MARK: - Lifecycle

  func start() {
    _snapshot = _localSettings()
    NotificationCenter.default.addObserver(self, selector: #selector(kvsDidChange(_:)),
                                           name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: _kvs)
    NotificationCenter.default.addObserver(self, selector: #selector(defaultsDidChange),
                                           name: UserDefaults.didChangeNotification, object: nil)
    _kvs.synchronize()
    _applyRemoteSettings(keys: Array(_kvs.dictionaryRepresentation.keys))
    sync()
  }

  /// Push local settings, then exchange the ssh files with iCloud Drive.
  func sync(force: Bool = false) {
    guard isAvailable else { return }
    _pushSettings()
    _queue.async { [weak self] in self?._syncFiles(force: force) }
  }

  /// Called after ssh-import so the fresh config reaches the other devices.
  func pushFiles() {
    guard isAvailable else { return }
    _queue.async { [weak self] in self?._syncFiles(force: true, preferLocal: true) }
  }

  // MARK: - Settings via key-value store

  private func _localSettings() -> [String: Any] {
    UserDefaults.standard.dictionaryRepresentation().filter { k, _ in
      Self.prefixes.contains { k.hasPrefix($0) }
    }
  }

  @objc private func defaultsDidChange() {
    guard !_applyingRemote, isAvailable else { return }
    _pushSettings()
  }

  private func _pushSettings() {
    let now = _localSettings()
    var changed = false
    for (k, v) in now where !_isEqual(_snapshot[k], v) {
      _kvs.set(v, forKey: k)
      changed = true
    }
    for k in _snapshot.keys where now[k] == nil {
      _kvs.removeObject(forKey: k)
      changed = true
    }
    _snapshot = now
    if changed { _kvs.synchronize() }
  }

  @objc private func kvsDidChange(_ note: Notification) {
    let keys = (note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
    _applyRemoteSettings(keys: keys)
  }

  private func _applyRemoteSettings(keys: [String]) {
    let ours = keys.filter { k in Self.prefixes.contains { k.hasPrefix($0) } }
    guard !ours.isEmpty else { return }
    _applyingRemote = true
    let d = UserDefaults.standard
    for k in ours {
      if let v = _kvs.object(forKey: k) { d.set(v, forKey: k) } else { d.removeObject(forKey: k) }
    }
    _snapshot = _localSettings()
    _applyingRemote = false
    DispatchQueue.main.async {
      VoiceInputSettings.shared.reload()
      ProSettings.shared.reload()
      NotificationCenter.default.post(name: Self.settingsDidChange, object: nil)
    }
  }

  private func _isEqual(_ a: Any?, _ b: Any?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case (let x?, let y?): return (x as AnyObject).isEqual(y)
    default: return false
    }
  }

  // MARK: - Files via iCloud Drive

  private func _cloudFolder() -> URL? {
    guard let root = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
    let dir = root.appendingPathComponent("Documents/BlinkPro", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func _syncFiles(force: Bool, preferLocal: Bool = false) {
    guard let cloud = _cloudFolder(), let sshDir = BlinkPaths.ssh() else {
      DispatchQueue.main.async { self.lastError = "iCloud Drive unavailable" }
      return
    }
    let fm = FileManager.default
    var error: String? = nil

    for name in Self.files {
      let local = URL(fileURLWithPath: (sshDir as NSString).appendingPathComponent(name))
      let remote = cloud.appendingPathComponent(name)

      // Make sure the cloud copy is downloaded before comparing.
      try? fm.startDownloadingUbiquitousItem(at: remote)
      let localDate = (try? fm.attributesOfItem(atPath: local.path)[.modificationDate] as? Date)
      let remoteDate = (try? fm.attributesOfItem(atPath: remote.path)[.modificationDate] as? Date)

      do {
        switch (localDate, remoteDate) {
        case (nil, nil):
          continue
        case (let l?, let r?):
          if preferLocal || l > r.addingTimeInterval(1) {
            try _copy(local, to: remote, coordinated: true)
          } else if r > l.addingTimeInterval(1) && !force {
            try _copy(remote, to: local, coordinated: false)
          } else if force && r > l.addingTimeInterval(1) {
            try _copy(remote, to: local, coordinated: false)
          }
        case (_?, nil):
          try _copy(local, to: remote, coordinated: true)
        case (nil, _?):
          try _copy(remote, to: local, coordinated: false)
        }
      } catch let e {
        error = "\(name): \(e.localizedDescription)"
      }
    }

    DispatchQueue.main.async {
      self.lastError = error
      if error == nil { self.lastSync = Date() }
    }
  }

  private func _copy(_ src: URL, to dst: URL, coordinated: Bool) throws {
    let data = try Data(contentsOf: src)
    if coordinated {
      var coordError: NSError?
      var writeError: Error?
      NSFileCoordinator().coordinate(writingItemAt: dst, options: .forReplacing, error: &coordError) { url in
        do { try data.write(to: url, options: .atomic) } catch { writeError = error }
      }
      if let e = coordError ?? (writeError as NSError?) { throw e }
    } else {
      try data.write(to: dst, options: .atomic)
    }
  }
}
