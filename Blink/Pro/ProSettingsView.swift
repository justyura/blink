//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K   P R O
//
// Settings › Blink Pro
//
//////////////////////////////////////////////////////////////////////////////////

import SwiftUI

struct ProSettingsView: View {
  @ObservedObject private var settings = ProSettings.shared

  var body: some View {
    List {
      Section(
        header: Text("Host Jumper (⌥F)"),
        footer: Text("Lists the hosts from ~/.ssh/config (use ssh-import to sync them) and Blink's Hosts. Picking a host jumps to its open session or connects with \(settings.hostConnect.title). \"local\" returns to a plain Blink shell.")
      ) {
        Picker("Connect with", selection: $settings.hostConnect) {
          ForEach(HostConnectCommand.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(SegmentedPickerStyle())
      }

      Section(
        header: Text("Web Search (⌥O)"),
        footer: Text(settings.searchEngine == .custom
                     ? "Custom URL with %s where the query goes, for example https://www.perplexity.ai/search?q=%s"
                     : "Typed text that looks like a URL opens directly, anything else is searched.")
      ) {
        Picker("Search engine", selection: $settings.searchEngine) {
          ForEach(SearchEngine.allCases) { Text($0.title).tag($0) }
        }
        if settings.searchEngine == .custom {
          TextField("https://example.com/search?q=%s", text: $settings.customSearchURL)
            .keyboardType(.URL)
            .autocapitalization(.none)
            .disableAutocorrection(true)
        }
      }

      Section(
        header: Text("Browser"),
        footer: Text(settings.browserTheme.usageHint + (settings.browserVimKeys ? "\n\nKeys: j/k scroll · d/u half page · gg/G top/bottom · f link hints · H/L back/forward · r reload · o address bar · x close · esc dismiss." : ""))
      ) {
        Picker("Night mode", selection: $settings.browserTheme) {
          ForEach(BrowserTheme.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(SegmentedPickerStyle())
        Toggle("Vim keys & link hints", isOn: $settings.browserVimKeys)
      }
    }
    .listStyle(GroupedListStyle())
    .navigationBarTitle("Blink Pro")
  }
}
