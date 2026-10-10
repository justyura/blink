//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K   P R O
//
// Voice input settings (ElevenLabs Scribe speech-to-text).
//
// Blink Pro is a fork of Blink Shell (https://github.com/blinksh/blink),
// distributed under the same GNU General Public License v3 terms.
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation
import Combine

enum VoiceInputMode: String, CaseIterable, Identifiable {
  /// Hold right Shift to record, release to transcribe.
  case pushToTalk = "push"
  /// Tap right Shift to start recording, tap again to stop and transcribe.
  case toggle = "toggle"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .pushToTalk: return "Push to Talk"
    case .toggle: return "Toggle"
    }
  }

  var usageHint: String {
    switch self {
    case .pushToTalk:
      return "Hold right Shift and speak. Release to transcribe. Pressing any other key while holding cancels the recording, so Shift+key chords keep working."
    case .toggle:
      return "Tap right Shift alone to start recording. Tap it again to stop and transcribe."
    }
  }
}

/// Persisted configuration for the voice input feature.
/// Plain values go to `UserDefaults`; the ElevenLabs API key lives in the keychain.
final class VoiceInputSettings: ObservableObject {
  static let shared = VoiceInputSettings()

  static let defaultModelId = "scribe_v2"
  static let availableModels: [(id: String, title: String)] = [
    ("scribe_v2", "Scribe v2"),
    ("scribe_v1", "Scribe v1"),
  ]

  private enum Keys {
    static let enabled = "voiceInput.enabled"
    static let mode = "voiceInput.mode"
    static let modelId = "voiceInput.modelId"
    static let languageCode = "voiceInput.languageCode"
    static let appendSpace = "voiceInput.appendSpace"
    static let pressEnter = "voiceInput.pressEnter"
    static let keyterms = "voiceInput.keyterms"
  }

  private static let keychainService = "sh.blink.voice"
  private static let keychainAPIKey = "elevenlabs-api-key"

  private let _defaults = UserDefaults.standard
  private let _keychain = UICKeyChainStore(service: VoiceInputSettings.keychainService)

  @Published var enabled: Bool {
    didSet { _defaults.set(enabled, forKey: Keys.enabled) }
  }

  @Published var mode: VoiceInputMode {
    didSet { _defaults.set(mode.rawValue, forKey: Keys.mode) }
  }

  @Published var modelId: String {
    didSet { _defaults.set(modelId, forKey: Keys.modelId) }
  }

  /// ISO-639-1 / ISO-639-3 language code. Empty means "detect automatically".
  @Published var languageCode: String {
    didSet { _defaults.set(languageCode, forKey: Keys.languageCode) }
  }

  /// Append a single space after the transcribed text so typing can continue naturally.
  @Published var appendSpace: Bool {
    didSet { _defaults.set(appendSpace, forKey: Keys.appendSpace) }
  }

  /// Send a carriage return after the transcribed text (submits the prompt).
  @Published var pressEnter: Bool {
    didSet { _defaults.set(pressEnter, forKey: Keys.pressEnter) }
  }

  /// Comma separated key terms that bias the transcriber (e.g. "Claude, Blink, kubectl").
  @Published var keyterms: String {
    didSet { _defaults.set(keyterms, forKey: Keys.keyterms) }
  }

  /// ElevenLabs API key. Stored in the keychain, never in UserDefaults.
  @Published var apiKey: String {
    didSet {
      if apiKey.isEmpty {
        _keychain.removeItem(forKey: VoiceInputSettings.keychainAPIKey)
      } else {
        _keychain.setString(apiKey, forKey: VoiceInputSettings.keychainAPIKey)
      }
    }
  }

  var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  var keytermsList: [String] {
    keyterms
      .split(whereSeparator: { $0 == "," || $0 == "\n" })
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  private init() {
    let d = UserDefaults.standard
    enabled = d.object(forKey: Keys.enabled) as? Bool ?? true
    mode = VoiceInputMode(rawValue: d.string(forKey: Keys.mode) ?? "") ?? .pushToTalk
    modelId = d.string(forKey: Keys.modelId) ?? VoiceInputSettings.defaultModelId
    languageCode = d.string(forKey: Keys.languageCode) ?? ""
    appendSpace = d.object(forKey: Keys.appendSpace) as? Bool ?? true
    pressEnter = d.object(forKey: Keys.pressEnter) as? Bool ?? false
    keyterms = d.string(forKey: Keys.keyterms) ?? ""
    apiKey = UICKeyChainStore(service: VoiceInputSettings.keychainService)
      .string(forKey: VoiceInputSettings.keychainAPIKey) ?? ""
  }
}
