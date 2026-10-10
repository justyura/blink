//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K   P R O
//
// Settings › Voice Input
//
//////////////////////////////////////////////////////////////////////////////////

import SwiftUI

struct VoiceInputSettingsView: View {
  @ObservedObject private var settings = VoiceInputSettings.shared
  @State private var _checkStatus: String? = nil
  @State private var _checking = false

  var body: some View {
    List {
      Section(
        header: Text("Voice Input"),
        footer: Text("Press the right Shift key on a hardware keyboard to dictate. Speech is transcribed by ElevenLabs Scribe and typed into the active terminal, which makes talking to AI assistants in the shell fast.")
      ) {
        Toggle("Enable Voice Input", isOn: $settings.enabled)
      }

      Section(
        header: Text("ElevenLabs"),
        footer: Text("Create a key at elevenlabs.io › Profile › API Keys. It only needs the Speech to Text permission. The key is stored in the keychain.")
      ) {
        SecureField("API Key", text: $settings.apiKey)
          .textContentType(.password)
          .autocapitalization(.none)
          .disableAutocorrection(true)
        Picker("Model", selection: $settings.modelId) {
          ForEach(VoiceInputSettings.availableModels, id: \.id) { model in
            Text(model.title).tag(model.id)
          }
        }
        HStack {
          Text("Language")
          Spacer()
          TextField("auto", text: $settings.languageCode)
            .multilineTextAlignment(.trailing)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .frame(maxWidth: 120)
            .foregroundColor(.secondary)
        }
        Button(action: _checkKey) {
          HStack {
            Text("Check API Key")
            Spacer()
            if _checking {
              ProgressView()
            } else if let status = _checkStatus {
              Text(status)
                .font(.footnote)
                .foregroundColor(status.hasPrefix("OK") ? .green : .red)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
            }
          }
        }
        .disabled(_checking || !settings.hasAPIKey)
      }

      Section(
        header: Text("Right Shift"),
        footer: Text(settings.mode.usageHint)
      ) {
        Picker(selection: $settings.mode, label: Text("")) {
          ForEach(VoiceInputMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .pickerStyle(SegmentedPickerStyle())
      }

      Section(
        header: Text("After Transcription"),
        footer: Text("\"Press Enter\" submits the dictated text right away, which is handy for chat-style AI tools.")
      ) {
        Toggle("Append Space", isOn: $settings.appendSpace)
        Toggle("Press Enter", isOn: $settings.pressEnter)
      }

      Section(
        header: Text("Key Terms"),
        footer: Text("Comma separated words the transcriber should favour, for example tool names or project jargon.")
      ) {
        TextField("Claude, kubectl, Blink", text: $settings.keyterms)
          .autocapitalization(.none)
          .disableAutocorrection(true)
      }
    }
    .listStyle(GroupedListStyle())
    .navigationBarTitle("Voice Input")
  }

  private func _checkKey() {
    _checking = true
    _checkStatus = nil
    let transcriber = ElevenLabsTranscriber(apiKey: settings.apiKey)
    Task {
      let result: String
      do {
        result = try await transcriber.checkAPIKey()
      } catch {
        result = error.localizedDescription
      }
      await MainActor.run {
        _checkStatus = result
        _checking = false
      }
    }
  }
}
