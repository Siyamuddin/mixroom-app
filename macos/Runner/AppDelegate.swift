import Cocoa
import FlutterMacOS
import AuthenticationServices
import juce_audio_engine

@objcMembers
class AppDelegate: FlutterAppDelegate, ASWebAuthenticationPresentationContextProviding {
  private let channelName = "mixroom/open_file"
  private let nativeSocialChannelName = "mixroom/native_social"
  private var channel: FlutterMethodChannel?
  private var nativeSocialChannel: FlutterMethodChannel?
  private var sampleBrowserAccessChannel: FlutterMethodChannel?
  private var activeSampleBookmarks: [String: URL] = [:]
  private var initialMixroomPath: String?
  private var initialMixroomUrl: String?
  private var channelsInitialized = false
  private var kakaoAuthSession: ASWebAuthenticationSession?

  @objc(applicationDidFinishLaunching:)
  dynamic override func applicationDidFinishLaunching(_ notification: Notification) {
    bindChannelsIfNeeded()
  }

  @objc(applicationWillTerminate:)
  dynamic override func applicationWillTerminate(_ notification: Notification) {
    JuceAudioEnginePluginSwift.shutdownForApplicationTermination()
  }

  @objc(applicationDidResignActive:)
  dynamic override func applicationDidResignActive(_ notification: Notification) {
    JuceAudioEnginePluginSwift.panicLiveMidiNotesForApplicationDeactivation()
  }

  @objc(application:openFiles:)
  dynamic override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    for path in filenames {
      if handleIncomingPath(path) {
        sender.reply(toOpenOrPrint: .success)
        return
      }
    }
    sender.reply(toOpenOrPrint: .failure)
  }

  @objc(application:openURLs:)
  dynamic override func application(_ application: NSApplication, open urls: [URL]) {
    var unhandled: [URL] = []
    for url in urls {
      if url.scheme == "mixroom", url.host == "education",
         url.pathComponents.dropFirst().first == "invites",
         url.pathComponents.count == 3 {
        initialMixroomUrl = url.absoluteString
        bindChannelsIfNeeded()
        channel?.invokeMethod("openMixroomUrl", arguments: url.absoluteString)
      } else {
        unhandled.append(url)
      }
    }
    if !unhandled.isEmpty {
      super.application(application, open: unhandled)
    }
  }

  @objc(applicationShouldTerminateAfterLastWindowClosed:)
  dynamic override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  @objc(applicationSupportsSecureRestorableState:)
  dynamic override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  @discardableResult
  private func handleIncomingPath(_ path: String) -> Bool {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || !trimmed.lowercased().hasSuffix(".mixroom") {
      return false
    }
    deliverPath(trimmed)
    return true
  }

  private func deliverPath(_ path: String) {
    bindChannelsIfNeeded()
    if let channel = channel {
      channel.invokeMethod("openMixroomPath", arguments: path)
    } else {
      initialMixroomPath = path
    }
  }

  private func bindChannelsIfNeeded() {
    if channelsInitialized { return }
    guard
      let flutterViewController = mainFlutterWindow?.contentViewController as? FlutterViewController
    else {
      return
    }

    channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      if call.method == "getInitialMixroomPath" {
        result(self.initialMixroomPath)
        self.initialMixroomPath = nil
      } else if call.method == "getInitialMixroomUrl" {
        result(self.initialMixroomUrl)
        self.initialMixroomUrl = nil
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    nativeSocialChannel = FlutterMethodChannel(
      name: nativeSocialChannelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    sampleBrowserAccessChannel = FlutterMethodChannel(
      name: "mixroom/sample_browser_access",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    sampleBrowserAccessChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "createBookmark":
        guard let path = args?["path"] as? String else {
          result(FlutterError(code: "bad_args", message: "Missing path", details: nil))
          return
        }
        do {
          let url = URL(fileURLWithPath: path)
          let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
          )
          result(["path": url.path, "persistentToken": bookmark.base64EncodedString()])
        } catch {
          result(FlutterError(code: "bookmark_failed", message: error.localizedDescription, details: nil))
        }
      case "restoreAccess":
        guard let token = args?["token"] as? String,
              let data = Data(base64Encoded: token) else {
          result(FlutterError(code: "bad_token", message: "Invalid bookmark", details: nil))
          return
        }
        do {
          var stale = false
          let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
          )
          guard url.startAccessingSecurityScopedResource() else {
            result(FlutterError(code: "access_denied", message: "Folder access is no longer available", details: nil))
            return
          }
          self.activeSampleBookmarks[token] = url
          result(["path": url.path, "persistentToken": token])
        } catch {
          result(FlutterError(code: "restore_failed", message: error.localizedDescription, details: nil))
        }
      case "releaseAccess":
        guard let token = args?["token"] as? String else { result(nil); return }
        self.activeSampleBookmarks.removeValue(forKey: token)?.stopAccessingSecurityScopedResource()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    nativeSocialChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      if call.method == "signInWithKakao" {
        let args = call.arguments as? [String: Any]
        let appKey = (args?["nativeAppKey"] as? String)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let restApiKey = (args?["restApiKey"] as? String)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.startKakaoSignIn(
          nativeAppKey: appKey,
          restApiKey: restApiKey,
          result: result
        )
        return
      }
      result(FlutterMethodNotImplemented)
    }
    channelsInitialized = true
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    return mainFlutterWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
  }

  private func startKakaoSignIn(
    nativeAppKey: String,
    restApiKey: String,
    result: @escaping FlutterResult
  ) {
    if nativeAppKey.isEmpty {
      result(FlutterError(
        code: "KAKAO_NOT_CONFIGURED",
        message: "Kakao sign-in is not configured in this build.",
        details: nil
      ))
      return
    }
    if restApiKey.isEmpty {
      result(FlutterError(
        code: "KAKAO_REST_API_KEY_NOT_CONFIGURED",
        message: "Kakao REST API key is not configured for this desktop build.",
        details: nil
      ))
      return
    }
    if kakaoAuthSession != nil {
      result(FlutterError(
        code: "KAKAO_SIGN_IN_IN_PROGRESS",
        message: "Kakao sign-in is already in progress.",
        details: nil
      ))
      return
    }

    let callbackScheme = "kakao\(nativeAppKey)"
    let redirectUri = "\(callbackScheme)://oauth"
    var components = URLComponents(string: "https://kauth.kakao.com/oauth/authorize")
    components?.queryItems = [
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "client_id", value: restApiKey),
      URLQueryItem(name: "redirect_uri", value: redirectUri),
      URLQueryItem(name: "scope", value: "account_email,profile_nickname")
    ]
    guard let authUrl = components?.url else {
      result(FlutterError(
        code: "KAKAO_AUTH_URL_INVALID",
        message: "Kakao sign-in could not start.",
        details: nil
      ))
      return
    }

    let session = ASWebAuthenticationSession(
      url: authUrl,
      callbackURLScheme: callbackScheme
    ) { [weak self] callbackUrl, error in
      guard let self = self else { return }
      self.kakaoAuthSession = nil

      if let error = error as? ASWebAuthenticationSessionError,
         error.code == .canceledLogin {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "USER_CANCELLED",
            message: "Social sign-in was cancelled.",
            details: nil
          ))
        }
        return
      }
      if let error = error {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "KAKAO_AUTH_FAILED",
            message: error.localizedDescription,
            details: nil
          ))
        }
        return
      }
      guard
        let callbackUrl = callbackUrl,
        let callbackComponents = URLComponents(url: callbackUrl, resolvingAgainstBaseURL: false)
      else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "KAKAO_CALLBACK_INVALID",
            message: "Kakao sign-in returned an invalid callback.",
            details: nil
          ))
        }
        return
      }
      if let callbackError = callbackComponents.queryItems?
        .first(where: { $0.name == "error_description" || $0.name == "error" })?
        .value,
         !callbackError.isEmpty {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "KAKAO_AUTH_FAILED",
            message: callbackError,
            details: nil
          ))
        }
        return
      }
      guard let code = callbackComponents.queryItems?
        .first(where: { $0.name == "code" })?
        .value,
            !code.isEmpty
      else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "KAKAO_CODE_MISSING",
            message: "Kakao sign-in did not return an authorization code.",
            details: nil
          ))
        }
        return
      }
      self.exchangeKakaoCode(
        code: code,
        restApiKey: restApiKey,
        redirectUri: redirectUri,
        result: result
      )
    }

    session.presentationContextProvider = self
    session.prefersEphemeralWebBrowserSession = false
    kakaoAuthSession = session
    if !session.start() {
      kakaoAuthSession = nil
      result(FlutterError(
        code: "KAKAO_AUTH_START_FAILED",
        message: "Kakao sign-in could not open.",
        details: nil
      ))
    }
  }

  private func exchangeKakaoCode(
    code: String,
    restApiKey: String,
    redirectUri: String,
    result: @escaping FlutterResult
  ) {
    guard let url = URL(string: "https://kauth.kakao.com/oauth/token") else {
      result(FlutterError(
        code: "KAKAO_TOKEN_URL_INVALID",
        message: "Kakao token endpoint is invalid.",
        details: nil
      ))
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(
      "application/x-www-form-urlencoded;charset=utf-8",
      forHTTPHeaderField: "Content-Type"
    )
    request.httpBody = formEncodedBody([
      "grant_type": "authorization_code",
      "client_id": restApiKey,
      "redirect_uri": redirectUri,
      "code": code
    ]).data(using: .utf8)

    URLSession.shared.dataTask(with: request) { data, response, error in
      if let error = error {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "KAKAO_TOKEN_EXCHANGE_FAILED",
            message: error.localizedDescription,
            details: nil
          ))
        }
        return
      }
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      guard let data = data else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "KAKAO_TOKEN_RESPONSE_EMPTY",
            message: "Kakao token response was empty.",
            details: nil
          ))
        }
        return
      }
      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      if status < 200 || status >= 300 {
        let message = (json?["error_description"] as? String)
          ?? (json?["error"] as? String)
          ?? "Kakao sign-in could not be completed."
        DispatchQueue.main.async {
          result(FlutterError(
            code: "KAKAO_TOKEN_EXCHANGE_FAILED",
            message: message,
            details: json
          ))
        }
        return
      }
      guard let accessToken = (json?["access_token"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
            !accessToken.isEmpty
      else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "KAKAO_ACCESS_TOKEN_MISSING",
            message: "Kakao sign-in did not return an access token.",
            details: json
          ))
        }
        return
      }
      DispatchQueue.main.async {
        result(["access_token": accessToken])
      }
    }.resume()
  }

  private func formEncodedBody(_ fields: [String: String]) -> String {
    return fields.map { key, value in
      "\(urlEncode(key))=\(urlEncode(value))"
    }.joined(separator: "&")
  }

  private func urlEncode(_ value: String) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }
}
