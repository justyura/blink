//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K   P R O
//
// Main window that intercepts the browser toggle keys before they reach the
// WKWebView. WebKit forwards hardware keys to the web content process and only
// falls back to the responder chain once that process answers, so a hung page
// would otherwise swallow Option+C and Cmd+W. Handling them in sendEvent also
// works while the address field (which lives in the navigation bar, outside
// BrowserController's responder chain) is being edited.
//
//////////////////////////////////////////////////////////////////////////////////

import UIKit

final class ProWindow: UIWindow {

  override func sendEvent(_ event: UIEvent) {
    if event.type == .presses, let pressesEvent = event as? UIPressesEvent, _handleBrowserKeys(pressesEvent) {
      return
    }
    super.sendEvent(event)
  }

  private func _handleBrowserKeys(_ event: UIPressesEvent) -> Bool {
    guard
      let presenter = rootViewController,
      presenter.presentedViewController === ProBrowser.shared.navigation
    else { return false }

    var swallow = false
    for press in event.allPresses {
      guard let key = press.key else { continue }
      let mods = key.modifierFlags.intersection([.command, .alternate, .shift, .control])
      let input = key.charactersIgnoringModifiers.lowercased()

      let hide = (mods == .alternate && input == "c") || (mods == .command && input == "w")
      let reset = mods == [.alternate, .shift] && input == "c"
      let stop = mods == .command && input == "."
      guard hide || reset || stop else { continue }

      swallow = true
      guard press.phase == .began else { continue }

      if stop {
        ProBrowser.shared.controller().webView?.stopLoading()
      } else if reset {
        ProBrowser.shared.reset(dismissingFrom: presenter)
      } else {
        presenter.dismiss(animated: true) {
          (presenter as? SpaceController)?.focusOnShellAction()
        }
      }
    }
    return swallow
  }
}
