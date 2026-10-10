//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K   P R O
//
// Settings for the Pro features (browser, host jumper). Persisted in UserDefaults.
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation
import Combine

enum SearchEngine: String, CaseIterable, Identifiable {
  case google, duckduckgo, bing, kagi, baidu, custom
  var id: String { rawValue }

  var title: String {
    switch self {
    case .google: return "Google"
    case .duckduckgo: return "DuckDuckGo"
    case .bing: return "Bing"
    case .kagi: return "Kagi"
    case .baidu: return "百度"
    case .custom: return "Custom"
    }
  }

  /// URL template with `%s` standing for the percent-encoded query.
  var template: String? {
    switch self {
    case .google: return "https://www.google.com/search?q=%s"
    case .duckduckgo: return "https://duckduckgo.com/?q=%s"
    case .bing: return "https://www.bing.com/search?q=%s"
    case .kagi: return "https://kagi.com/search?q=%s"
    case .baidu: return "https://www.baidu.com/s?wd=%s"
    case .custom: return nil
    }
  }
}

enum BrowserTheme: String, CaseIterable, Identifiable {
  case system, dark, forceDark
  var id: String { rawValue }

  var title: String {
    switch self {
    case .system: return "System"
    case .dark: return "Dark"
    case .forceDark: return "Force Dark"
    }
  }

  var usageHint: String {
    switch self {
    case .system: return "Pages follow the iPad appearance."
    case .dark: return "Pages that support dark mode render dark."
    case .forceDark: return "Every page is inverted to dark, images are kept normal. Best for reading at night."
    }
  }
}

enum HostConnectCommand: String, CaseIterable, Identifiable {
  case ssh, mosh
  var id: String { rawValue }
  var title: String { rawValue }
}

final class ProSettings: ObservableObject {
  static let shared = ProSettings()

  private enum Keys {
    static let searchEngine = "blinkpro.searchEngine"
    static let customSearchURL = "blinkpro.customSearchURL"
    static let browserTheme = "blinkpro.browserTheme"
    static let vimKeys = "blinkpro.browserVimKeys"
    static let hostConnect = "blinkpro.hostConnect"
  }

  private let _d = UserDefaults.standard

  @Published var searchEngine: SearchEngine {
    didSet { _d.set(searchEngine.rawValue, forKey: Keys.searchEngine) }
  }

  /// Used when `searchEngine == .custom`. `%s` is replaced by the query.
  @Published var customSearchURL: String {
    didSet { _d.set(customSearchURL, forKey: Keys.customSearchURL) }
  }

  @Published var browserTheme: BrowserTheme {
    didSet { _d.set(browserTheme.rawValue, forKey: Keys.browserTheme) }
  }

  /// j/k scrolling, f link hints and friends inside the built-in browser.
  @Published var browserVimKeys: Bool {
    didSet { _d.set(browserVimKeys, forKey: Keys.vimKeys) }
  }

  /// Command used by the host jumper to connect to a host.
  @Published var hostConnect: HostConnectCommand {
    didSet { _d.set(hostConnect.rawValue, forKey: Keys.hostConnect) }
  }

  /// The effective search URL template (`%s` placeholder).
  var searchTemplate: String {
    if searchEngine == .custom {
      let custom = customSearchURL.trimmingCharacters(in: .whitespaces)
      if custom.contains("%s") { return custom }
      if !custom.isEmpty { return custom + "%s" }
    }
    return searchEngine.template ?? SearchEngine.google.template!
  }

  private init() {
    let d = UserDefaults.standard
    searchEngine = SearchEngine(rawValue: d.string(forKey: Keys.searchEngine) ?? "") ?? .google
    customSearchURL = d.string(forKey: Keys.customSearchURL) ?? ""
    browserTheme = BrowserTheme(rawValue: d.string(forKey: Keys.browserTheme) ?? "") ?? .system
    browserVimKeys = d.object(forKey: Keys.vimKeys) as? Bool ?? true
    hostConnect = HostConnectCommand(rawValue: d.string(forKey: Keys.hostConnect) ?? "") ?? .ssh
  }
}
