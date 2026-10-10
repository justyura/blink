//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K   P R O
//
// Session jumper, host jumper, web search bar and app hopping on top of
// SpaceController.
//
//////////////////////////////////////////////////////////////////////////////////

import UIKit
import WebKit

/// Remembers which host a session was opened for by the host jumper.
enum ProSessionHosts {
  static var hostBySession: [UUID: String] = [:]
}

struct ProHost {
  let alias: String
  let hostName: String
}

extension SpaceController {

  // MARK: - Global key commands (reachable even when the terminal is not focused)

  private static var _proGlobalCommandsCache: [UIKeyCommand]? = nil

  func proGlobalKeyCommands() -> [UIKeyCommand] {
    if let cached = Self._proGlobalCommandsCache { return cached }
    let wanted: [Command] = [.openCanvas, .hostJumper, .sessionSwitcher, .webSearch, .toggleBrowser]
    let cmds: [UIKeyCommand] = KBTracker.shared.loadConfig().shortcuts.compactMap { shortcut -> UIKeyCommand? in
      guard case .command(let c) = shortcut.action, wanted.contains(c), !shortcut.input.isEmpty else { return nil }
      let cmd = UIKeyCommand(
        title: c.title,
        action: #selector(_onProGlobalCommand(_:)),
        input: shortcut.input,
        modifierFlags: shortcut.modifiers,
        propertyList: ["ProCommand": c.rawValue]
      )
      cmd.wantsPriorityOverSystemBehavior = true
      return cmd
    }
    Self._proGlobalCommandsCache = cmds
    return cmds
  }

  @objc func _onProGlobalCommand(_ sender: UIKeyCommand) {
    guard
      let dict = sender.propertyList as? [String: String],
      let raw = dict["ProCommand"],
      let cmd = Command(rawValue: raw)
    else { return }
    _onCommand(cmd)
  }

  // MARK: - Session jumper (Option+J)

  /// One row per open session, in viewport order.
  func proSessionItems() -> [PaletteItem] {
    _viewportsKeys.enumerated().map { idx, key in
      let term: TermController = SessionRegistry.shared[key]
      let title = term.termView.title?.trimmingCharacters(in: .whitespaces) ?? ""
      let host = ProSessionHosts.hostBySession[key]
      let fallback = host.map { "\(ProSettings.shared.hostConnect.title) \($0)" } ?? (term.proIsRunningCommand ? "Shell \(idx + 1)" : "local")
      let hasTitle = !(title.isEmpty || title == "blink")
      return PaletteItem(
        id: key.uuidString,
        badge: "\(idx + 1)",
        title: hasTitle ? title : fallback,
        subtitle: hasTitle ? fallback : "",
        isCurrent: key == _currentKey
      )
    }
  }

  @objc func showSessionSwitcherAction() {
    let sp = _interactiveSpaceController()
    if sp._proPaletteVC != nil {
      sp._dismissProPalette()
      return
    }
    let items = sp.proSessionItems()
    let model = PaletteModel(
      title: "\(items.count) sessions",
      placeholder: "Jump to session…",
      footer: "↑↓ select · ⏎ switch · type a number or host · esc close",
      items: items
    )
    model.onSubmit = { [weak sp] _, item in
      guard let sp = sp else { return }
      sp._dismissProPalette()
      if let item = item, let key = UUID(uuidString: item.id) {
        sp._moveToShell(key: key)
      }
    }
    model.onCancel = { [weak sp] in sp?._dismissProPalette() }
    sp._presentProPalette(model: model)
  }

  // MARK: - Host jumper (Option+F)

  /// Hosts from ~/.ssh/config plus Blink's Hosts, deduplicated by alias.
  static func proKnownHosts() -> [ProHost] {
    var byAlias: [String: ProHost] = [:]
    var order: [String] = []

    func add(_ alias: String, _ hostName: String) {
      let a = alias.trimmingCharacters(in: .whitespaces)
      guard !a.isEmpty, !a.contains("*"), !a.contains("?"), !a.hasPrefix("!") else { return }
      if byAlias[a] == nil { order.append(a) }
      byAlias[a] = ProHost(alias: a, hostName: hostName)
    }

    if let sshDir = BlinkPaths.ssh(),
       let text = try? String(contentsOfFile: (sshDir as NSString).appendingPathComponent("config"), encoding: .utf8) {
      var pendingAliases: [String] = []
      var pendingHostName = ""
      func flush() {
        for a in pendingAliases { add(a, pendingHostName) }
        pendingAliases = []; pendingHostName = ""
      }
      for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") { continue }
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "=" }).map(String.init)
        guard let key = parts.first?.lowercased() else { continue }
        if key == "host" {
          flush()
          pendingAliases = Array(parts.dropFirst())
        } else if key == "hostname", parts.count > 1 {
          pendingHostName = parts[1]
        }
      }
      flush()
    }

    for h in BKHosts.allHosts() {
      add(h.host, h.hostName ?? "")
    }

    return order.compactMap { byAlias[$0] }
  }

  /// The session that belongs to a host alias, if one is open.
  func proSession(forHost alias: String) -> UUID? {
    let a = alias.lowercased()
    if let (key, _) = ProSessionHosts.hostBySession.first(where: { $0.value.lowercased() == a && _viewportsKeys.contains($0.key) }) {
      return key
    }
    // Fall back to the terminal title (typically user@host).
    return _viewportsKeys.first { key in
      let term: TermController = SessionRegistry.shared[key]
      let title = (term.termView.title ?? "").lowercased()
      return title.contains("@\(a)") || title.hasPrefix("\(a):") || title.hasPrefix("\(a) ")
    }
  }

  /// A session sitting at the plain Blink prompt.
  func proLocalSession() -> UUID? {
    if let current = _currentKey, !(SessionRegistry.shared[current] as TermController).proIsRunningCommand {
      return current
    }
    return _viewportsKeys.first { key in
      !(SessionRegistry.shared[key] as TermController).proIsRunningCommand
    }
  }

  @objc func showHostJumperAction() {
    let sp = _interactiveSpaceController()
    if sp._proPaletteVC != nil {
      sp._dismissProPalette()
      return
    }

    let hosts = Self.proKnownHosts()
    var items: [PaletteItem] = []
    let localKey = sp.proLocalSession()
    items.append(PaletteItem(
      id: "local",
      badge: "⌂",
      title: "local",
      subtitle: localKey == nil ? "new Blink shell" : "Blink shell",
      isCurrent: localKey != nil && localKey == sp._currentKey
    ))
    for h in hosts {
      let open = sp.proSession(forHost: h.alias)
      let idx = open.flatMap { sp._viewportsKeys.firstIndex(of: $0) }
      items.append(PaletteItem(
        id: "host:\(h.alias)",
        badge: idx.map { "\($0 + 1)" } ?? "→",
        title: h.alias,
        subtitle: open != nil ? "connected · session \((idx ?? 0) + 1)" : (h.hostName.isEmpty ? "" : h.hostName),
        isCurrent: open != nil && open == sp._currentKey
      ))
    }

    let model = PaletteModel(
      title: "\(hosts.count) hosts",
      placeholder: "Host name…",
      footer: "⏎ jump to the host's session, or connect with \(ProSettings.shared.hostConnect.title) · \"local\" = Blink shell · esc close",
      items: items
    )
    model.onSubmit = { [weak sp] query, item in
      guard let sp = sp else { return }
      sp._dismissProPalette()
      let typed = query.trimmingCharacters(in: .whitespaces)
      if let item = item {
        if item.id == "local" { sp.proJumpToLocal(); return }
        sp.proJump(toHost: String(item.id.dropFirst("host:".count)))
      } else if !typed.isEmpty {
        if typed.lowercased() == "local" { sp.proJumpToLocal() } else { sp.proJump(toHost: typed) }
      }
    }
    model.onCancel = { [weak sp] in sp?._dismissProPalette() }
    sp._presentProPalette(model: model)
  }

  func proJump(toHost alias: String) {
    if let key = proSession(forHost: alias) {
      _moveToShell(key: key)
      return
    }
    let command = "\(ProSettings.shared.hostConnect.rawValue) \(alias)"
    _newShellAction(command: command)
    if let key = _currentKey {
      ProSessionHosts.hostBySession[key] = alias
    }
  }

  func proJumpToLocal() {
    if let key = proLocalSession() {
      _moveToShell(key: key)
    } else {
      _newShellAction()
    }
  }

  // MARK: - Web search (Option+O)

  @objc func showWebSearchAction() {
    let sp = _interactiveSpaceController()
    if sp._proPaletteVC != nil {
      sp._dismissProPalette()
      return
    }
    let model = PaletteModel(
      title: ProSettings.shared.searchEngine.title,
      placeholder: "Search or enter a URL",
      footer: "⏎ open in the built-in browser · esc close"
    )
    model.onSubmit = { [weak sp] query, _ in
      guard let sp = sp else { return }
      sp._dismissProPalette()
      let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !q.isEmpty, let url = BrowserController.url(forInput: q) else { return }
      sp.proOpenBrowser(url: url)
    }
    model.onCancel = { [weak sp] in sp?._dismissProPalette() }
    sp._presentProPalette(model: model)
  }

  /// Loads a URL in the persistent built-in browser and shows it.
  func proOpenBrowser(url: URL) {
    let sp = _interactiveSpaceController()
    let browser = ProBrowser.shared.controller()
    browser.load(url)
    sp._presentProBrowser()
  }

  /// Option+C: show the browser (last page kept) or hide it.
  @objc func toggleBrowserAction() {
    let sp = _interactiveSpaceController()
    if ProBrowser.shared.navigation.presentingViewController != nil {
      // Hide, including anything the page presented on top of the browser.
      let presenter = ProBrowser.shared.navigation.presentingViewController ?? sp
      presenter.dismiss(animated: true) { sp.focusOnShellAction() }
      return
    }
    let browser = ProBrowser.shared.controller()
    let firstUse = browser.webView?.url == nil
    if firstUse {
      browser.loadStartPage()
    }
    sp._presentProBrowser(focusAddress: firstUse)
  }

  func _presentProBrowser(focusAddress: Bool = false) {
    guard presentedViewController == nil else { return }
    currentTerm()?.resignInput()
    present(ProBrowser.shared.navigation, animated: true) {
      if focusAddress { ProBrowser.shared.controller()._focusAddress() }
    }
  }

  // MARK: - App hopping (Option+B)

  @objc func openCanvasSimpleAction() {
    // Open directly on the main thread: no extra dispatch, so the hop starts immediately.
    UIApplication.shared.open(URL(string: "canvassimple://")!, options: [:], completionHandler: nil)
  }

  // MARK: - Palette plumbing

  func _presentProPalette(model: PaletteModel) {
    view.window?.makeKeyAndVisible()
    let ctrl = PaletteViewController(model: model)
    ctrl.view.frame = _overlay.frame
    ctrl.willMove(toParent: self)
    view.addSubview(ctrl.view)
    addChild(ctrl)
    ctrl.didMove(toParent: self)
    _proPaletteVC = ctrl
    _isSnipsInputModeActive = true
    ctrl.becomeFirstResponder()
  }

  func _dismissProPalette() {
    guard let ctrl = _proPaletteVC else { return }
    ctrl.willMove(toParent: nil)
    ctrl.view.removeFromSuperview()
    ctrl.removeFromParent()
    ctrl.didMove(toParent: nil)
    _proPaletteVC = nil
    _isSnipsInputModeActive = false
    focusOnShellAction()
  }
}

/// Weak proxy so WKUserContentController does not retain the browser controller.
final class ProScriptMessageProxy: NSObject, WKScriptMessageHandler {
  private weak var _target: BrowserController?

  init(_ target: BrowserController) {
    _target = target
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
    _target?.handleScriptMessage(action: action, payload: body["payload"])
  }
}

/// The one built-in browser instance. Hidden with Option+C or Close, it keeps its page
/// and history, so toggling it back is instant. Rebuilt when browser settings change.
final class ProBrowser {
  static let shared = ProBrowser()

  private(set) var navigation: UINavigationController = ProBrowserNavigationController()
  private var _controller: BrowserController? = nil
  private var _signature = ""

  private init() {}

  private var _currentSignature: String {
    let s = ProSettings.shared
    return "\(s.browserVimKeys)|\(s.browserTheme.rawValue)"
  }

  /// Drops the current web view (for example when a page hung) so the next
  /// use starts from a fresh one.
  func reset(dismissingFrom presenter: UIViewController?) {
    let nav = navigation
    _controller?.webView?.stopLoading()
    _controller = nil
    _signature = ""
    navigation = ProBrowserNavigationController()
    if presenter?.presentedViewController === nav {
      presenter?.dismiss(animated: true) {
        (presenter as? SpaceController)?.focusOnShellAction()
      }
    }
  }

  func controller() -> BrowserController {
    if let c = _controller, _signature == _currentSignature { return c }

    let settings = ProSettings.shared
    let config = WKWebViewConfiguration()
    config.allowsInlineMediaPlayback = true
    let browser = BrowserController()
    config.userContentController.add(ProScriptMessageProxy(browser), name: BrowserVimScript.messageHandler)
    config.userContentController.addUserScript(
      WKUserScript(source: BrowserVimScript.hotkeys, injectionTime: .atDocumentStart, forMainFrameOnly: false))
    if settings.browserVimKeys {
      config.userContentController.addUserScript(
        WKUserScript(source: BrowserVimScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }
    if settings.browserTheme == .forceDark {
      config.userContentController.addUserScript(
        WKUserScript(source: BrowserVimScript.forceDarkCSS, injectionTime: .atDocumentStart, forMainFrameOnly: false))
    }

    let webView = WKWebView(frame: .zero, configuration: config)
    webView.allowsBackForwardNavigationGestures = true
    if settings.browserTheme != .system {
      webView.overrideUserInterfaceStyle = .dark
    }
    browser.webView = webView

    let nav = ProBrowserNavigationController(rootViewController: browser)
    nav.modalPresentationStyle = .fullScreen
    nav.overrideUserInterfaceStyle = settings.browserTheme == .system ? .unspecified : .dark

    navigation = nav
    _controller = browser
    _signature = _currentSignature
    return browser
  }
}

/// Navigation controller for the built-in browser. It sits in the responder chain
/// of both the web view and the address field, and claims Cmd+W / Option+C with
/// priority over the system, otherwise iPadOS treats Cmd+W as "close window".
final class ProBrowserNavigationController: UINavigationController {

  override var canBecomeFirstResponder: Bool { true }

  override var keyCommands: [UIKeyCommand]? {
    let cmds = [
      UIKeyCommand(title: "Hide Browser", action: #selector(_hide), input: "w", modifierFlags: .command),
      UIKeyCommand(title: "Hide Browser", action: #selector(_hide), input: "c", modifierFlags: .alternate),
      UIKeyCommand(title: "Reset Browser", action: #selector(_reset), input: "c", modifierFlags: [.alternate, .shift]),
      UIKeyCommand(title: "Stop Loading", action: #selector(_stop), input: ".", modifierFlags: .command),
    ]
    cmds.forEach { $0.wantsPriorityOverSystemBehavior = true }
    return cmds
  }

  @objc private func _hide() {
    let presenter = presentingViewController
    presenter?.dismiss(animated: true) {
      (presenter as? SpaceController)?.focusOnShellAction()
    }
  }

  @objc private func _reset() {
    ProBrowser.shared.reset(dismissingFrom: presentingViewController)
  }

  @objc private func _stop() {
    (viewControllers.first as? BrowserController)?.webView?.stopLoading()
  }
}
