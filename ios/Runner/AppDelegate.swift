import UIKit
import Flutter
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private func prepareVoIPAudioSession() {
    configureVoIPAudioSession()
    activateVoIPAudioSession()
  }

  private func configureVoIPAudioSession() {
    let audioSession = AVAudioSession.sharedInstance()
    do {
      // Call-safe configuration for bidirectional VoIP audio.
      try audioSession.setCategory(
        .playAndRecord,
        mode: .voiceChat,
        options: [.allowBluetooth, .defaultToSpeaker]
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
      try audioSession.setActive(true)
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
    // Avoid keeping the session force-active at launch while there is no call.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      self?.configureVoIPAudioSession()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    prepareVoIPAudioSession()
  }

  override func applicationWillEnterForeground(_ application: UIApplication) {
    super.applicationWillEnterForeground(application)
    prepareVoIPAudioSession()
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    // Keep session configured for CallKit answer from lock screen/background.
    configureVoIPAudioSession()
  }

  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    // This path is commonly used when a user answers from lock screen CallKit UI.
    prepareVoIPAudioSession()
    return super.application(
      application,
      continue: userActivity,
      restorationHandler: restorationHandler
    )
  }
}
