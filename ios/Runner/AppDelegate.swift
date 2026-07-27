import FirebaseCore
import FirebaseMessaging
import Flutter
import GoogleMaps
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// APNs token that arrived before Firebase was configured (see
  /// didRegisterForRemoteNotificationsWithDeviceToken below).
  private var pendingApnsToken: Data?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !apiKey.isEmpty {
      GMSServices.provideAPIKey(apiKey)
    } else {
      NSLog("[Runner] GMSApiKey is missing or empty; Google Maps views will not render. Set GOOGLE_MAPS_API_KEY in ios/Flutter/Secrets.xcconfig (local) or the CI inject step.")
    }
    // firebase_messaging only calls registerForRemoteNotifications from its
    // UIApplicationDidFinishLaunchingNotification observer, which it registers
    // at plugin-registration time. Under the UIScene lifecycle the implicit
    // Flutter engine (and thus plugin registration) initializes at
    // scene-connect — after that notification has already been posted — so the
    // observer never fires and APNs registration never happens. Register
    // explicitly; the didRegister... override below forwards the token.
    application.registerForRemoteNotifications()
    // Same UIScene gap, but for notification taps: firebase_messaging would
    // install itself as the UNUserNotificationCenter delegate from its launch
    // hook, which never runs (see above), so NO delegate is ever set and iOS
    // drops every tap (didReceiveNotificationResponse) without invoking
    // anyone — the app opens but never navigates. FlutterAppDelegate
    // implements the delegate methods and forwards them to every registered
    // plugin (firebase_messaging AND flutter_local_notifications), and a
    // plugin that later checks the delegate sees a FlutterAppLifeCycleProvider
    // and leaves it in place. Must be assigned before launching finishes or
    // iOS won't deliver the cold-start tap response.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Under the UIScene lifecycle (SceneDelegate + UIApplicationSceneManifest)
  // firebase_messaging's app-delegate swizzling misses this callback, so
  // Messaging.apnsToken stays unset and getToken() fails with
  // apns-token-not-set. Forward the APNs token explicitly; harmless if
  // swizzling also delivers it.
  //
  // The token can arrive before the Flutter engine has registered plugins
  // (registration is requested in didFinishLaunching above), and
  // Messaging.messaging() traps if no default FirebaseApp is configured yet —
  // firebase_core configures it from the bundled GoogleService-Info.plist
  // during plugin registration. Cache the token for that window and apply it
  // in didInitializeImplicitFlutterEngine.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    if FirebaseApp.app() != nil {
      Messaging.messaging().apnsToken = deviceToken
    } else {
      pendingApnsToken = deviceToken
    }
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("[Runner] APNs registration failed: \(error)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Plugin registration configured the default FirebaseApp (from the bundled
    // plist); deliver an APNs token that arrived before that. Both callbacks
    // run on the main thread, so there is no race on pendingApnsToken.
    if let token = pendingApnsToken, FirebaseApp.app() != nil {
      Messaging.messaging().apnsToken = token
      pendingApnsToken = nil
    }
  }
}
