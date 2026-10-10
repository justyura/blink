//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K   P R O
//
// Voice input settings (OpenAI gpt-4o-transcribe or ElevenLabs Scribe).
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

  private enum Keys {
    static let enabled = "voiceInput.enabled"
    static let mode = "voiceInput.mode"
    static let provider = "voiceInput.provider"
    static func modelId(_ p: SpeechProvider) -> String { "voiceInput.modelId.\(p.rawValue)" }
    static let languageCode = "voiceInput.languageCode"
    static let appendSpace = "voiceInput.appendSpace"
    static let pressEnter = "voiceInput.pressEnter"
    static let keyterms = "voiceInput.keyterms"
  }

  private static let keychainService = "sh.blink.voice"
  private static func keychainAPIKey(_ p: SpeechProvider) -> String {
    switch p {
    case .openAI: return "openai-api-key"
    case .elevenLabs: return "elevenlabs-api-key"
    }
  }

  private let _defaults = UserDefaults.standard
  private let _keychain = UICKeyChainStore(service: VoiceInputSettings.keychainService)

  @Published var enabled: Bool {
    didSet { _defaults.set(enabled, forKey: Keys.enabled) }
  }

  @Published var mode: VoiceInputMode {
    didSet { _defaults.set(mode.rawValue, forKey: Keys.mode) }
  }

  /// Which speech-to-text service to use.
  @Published var provider: SpeechProvider {
    didSet { _defaults.set(provider.rawValue, forKey: Keys.provider) }
  }

  /// Model for the selected provider.
  @Published var modelId: String {
    didSet { _defaults.set(modelId, forKey: Keys.modelId(provider)) }
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

  /// API key for the selected provider. Stored in the keychain, never in UserDefaults.
  @Published var apiKey: String {
    didSet { _storeAPIKey(apiKey, for: provider) }
  }

  var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  func apiKey(for p: SpeechProvider) -> String {
    p == provider ? apiKey : (_keychain.string(forKey: VoiceInputSettings.keychainAPIKey(p)) ?? "")
  }

  func modelId(for p: SpeechProvider) -> String {
    p == provider ? modelId : (_defaults.string(forKey: Keys.modelId(p)) ?? p.defaultModelId)
  }

  /// Switch provider and reload that provider's key and model.
  func select(provider p: SpeechProvider) {
    guard p != provider else { return }
    provider = p
    modelId = _defaults.string(forKey: Keys.modelId(p)) ?? p.defaultModelId
    apiKey = _keychain.string(forKey: VoiceInputSettings.keychainAPIKey(p)) ?? ""
  }

  private func _storeAPIKey(_ key: String, for p: SpeechProvider) {
    if key.isEmpty {
      _keychain.removeItem(forKey: VoiceInputSettings.keychainAPIKey(p))
    } else {
      _keychain.setString(key, forKey: VoiceInputSettings.keychainAPIKey(p))
    }
  }

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
    let p = SpeechProvider(rawValue: d.string(forKey: Keys.provider) ?? "") ?? .openAI
    provider = p
    modelId = d.string(forKey: Keys.modelId(p)) ?? p.defaultModelId
    languageCode = d.string(forKey: Keys.languageCode) ?? ""
    appendSpace = d.object(forKey: Keys.appendSpace) as? Bool ?? true
    pressEnter = d.object(forKey: Keys.pressEnter) as? Bool ?? false
    keyterms = d.string(forKey: Keys.keyterms) ?? ""
    apiKey = UICKeyChainStore(service: VoiceInputSettings.keychainService)
      .string(forKey: VoiceInputSettings.keychainAPIKey(p)) ?? ""
  }
}
