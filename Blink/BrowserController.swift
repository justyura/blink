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

  /// Search engine used for non-URL input. Override with the
  /// `blinkpro.searchURL` user default, e.g. "https://duckduckgo.com/?q=%@".
  static var searchTemplate: String {
    UserDefaults.standard.string(forKey: "blinkpro.searchURL") ?? "https://www.google.com/search?q=%@"
  }

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
    return URL(string: String(format: searchTemplate, q))
  }

  private var _urlObservation: NSKeyValueObservation?
  private let _addressField = UITextField()

  
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
  
  public override var canBecomeFirstResponder: Bool { true }

  public override var keyCommands: [UIKeyCommand]? {
    let cmds = [
      UIKeyCommand(title: "Address", action: #selector(_focusAddress), input: "l", modifierFlags: .command),
      UIKeyCommand(title: "Address", action: #selector(_focusAddress), input: "o", modifierFlags: .alternate),
      UIKeyCommand(title: "Close", action: #selector(_close), input: "w", modifierFlags: .command),
      UIKeyCommand(title: "Reload", action: #selector(_reload), input: "r", modifierFlags: .command),
      UIKeyCommand(title: "Back", action: #selector(_goBack), input: "[", modifierFlags: .command),
      UIKeyCommand(title: "Forward", action: #selector(_goForward), input: "]", modifierFlags: .command),
      UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(_escape)),
    ]
    cmds.forEach { $0.wantsPriorityOverSystemBehavior = true }
    return cmds
  }

  @objc public func load(_ url: URL) {
    webView?.load(URLRequest(url: url))
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
    self.dismiss(animated: true) {
      UIApplication.shared.sendAction(#selector(SpaceController.focusOnShellAction), to: nil, from: nil, for: nil)
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
