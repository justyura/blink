//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016-2019 Blink Mobile Shell Project
//
// This file is part of Blink.
//
// Blink is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Blink is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Blink. If not, see <http://www.gnu.org/licenses/>.
//
// In addition, Blink is also subject to certain additional terms under
// GNU GPL version 3 section 7.
//
// You should have received a copy of these additional terms immediately
// following the terms and conditions of the GNU General Public License
// which accompanied the Blink Source Code. If not, see
// <http://www.github.com/blinksh/blink>.
//
////////////////////////////////////////////////////////////////////////////////


import Foundation
import UIKit
import WebKit

@objc public class BrowserController: UIViewController, UITextFieldDelegate {

  /// Search engine template from Settings › Blink Pro (`%s` is the query).
  static var searchTemplate: String { ProSettings.shared.searchTemplate }

  /// Turns typed text into a URL: full URLs and host-like strings load directly,
  /// everything else becomes a search.
  static func url(forInput raw: String) -> URL? {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    if text.contains("://"), let url = URL(string: text) { return url }
    let looksLikeHost = !text.contains(" ") &&
      (text.contains(".") || text.hasPrefix("localhost")) &&
      !text.hasPrefix(".") && !text.hasSuffix(".")
    if looksLikeHost, let url = URL(string: "https://\(text)") { return url }
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&+=?#")
    let q = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    return URL(string: searchTemplate.replacingOccurrences(of: "%s", with: q))
  }

  private var _urlObservation: NSKeyValueObservation?
  private var _watchdog: Timer?
  private var _pendingPing: Date?
  /// True when the page stopped answering JavaScript pings; keys then bypass the web view.
  private(set) var isHung = false
  private let _addressField = ProAddressField()

  
  @objc public var webView: WKWebView? = nil {
    didSet {
      oldValue?.removeFromSuperview()
      _urlObservation = nil
      if let web = webView {
        view.insertSubview(web, at: 0)
        _urlObservation = web.observe(\.url, options: [.initial, .new]) { [weak self] wv, _ in
          guard let self = self, !self._addressField.isFirstResponder else { return }
          self._addressField.text = wv.url?.absoluteString
        }
      }
    }
  }
  
  public override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground

    _addressField.borderStyle = .roundedRect
    _addressField.placeholder = "Search or enter a URL"
    _addressField.keyboardType = .webSearch
    _addressField.returnKeyType = .go
    _addressField.autocapitalizationType = .none
    _addressField.autocorrectionType = .no
    _addressField.clearButtonMode = .whileEditing
    _addressField.font = UIFont.systemFont(ofSize: 15)
    _addressField.delegate = self
    _addressField.onEscape = { [weak self] in
      guard let self = self else { return }
      self._addressField.text = self.webView?.url?.absoluteString
      self._addressField.resignFirstResponder()
    }
    _addressField.frame = CGRect(x: 0, y: 0, width: 720, height: 34)
    _addressField.autoresizingMask = [.flexibleWidth]
    navigationItem.titleView = _addressField

    navigationItem.leftBarButtonItems = [
      UIBarButtonItem(
        image: UIImage(systemName: "arrow.left"),
        style: .plain,
        target: self,
        action: #selector(_goBack)
      ),
      UIBarButtonItem(
        image: UIImage(systemName: "arrow.right"),
        style: .plain,
        target: self,
        action: #selector(_goForward)
      ),
    ]
    
    navigationItem.rightBarButtonItems = [
      UIBarButtonItem(
        barButtonSystemItem: .close,
        target: self,
        action: #selector(_close)
      ),
      UIBarButtonItem(
        barButtonSystemItem: .refresh,
        target: self,
        action: #selector(_reload)
      ),
      UIBarButtonItem(
        image: UIImage(systemName: "safari"),
        style: .plain,
        target: self,
        action: #selector(_openBrowser)
      ),
    ]
    
  }
  
  public override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    webView?.frame = self.view.bounds
  }

  public override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    _focusPage()
    _watchdog?.invalidate()
    _watchdog = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?._ping() }
  }

  public override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    _watchdog?.invalidate()
    _watchdog = nil
    _pendingPing = nil
  }

  public func textFieldDidEndEditing(_ textField: UITextField) {
    _focusPage()
  }

  /// Keys normally go to the page. While it is hung they go to the navigation
  /// controller instead, whose key commands do not depend on the web process.
  private func _focusPage() {
    if isHung {
      navigationController?.becomeFirstResponder()
    } else {
      webView?.becomeFirstResponder()
    }
  }

  private func _ping() {
    guard let webView = webView, !_addressField.isFirstResponder else { return }
    if let started = _pendingPing {
      if Date().timeIntervalSince(started) > 3 { _setHung(true) }
      return
    }
    _pendingPing = Date()
    webView.evaluateJavaScript("1") { [weak self] _, _ in
      guard let self = self else { return }
      self._pendingPing = nil
      if self.isHung { self._setHung(false) }
    }
  }

  private func _setHung(_ hung: Bool) {
    guard hung != isHung else { return }
    isHung = hung
    navigationItem.prompt = hung ? "Page not responding · ⌥⇧C resets · ⌥C hides" : nil
    _focusPage()
  }

  // MARK: - Messages from the injected Vim script

  func handleScriptMessage(action: String, payload: Any?) {
    switch action {
    case "address": _focusAddress()
    case "close": _close()
    case "reset": ProBrowser.shared.reset(dismissingFrom: presentingViewController)
    case "stop": webView?.stopLoading()
    case "copyURL":
      if let s = payload as? String { UIPasteboard.general.string = s }
    default: break
    }
  }
  
  public override var canBecomeFirstResponder: Bool { true }

  public override var keyCommands: [UIKeyCommand]? {
    let cmds = [
      UIKeyCommand(title: "Address", action: #selector(_focusAddress), input: "l", modifierFlags: .command),
      UIKeyCommand(title: "Address", action: #selector(_focusAddress), input: "o", modifierFlags: .alternate),
      UIKeyCommand(title: "Close", action: #selector(_close), input: "w", modifierFlags: .command),
      UIKeyCommand(title: "Hide", action: #selector(_close), input: "c", modifierFlags: .alternate),
      UIKeyCommand(title: "Reload", action: #selector(_reload), input: "r", modifierFlags: .command),
      UIKeyCommand(title: "Back", action: #selector(_goBack), input: "[", modifierFlags: .command),
      UIKeyCommand(title: "Forward", action: #selector(_goForward), input: "]", modifierFlags: .command),
    ]
    cmds.forEach { $0.wantsPriorityOverSystemBehavior = true }
    if _addressField.isFirstResponder {
      let esc = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(_escape))
      esc.wantsPriorityOverSystemBehavior = true
      return cmds + [esc]
    }
    return cmds
  }

  @objc public func load(_ url: URL) {
    webView?.load(URLRequest(url: url))
  }

  func loadStartPage() {
    webView?.loadHTMLString(BrowserVimScript.startPageHTML, baseURL: nil)
  }

  @objc func _focusAddress() {
    _addressField.becomeFirstResponder()
    _addressField.selectAll(nil)
  }

  @objc func _escape() {
    if _addressField.isFirstResponder {
      _addressField.text = webView?.url?.absoluteString
      _addressField.resignFirstResponder()
    } else {
      _close()
    }
  }

  @objc func _goBack() {
    webView?.goBack()
  }
  
  @objc func _goForward() {
    webView?.goForward()
  }
  
  @objc func _reload() {
    webView?.reloadFromOrigin()
  }
  
  @objc func _close() {
    // Dismiss from the presenter so the whole browser goes away, including anything
    // the page may have presented on top (select popovers, pickers, autofill).
    // Calling dismiss on this controller would only close that top layer.
    let presenter = navigationController?.presentingViewController ?? presentingViewController
    guard let presenter = presenter else {
      dismiss(animated: true)
      return
    }
    presenter.dismiss(animated: true) {
      if let sp = presenter as? SpaceController {
        sp.focusOnShellAction()
      } else {
        UIApplication.shared.sendAction(#selector(SpaceController.focusOnShellAction), to: nil, from: nil, for: nil)
      }
    }
  }
  
  @objc func _openBrowser() {
    if let url = webView?.url {
      blink_openurl(url)
    }
  }

  // MARK: - UITextFieldDelegate

  public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    if let url = Self.url(forInput: textField.text ?? "") {
      load(url)
    }
    textField.resignFirstResponder()
    return true
  }
}

/// Address field that handles Esc itself: the navigation bar is not in the
/// BrowserController responder chain, so the controller's key commands never
/// see keys typed here.
final class ProAddressField: UITextField {
  var onEscape: () -> Void = {}

  override var keyCommands: [UIKeyCommand]? {
    let esc = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(_escape))
    esc.wantsPriorityOverSystemBehavior = true
    return [esc]
  }

  @objc private func _escape() { onEscape() }
}
