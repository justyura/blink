//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K   P R O
//
// Floating pill that shows the voice input state over the terminal.
//
//////////////////////////////////////////////////////////////////////////////////

import UIKit

final class VoiceInputHUD: UIView {
  enum Style {
    case listening
    case transcribing
    case success
    case failure
  }

  private let _blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
  private let _icon = UIImageView()
  private let _label = UILabel()
  private let _level = UIView()
  private var _levelWidth: NSLayoutConstraint!
  private var _hideTask: Task<Void, Never>?

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    translatesAutoresizingMaskIntoConstraints = false
    layer.cornerRadius = 18
    layer.cornerCurve = .continuous
    clipsToBounds = true

    _blur.translatesAutoresizingMaskIntoConstraints = false
    addSubview(_blur)

    _icon.translatesAutoresizingMaskIntoConstraints = false
    _icon.contentMode = .scaleAspectFit
    _icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)

    _label.translatesAutoresizingMaskIntoConstraints = false
    _label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
    _label.textColor = .label
    _label.numberOfLines = 1
    _label.lineBreakMode = .byTruncatingTail

    _level.translatesAutoresizingMaskIntoConstraints = false
    _level.backgroundColor = UIColor.systemRed.withAlphaComponent(0.35)

    _blur.contentView.addSubview(_level)
    _blur.contentView.addSubview(_icon)
    _blur.contentView.addSubview(_label)

    _levelWidth = _level.widthAnchor.constraint(equalToConstant: 0)

    NSLayoutConstraint.activate([
      _blur.topAnchor.constraint(equalTo: topAnchor),
      _blur.bottomAnchor.constraint(equalTo: bottomAnchor),
      _blur.leadingAnchor.constraint(equalTo: leadingAnchor),
      _blur.trailingAnchor.constraint(equalTo: trailingAnchor),

      _level.leadingAnchor.constraint(equalTo: _blur.contentView.leadingAnchor),
      _level.topAnchor.constraint(equalTo: _blur.contentView.topAnchor),
      _level.bottomAnchor.constraint(equalTo: _blur.contentView.bottomAnchor),
      _levelWidth,

      _icon.leadingAnchor.constraint(equalTo: _blur.contentView.leadingAnchor, constant: 14),
      _icon.centerYAnchor.constraint(equalTo: _blur.contentView.centerYAnchor),
      _icon.widthAnchor.constraint(equalToConstant: 20),

      _label.leadingAnchor.constraint(equalTo: _icon.trailingAnchor, constant: 8),
      _label.trailingAnchor.constraint(equalTo: _blur.contentView.trailingAnchor, constant: -16),
      _label.topAnchor.constraint(equalTo: _blur.contentView.topAnchor, constant: 9),
      _label.bottomAnchor.constraint(equalTo: _blur.contentView.bottomAnchor, constant: -9),
      widthAnchor.constraint(lessThanOrEqualToConstant: 420),
      heightAnchor.constraint(equalToConstant: 36),
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func set(style: Style, text: String) {
    _hideTask?.cancel()
    _label.text = text
    _icon.layer.removeAllAnimations()
    _icon.alpha = 1

    switch style {
    case .listening:
      _icon.image = UIImage(systemName: "mic.fill")
      _icon.tintColor = .systemRed
      _pulseIcon()
    case .transcribing:
      _icon.image = UIImage(systemName: "waveform")
      _icon.tintColor = .systemBlue
      _pulseIcon()
      setLevel(0)
    case .success:
      _icon.image = UIImage(systemName: "checkmark.circle.fill")
      _icon.tintColor = .systemGreen
      setLevel(0)
    case .failure:
      _icon.image = UIImage(systemName: "exclamationmark.triangle.fill")
      _icon.tintColor = .systemOrange
      setLevel(0)
    }
  }

  /// level in 0...1
  func setLevel(_ level: CGFloat) {
    let clamped = max(0, min(1, level))
    _levelWidth.constant = bounds.width * clamped
    UIView.animate(withDuration: 0.08) { self.layoutIfNeeded() }
  }

  private func _pulseIcon() {
    UIView.animate(
      withDuration: 0.7,
      delay: 0,
      options: [.repeat, .autoreverse, .allowUserInteraction, .curveEaseInOut]
    ) {
      self._icon.alpha = 0.35
    }
  }

  // MARK: - Presentation

  static func show(in window: UIWindow, style: Style, text: String) -> VoiceInputHUD {
    let hud: VoiceInputHUD
    if let existing = window.subviews.compactMap({ $0 as? VoiceInputHUD }).first {
      hud = existing
      window.bringSubviewToFront(hud)
    } else {
      hud = VoiceInputHUD(frame: .zero)
      hud.alpha = 0
      hud.transform = CGAffineTransform(translationX: 0, y: -12)
      window.addSubview(hud)
      NSLayoutConstraint.activate([
        hud.centerXAnchor.constraint(equalTo: window.centerXAnchor),
        hud.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 12),
        hud.leadingAnchor.constraint(greaterThanOrEqualTo: window.leadingAnchor, constant: 16),
      ])
      window.layoutIfNeeded()
      UIView.animate(withDuration: 0.2) {
        hud.alpha = 1
        hud.transform = .identity
      }
    }
    hud.set(style: style, text: text)
    return hud
  }

  func hide(after delay: TimeInterval = 0) {
    _hideTask?.cancel()
    _hideTask = Task { @MainActor [weak self] in
      if delay > 0 {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      }
      guard !Task.isCancelled, let self = self else { return }
      UIView.animate(withDuration: 0.2, animations: {
        self.alpha = 0
        self.transform = CGAffineTransform(translationX: 0, y: -12)
      }, completion: { _ in
        self.removeFromSuperview()
      })
    }
  }
}
