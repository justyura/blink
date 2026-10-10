//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K   P R O
//
// Minimal client for the ElevenLabs Speech-to-Text (Scribe) API.
// https://elevenlabs.io/docs/api-reference/speech-to-text/convert
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation

struct ElevenLabsTranscriber: SpeechTranscriber {
  static let endpoint = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!

  var apiKey: String
  var modelId: String = SpeechProvider.elevenLabs.defaultModelId
  var languageCode: String? = nil
  var keyterms: [String] = []

  /// Uploads an audio file and returns the transcript.
  func transcribe(fileURL: URL) async throws -> SpeechTranscript {
    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { throw TranscriberError.missingAPIKey("ElevenLabs") }

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
    append("Content-Type: \(MultipartAudio.mimeType(for: fileURL))\r\n\r\n")
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
      throw TranscriberError.network(error)
    }

    guard let http = response as? HTTPURLResponse else { throw TranscriberError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      throw TranscriberError.http(provider: "ElevenLabs", status: http.statusCode, message: Self.errorMessage(from: data))
    }

    guard
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let text = json["text"] as? String
    else {
      throw TranscriberError.invalidResponse
    }

    return SpeechTranscript(text: text, languageCode: json["language_code"] as? String)
  }

  /// Validates the key by transcribing a short silent clip, which exercises the
  /// Speech to Text permission that dictation actually needs.
  func checkAPIKey() async throws -> String {
    let url = try MultipartAudio.silentWAVFile()
    defer { try? FileManager.default.removeItem(at: url) }
    _ = try await transcribe(fileURL: url)
    return "OK · \(modelId)"
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

}
