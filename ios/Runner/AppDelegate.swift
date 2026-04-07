import UIKit
import Flutter
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private func configureVoIPAudioSession() {
    let audioSession = AVAudioSession.sharedInstance()
    do {
      // Configure telephony audio routing for in-call media.
      try audioSession.setCategory(
        .playAndRecord,
        mode: .voiceChat,
        options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
      )
      try audioSession.setPreferredSampleRate(48_000)
      try audioSession.setPreferredIOBufferDuration(0.005)
    } catch {
      NSLog("VoIP audio category configuration failed: \(error.localizedDescription)")
    }
  }

  private func activateVoIPAudioSession() {
    let audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
      try audioSession.overrideOutputAudioPort(.speaker)
    } catch {
      NSLog("VoIP audio activation failed: \(error.localizedDescription)")
    }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    configureVoIPAudioSession()
    activateVoIPAudioSession()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      self?.activateVoIPAudioSession()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    configureVoIPAudioSession()
    activateVoIPAudioSession()
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    // Keep session configured for CallKit answer from lock screen/background.
    configureVoIPAudioSession()
  }
}
