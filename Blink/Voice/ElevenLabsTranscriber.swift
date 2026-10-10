//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K   P R O
//
// Minimal client for the ElevenLabs Speech-to-Text (Scribe) API.
// https://elevenlabs.io/docs/api-reference/speech-to-text/convert
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation

enum ElevenLabsError: LocalizedError {
  case missingAPIKey
  case invalidResponse
  case http(status: Int, message: String)
  case network(Error)

  var errorDescription: String? {
    switch self {
    case .missingAPIKey:
      return "ElevenLabs API key is not set. Open Settings › Voice Input."
    case .invalidResponse:
      return "Unexpected response from ElevenLabs."
    case .http(let status, let message):
      switch status {
      case 401: return "ElevenLabs rejected the API key (401)."
      case 402: return "ElevenLabs quota exceeded (402)."
      default: return "ElevenLabs error \(status): \(message)"
      }
    case .network(let err):
      return "Network error: \(err.localizedDescription)"
    }
  }
}

struct ElevenLabsTranscript {
  let text: String
  let languageCode: String?
}

struct ElevenLabsTranscriber {
  static let endpoint = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
  static let userEndpoint = URL(string: "https://api.elevenlabs.io/v1/user")!

  var apiKey: String
  var modelId: String = VoiceInputSettings.defaultModelId
  var languageCode: String? = nil
  var keyterms: [String] = []

  /// Uploads an audio file and returns the transcript.
  func transcribe(fileURL: URL) async throws -> ElevenLabsTranscript {
    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { throw ElevenLabsError.missingAPIKey }

    let audio = try Data(contentsOf: fileURL)
    let boundary = "BlinkPro-\(UUID().uuidString)"

    var fields: [(String, String)] = [
      ("model_id", modelId),
      ("tag_audio_events", "false"),
      ("diarize", "false"),
      ("timestamps_granularity", "none"),
    ]
    if let lang = languageCode?.trimmingCharacters(in: .whitespaces), !lang.isEmpty {
      fields.append(("language_code", lang))
    }
    for term in keyterms.prefix(1000) {
      fields.append(("keyterms", term))
    }

    var body = Data()
    func append(_ s: String) { body.append(s.data(using: .utf8)!) }
    for (name, value) in fields {
      append("--\(boundary)\r\n")
      append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
      append("\(value)\r\n")
    }
    append("--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
    append("Content-Type: \(Self.mimeType(for: fileURL))\r\n\r\n")
    body.append(audio)
    append("\r\n--\(boundary)--\r\n")

    var request = URLRequest(url: Self.endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 90
    request.setValue(key, forHTTPHeaderField: "xi-api-key")
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await URLSession.shared.upload(for: request, from: body)
    } catch {
      throw ElevenLabsError.network(error)
    }

    guard let http = response as? HTTPURLResponse else { throw ElevenLabsError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      throw ElevenLabsError.http(status: http.statusCode, message: Self.errorMessage(from: data))
    }

    guard
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let text = json["text"] as? String
    else {
      throw ElevenLabsError.invalidResponse
    }

    return ElevenLabsTranscript(text: text, languageCode: json["language_code"] as? String)
  }

  /// Validates the API key by fetching the account. Returns a short description of the account.
  func checkAPIKey() async throws -> String {
    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { throw ElevenLabsError.missingAPIKey }

    var request = URLRequest(url: Self.userEndpoint)
    request.timeoutInterval = 20
    request.setValue(key, forHTTPHeaderField: "xi-api-key")

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw ElevenLabsError.network(error)
    }
    guard let http = response as? HTTPURLResponse else { throw ElevenLabsError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      throw ElevenLabsError.http(status: http.statusCode, message: Self.errorMessage(from: data))
    }

    let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    let sub = json["subscription"] as? [String: Any]
    let tier = sub?["tier"] as? String ?? "unknown tier"
    if let used = sub?["character_count"] as? Int, let limit = sub?["character_limit"] as? Int {
      return "OK · \(tier) · \(used)/\(limit) characters used"
    }
    return "OK · \(tier)"
  }

  private static func errorMessage(from data: Data) -> String {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return String(data: data, encoding: .utf8)?.prefix(200).description ?? ""
    }
    if let detail = json["detail"] as? [String: Any] {
      return (detail["message"] as? String) ?? (detail["status"] as? String) ?? "\(detail)"
    }
    if let detail = json["detail"] as? String { return detail }
    if let list = json["detail"] as? [[String: Any]] {
      return list.compactMap { $0["msg"] as? String }.joined(separator: "; ")
    }
    return ""
  }

  private static func mimeType(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "m4a", "aac": return "audio/mp4"
    case "wav": return "audio/wav"
    case "caf": return "audio/x-caf"
    case "mp3": return "audio/mpeg"
    default: return "application/octet-stream"
    }
  }
}
