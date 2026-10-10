//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K   P R O
//
// Common interface for speech-to-text providers.
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation

enum SpeechProvider: String, CaseIterable, Identifiable {
  case openAI = "openai"
  case elevenLabs = "elevenlabs"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .openAI: return "OpenAI"
    case .elevenLabs: return "ElevenLabs"
    }
  }

  var defaultModelId: String {
    switch self {
    case .openAI: return "gpt-4o-transcribe"
    case .elevenLabs: return "scribe_v2"
    }
  }

  var availableModels: [(id: String, title: String)] {
    switch self {
    case .openAI:
      return [
        ("gpt-4o-transcribe", "GPT-4o Transcribe"),
        ("gpt-4o-mini-transcribe", "GPT-4o mini Transcribe"),
        ("whisper-1", "Whisper"),
      ]
    case .elevenLabs:
      return [
        ("scribe_v2", "Scribe v2"),
        ("scribe_v1", "Scribe v1"),
      ]
    }
  }

  var apiKeyHint: String {
    switch self {
    case .openAI:
      return "Create a key at platform.openai.com › API keys. The key is stored in the keychain."
    case .elevenLabs:
      return "Create a key at elevenlabs.io › Profile › API Keys. It only needs the Speech to Text permission. The key is stored in the keychain."
    }
  }
}

struct SpeechTranscript {
  let text: String
  let languageCode: String?
}

enum TranscriberError: LocalizedError {
  case missingAPIKey(String)
  case invalidResponse
  case http(provider: String, status: Int, message: String)
  case network(Error)

  var errorDescription: String? {
    switch self {
    case .missingAPIKey(let provider):
      return "\(provider) API key is not set. Open Settings › Voice Input."
    case .invalidResponse:
      return "Unexpected response from the transcription service."
    case .http(let provider, let status, let message):
      let detail = message.isEmpty ? "" : " \(message)"
      switch status {
      case 401: return "\(provider) rejected the API key (401).\(detail)"
      case 402: return "\(provider) quota exceeded (402).\(detail)"
      case 429: return "\(provider) rate limit or quota exceeded (429).\(detail)"
      default: return "\(provider) error \(status).\(detail)"
      }
    case .network(let err):
      return "Network error: \(err.localizedDescription)"
    }
  }
}

protocol SpeechTranscriber {
  func transcribe(fileURL: URL) async throws -> SpeechTranscript
  func checkAPIKey() async throws -> String
}

enum MultipartAudio {
  /// A short WAV file of silence (16 kHz, mono, 16-bit) used to validate API keys
  /// against the real transcription endpoint, which is the permission that matters.
  static func silentWAVFile(seconds: Double = 0.4) throws -> URL {
    let sampleRate = 16_000
    let frames = Int(Double(sampleRate) * seconds)
    let dataSize = frames * 2
    var d = Data()
    func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
    func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
    d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + dataSize)); d.append("WAVE".data(using: .ascii)!)
    d.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1)
    u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
    d.append("data".data(using: .ascii)!); u32(UInt32(dataSize))
    d.append(Data(count: dataSize))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("blink-voice-keycheck.wav")
    try d.write(to: url)
    return url
  }

  static func mimeType(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "m4a", "aac": return "audio/mp4"
    case "wav": return "audio/wav"
    case "caf": return "audio/x-caf"
    case "mp3": return "audio/mpeg"
    default: return "application/octet-stream"
    }
  }
}

extension VoiceInputSettings {
  /// Builds the transcriber for the currently selected provider.
  func makeTranscriber() -> SpeechTranscriber {
    switch provider {
    case .openAI:
      return OpenAITranscriber(
        apiKey: apiKey(for: .openAI),
        modelId: modelId(for: .openAI),
        languageCode: languageCode,
        keyterms: keytermsList
      )
    case .elevenLabs:
      return ElevenLabsTranscriber(
        apiKey: apiKey(for: .elevenLabs),
        modelId: modelId(for: .elevenLabs),
        languageCode: languageCode,
        keyterms: keytermsList
      )
    }
  }
}
