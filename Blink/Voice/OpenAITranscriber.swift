//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K   P R O
//
// Minimal client for the OpenAI audio transcription API (gpt-4o-transcribe).
// https://platform.openai.com/docs/api-reference/audio/createTranscription
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation

struct OpenAITranscriber: SpeechTranscriber {
  static let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

  var apiKey: String
  var modelId: String = "gpt-4o-transcribe"
  var languageCode: String? = nil
  var keyterms: [String] = []

  func transcribe(fileURL: URL) async throws -> SpeechTranscript {
    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { throw TranscriberError.missingAPIKey("OpenAI") }

    let audio = try Data(contentsOf: fileURL)
    let boundary = "BlinkPro-\(UUID().uuidString)"

    var fields: [(String, String)] = [
      ("model", modelId),
      ("response_format", "json"),
    ]
    if let lang = languageCode?.trimmingCharacters(in: .whitespaces), !lang.isEmpty {
      fields.append(("language", lang))
    }
    // The prompt biases the model towards the vocabulary it contains.
    if !keyterms.isEmpty {
      fields.append(("prompt", keyterms.joined(separator: ", ")))
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
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
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
      throw TranscriberError.http(provider: "OpenAI", status: http.statusCode, message: Self.errorMessage(from: data))
    }

    guard
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let text = json["text"] as? String
    else {
      throw TranscriberError.invalidResponse
    }

    return SpeechTranscript(text: text, languageCode: nil)
  }

  /// Validates the key by transcribing a short silent clip with the selected model.
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
    if let err = json["error"] as? [String: Any] {
      return (err["message"] as? String) ?? "\(err)"
    }
    return ""
  }
}
