//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K   P R O
//
// Tracks the right Shift key on a hardware keyboard and turns a "solo" press
// (no other key pressed while it is held) into a voice input trigger.
//
//////////////////////////////////////////////////////////////////////////////////

import UIKit

@MainActor
final class VoiceShiftTracker {
  /// How long right Shift must be held alone before push-to-talk starts recording.
  /// Keeps normal Shift+key chords from flashing the microphone.
  static let pushToTalkHoldDelay: TimeInterval = 0.2

  private var _shiftDown = false
  private var _solo = false
  private var _holdTask: Task<Void, Never>?

  private static func _isRightShift(_ press: UIPress) -> Bool {
    press.key?.keyCode == .keyboardRightShift
  }

  func pressesBegan(_ presses: Set<UIPress>) {
    let settings = VoiceInputSettings.shared
    guard settings.enabled else { return }

    let hasRightShift = presses.contains(where: Self._isRightShift)
    let hasOtherKeys = presses.contains { !Self._isRightShift($0) }

    if hasRightShift && !hasOtherKeys && !_shiftDown {
      _shiftDown = true
      _solo = true
      if settings.mode == .pushToTalk {
        _holdTask?.cancel()
        _holdTask = Task { @MainActor [weak self] in
          try? await Task.sleep(nanoseconds: UInt64(Self.pushToTalkHoldDelay * 1_000_000_000))
          guard !Task.isCancelled, let self = self, self._shiftDown, self._solo else { return }
          VoiceInputManager.shared.beginPushToTalk()
        }
      }
      return
    }

    if hasOtherKeys && _shiftDown {
      _breakSolo()
    }
  }

  func pressesEnded(_ presses: Set<UIPress>) {
    guard presses.contains(where: Self._isRightShift), _shiftDown else { return }
    _shiftDown = false
    _holdTask?.cancel()
    _holdTask = nil

    guard _solo else { return }
    _solo = false

    let settings = VoiceInputSettings.shared
    guard settings.enabled else { return }

    switch settings.mode {
    case .pushToTalk:
      VoiceInputManager.shared.endPushToTalk()
    case .toggle:
      VoiceInputManager.shared.toggle()
    }
  }

  func pressesCancelled(_ presses: Set<UIPress>) {
    guard presses.contains(where: Self._isRightShift), _shiftDown else { return }
    _shiftDown = false
    _breakSolo()
  }

  private func _breakSolo() {
    _solo = false
    _holdTask?.cancel()
    _holdTask = nil
    let manager = VoiceInputManager.shared
    if manager.isPushToTalkRecording {
      manager.cancel()
    }
  }
}
