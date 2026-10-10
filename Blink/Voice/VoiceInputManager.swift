//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K   P R O
//
// Records microphone audio, sends it to a speech-to-text service and types the
// transcript into the active terminal. Triggered by the right Shift key
// (see SmarterTermInput+VoiceInput.swift).
//
//////////////////////////////////////////////////////////////////////////////////

import AVFoundation
import UIKit

@MainActor
final class VoiceInputManager: NSObject {
  static let shared = VoiceInputManager()

  enum State {
    case idle
    case recording
    case transcribing
  }

  private(set) var state: State = .idle

  /// True when the current recording was started by push-to-talk (hold).
  private(set) var isPushToTalkRecording = false

  private var _recorder: AVAudioRecorder?
  private var _recordingURL: URL?
  private var _hud: VoiceInputHUD?
  private var _meterTimer: Timer?
  private var _recordingStartedAt: Date?
  private var _speechDetected = false
  private var _lastLoudAt: Date?
  private var _sessionWasActivated = false
  private weak var _targetDevice: TermDevice?
  private var _transcribeTask: Task<Void, Never>?

  private let _settings = VoiceInputSettings.shared

  private override init() {
    super.init()
  }

  // MARK: - Public API used by the key hooks

  /// Right Shift held long enough without other keys: start recording.
  func beginPushToTalk() {
    guard state == .idle else { return }
    isPushToTalkRecording = true
    Task { await _startRecording() }
  }

  /// Right Shift released: finish the push-to-talk recording and transcribe.
  func endPushToTalk() {
    guard state == .recording, isPushToTalkRecording else { return }
    _finishRecordingAndTranscribe()
  }

  /// Right Shift tapped in toggle mode.
  func toggle() {
    switch state {
    case .idle:
      isPushToTalkRecording = false
      Task { await _startRecording() }
    case .recording:
      _finishRecordingAndTranscribe()
    case .transcribing:
      break
    }
  }

  /// Drop the current recording without transcribing (another key was pressed).
  func cancel() {
    switch state {
    case .recording:
      _stopRecorder()
      _cleanupRecordingFile()
      _dismissHUD()
      state = .idle
      isPushToTalkRecording = false
    case .transcribing:
      _transcribeTask?.cancel()
      _transcribeTask = nil
      _cleanupRecordingFile()
      _dismissHUD()
      state = .idle
    case .idle:
      break
    }
  }

  // MARK: - Recording

  private func _startRecording() async {
    guard state == .idle else { return }
    guard _settings.enabled else { return }

    _targetDevice = Self._activeDevice()

    guard _settings.hasAPIKey else {
      _flash(.failure, TranscriberError.missingAPIKey(_settings.provider.title).localizedDescription)
      isPushToTalkRecording = false
      return
    }

    let granted = await Self._requestMicrophonePermission()
    guard granted else {
      _flash(.failure, "Microphone access denied. Enable it in iOS Settings › Blink.")
      isPushToTalkRecording = false
      return
    }

    // The key may have been released while we were waiting for permission.
    guard state == .idle else { return }

    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(
        .playAndRecord,
        mode: .default,
        options: [.mixWithOthers, .allowBluetoothHFP, .defaultToSpeaker]
      )
      try session.setActive(true, options: [])
      _sessionWasActivated = true
    } catch {
      _flash(.failure, "Audio session error: \(error.localizedDescription)")
      isPushToTalkRecording = false
      return
    }

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("blink-voice-\(UUID().uuidString).m4a")
    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
      AVSampleRateKey: 16_000,
      AVNumberOfChannelsKey: 1,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      AVEncoderBitRateKey: 48_000,
    ]

    do {
      let recorder = try AVAudioRecorder(url: url, settings: settings)
      recorder.isMeteringEnabled = true
      recorder.delegate = self
      guard recorder.record() else {
        throw NSError(domain: "VoiceInput", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not start recording"])
      }
      _recorder = recorder
      _recordingURL = url
      state = .recording
    } catch {
      _deactivateSession()
      _flash(.failure, error.localizedDescription)
      isPushToTalkRecording = false
      return
    }

    _haptic(.medium)
    _recordingStartedAt = Date()
    _speechDetected = false
    _lastLoudAt = nil
    let autoStop = _settings.autoStopOnSilence && !isPushToTalkRecording
    _showHUD(.listening, isPushToTalkRecording
             ? "Listening… release Shift to send"
             : (autoStop ? "Listening… pause to send, tap mic to stop" : "Listening… tap mic or right Shift to stop"))
    _startMetering()
  }

  private func _finishRecordingAndTranscribe() {
    guard state == .recording, let recorder = _recorder, let url = _recordingURL else { return }
    let duration = recorder.currentTime
    _stopRecorder()

    // Too short to be speech, most likely an accidental tap.
    guard duration >= 0.35 else {
      _cleanupRecordingFile()
      _dismissHUD()
      state = .idle
      isPushToTalkRecording = false
      return
    }

    state = .transcribing
    isPushToTalkRecording = false
    _haptic(.light)
    _showHUD(.transcribing, "Transcribing…")

    let transcriber = _settings.makeTranscriber()

    _transcribeTask = Task { [weak self] in
      do {
        let result = try await transcriber.transcribe(fileURL: url)
        guard !Task.isCancelled else { return }
        await MainActor.run { self?._deliver(transcript: result.text) }
      } catch {
        guard !Task.isCancelled else { return }
        await MainActor.run { self?._fail(error) }
      }
    }
  }

  private func _deliver(transcript raw: String) {
    _cleanupRecordingFile()
    _transcribeTask = nil
    state = .idle

    var text = raw
      .replacingOccurrences(of: "\r\n", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !text.isEmpty else {
      _flash(.failure, "Nothing recognised")
      return
    }

    if _settings.appendSpace && !_settings.pressEnter {
      text.append(" ")
    }

    guard let device = _targetDevice ?? Self._activeDevice() else {
      _flash(.failure, "No active terminal")
      return
    }

    device.write(text)
    if _settings.pressEnter {
      device.write("\r")
    }

    _haptic(.light)
    _flash(.success, text, duration: min(4, 1.2 + Double(text.count) * 0.03))
  }

  private func _fail(_ error: Error) {
    _cleanupRecordingFile()
    _transcribeTask = nil
    state = .idle
    _flash(.failure, error.localizedDescription, duration: 3.5)
  }

  private func _stopRecorder() {
    _meterTimer?.invalidate()
    _meterTimer = nil
    _recorder?.stop()
    _recorder = nil
    _deactivateSession()
  }

  private func _deactivateSession() {
    guard _sessionWasActivated else { return }
    _sessionWasActivated = false
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
  }

  private func _cleanupRecordingFile() {
    if let url = _recordingURL {
      try? FileManager.default.removeItem(at: url)
    }
    _recordingURL = nil
  }

  private func _startMetering() {
    _meterTimer?.invalidate()
    _meterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self = self, let recorder = self._recorder else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0) // dB, -160...0
        let normalized = CGFloat(max(0, (power + 50) / 50))
        self._hud?.setLevel(normalized)
        self._checkSilence(power: power)
      }
    }
  }

  /// Tap-to-talk: finish ~1.5 s after speech stops, give up after 8 s of nothing,
  /// and cap recordings at 90 s.
  private func _checkSilence(power: Float) {
    guard state == .recording, !isPushToTalkRecording, _settings.autoStopOnSilence,
          let started = _recordingStartedAt else { return }
    let now = Date()
    let loud = power > -38
    if loud {
      _speechDetected = true
      _lastLoudAt = now
    }
    let elapsed = now.timeIntervalSince(started)
    if _speechDetected, let last = _lastLoudAt, now.timeIntervalSince(last) > 1.5 {
      _finishRecordingAndTranscribe()
    } else if !_speechDetected && elapsed > 8 {
      cancel()
      _flash(.failure, "No speech detected")
    } else if elapsed > 90 {
      _finishRecordingAndTranscribe()
    }
  }

  // MARK: - HUD

  private func _showHUD(_ style: VoiceInputHUD.Style, _ text: String) {
    guard let window = Self._hudWindow(for: _targetDevice) else { return }
    _hud = VoiceInputHUD.show(in: window, style: style, text: text)
  }

  private func _flash(_ style: VoiceInputHUD.Style, _ text: String, duration: TimeInterval = 2.5) {
    _showHUD(style, text)
    _hud?.hide(after: duration)
  }

  private func _dismissHUD() {
    _hud?.hide()
    _hud = nil
  }

  private func _haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
    #if !targetEnvironment(macCatalyst)
    UIImpactFeedbackGenerator(style: style).impactOccurred()
    #endif
  }

  // MARK: - Helpers

  /// The terminal that currently has keyboard focus.
  private static func _activeDevice() -> TermDevice? {
    if let device = KBTracker.shared.input?.device {
      return device
    }
    for scene in UIApplication.shared.connectedScenes {
      guard
        let windowScene = scene as? UIWindowScene,
        scene.activationState == .foregroundActive,
        let space = windowScene.windows.compactMap({ $0.rootViewController as? SpaceController }).first,
        let device = space.currentDevice
      else { continue }
      return device
    }
    return nil
  }

  private static func _hudWindow(for device: TermDevice?) -> UIWindow? {
    if let window = device?.view?.window { return window }
    if let window = KBTracker.shared.input?.window { return window }
    return UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
  }

  private static func _requestMicrophonePermission() async -> Bool {
    if #available(iOS 17.0, macCatalyst 17.0, *) {
      switch AVAudioApplication.shared.recordPermission {
      case .granted: return true
      case .denied: return false
      default: return await AVAudioApplication.requestRecordPermission()
      }
    } else {
      let session = AVAudioSession.sharedInstance()
      switch session.recordPermission {
      case .granted: return true
      case .denied: return false
      default:
        return await withCheckedContinuation { cont in
          session.requestRecordPermission { cont.resume(returning: $0) }
        }
      }
    }
  }
}

extension VoiceInputManager: AVAudioRecorderDelegate {
  nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
    Task { @MainActor in
      guard self.state == .recording else { return }
      self._stopRecorder()
      self._cleanupRecordingFile()
      self.state = .idle
      self.isPushToTalkRecording = false
      self._flash(.failure, "Recording failed: \(error?.localizedDescription ?? "unknown error")")
    }
  }
}
