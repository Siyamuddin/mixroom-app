import Cocoa
import FlutterMacOS
import AuthenticationServices

@main
class AppDelegate: FlutterAppDelegate, ASWebAuthenticationPresentationContextProviding {
  private let channelName = "mixroom/open_file"
  private let nativeSocialChannelName = "mixroom/native_social"
  private var channel: FlutterMethodChannel?
  private var nativeSocialChannel: FlutterMethodChannel?
  private var initialMixroomPath: String?
  private var channelsInitialized = false
  private var kakaoAuthSession: ASWebAuthenticationSession?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    bindChannelsIfNeeded()
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    for path in filenames {
      if handleIncomingPath(path) {
        sender.reply(toOpenOrPrint: .success)
        return
      }
    }
    sender.reply(toOpenOrPrint: .failure)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
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
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    nativeSocialChannel = FlutterMethodChannel(
      name: nativeSocialChannelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    nativeSocialChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      if call.method == "signInWithKakao" {
        let args = call.arguments as? [String: Any]
        let appKey = (args?["nativeAppKey"] as? String)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.startKakaoSignIn(nativeAppKey: appKey, result: result)
        return
      }
      result(FlutterMethodNotImplemented)
    }
    channelsInitialized = true
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    return mainFlutterWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
  }

  private func startKakaoSignIn(nativeAppKey: String, result: @escaping FlutterResult) {
    if nativeAppKey.isEmpty {
      result(FlutterError(
        code: "KAKAO_NOT_CONFIGURED",
        message: "Kakao sign-in is not configured in this build.",
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
      URLQueryItem(name: "client_id", value: nativeAppKey),
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
        nativeAppKey: nativeAppKey,
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
    nativeAppKey: String,
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
      "client_id": nativeAppKey,
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
