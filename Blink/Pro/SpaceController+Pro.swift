//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K   P R O
//
// Session jumper, web search bar and app hopping on top of SpaceController.
//
//////////////////////////////////////////////////////////////////////////////////

import UIKit
import WebKit

extension SpaceController {

  // MARK: - Session jumper (Option+J)

  /// One row per open session, in viewport order.
  func proSessionItems() -> [PaletteItem] {
    _viewportsKeys.enumerated().map { idx, key in
      let term: TermController = SessionRegistry.shared[key]
      let title = term.termView.title?.trimmingCharacters(in: .whitespaces) ?? ""
      let fallback = "Shell \(idx + 1)"
      return PaletteItem(
        id: key.uuidString,
        badge: "\(idx + 1)",
        title: title.isEmpty || title == "blink" ? fallback : title,
        subtitle: title.isEmpty || title == "blink" ? "" : fallback,
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

  // MARK: - Web search (Option+O)

  @objc func showWebSearchAction() {
    let sp = _interactiveSpaceController()
    if sp._proPaletteVC != nil {
      sp._dismissProPalette()
      return
    }
    let model = PaletteModel(
      title: "Web",
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

  /// Presents the built-in browser full screen over the terminal.
  func proOpenBrowser(url: URL) {
    let sp = _interactiveSpaceController()
    sp.currentTerm()?.resignInput()

    let config = WKWebViewConfiguration()
    config.allowsInlineMediaPlayback = true
    let webView = WKWebView(frame: .zero, configuration: config)
    webView.allowsBackForwardNavigationGestures = true

    let browser = BrowserController()
    browser.webView = webView
    let nav = UINavigationController(rootViewController: browser)
    nav.modalPresentationStyle = .fullScreen
    webView.load(URLRequest(url: url))
    sp.present(nav, animated: true)
  }

  // MARK: - App hopping (Option+B)

  @objc func openCanvasSimpleAction() {
    blink_openurl(URL(string: "canvassimple://")!)
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
