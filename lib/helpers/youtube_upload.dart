import 'dart:io';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:googleapis/youtube/v3.dart' as yt;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class YoutubeService {
  static final FlutterAppAuth _appAuth = const FlutterAppAuth();

  // YouTube upload scopes
  static const List<String> _scopes = [
    yt.YouTubeApi.youtubeUploadScope,
    'openid',
    'email',
    'profile',
  ];

  // Your OAuth client IDs
  static const _androidClientId = '697048427229-ajqs9251lvnb1iltnbl86qgqkrounjc3.apps.googleusercontent.com';
  static const _iosClientId = '697048427229-jc3ccjksgqjg566nuubcnd60tsb2hvh1.apps.googleusercontent.com';
  static const _webClientId = '697048427229-emv8c52vi41a4c9tfdnip56ll3ee42mf.apps.googleusercontent.com';

  // Redirect URIs per platform
  static const _iosRedirectUri = 'com.mixroom.mixroom:/oauthredirect';
  static const _androidRedirectUri = 'com.mixroom.mixroomapp:/oauthredirect';

  static yt.YouTubeApi? _youtubeApiClient;

  /// Upload a video to YouTube.
  static Future<String?> uploadVideo({
    required File file,
    required String title,
    required String description,
    String privacy = 'public', // can be 'public', 'unlisted', or 'private'
  }) async {
    try {
      // 1️⃣ Pick client ID and redirect URI based on platform
      final String clientId = Platform.isIOS ? _iosClientId : _androidClientId;
      final String redirectUri = Platform.isIOS ? _iosRedirectUri : _androidRedirectUri;

      debugPrint('🎬 Starting YouTube OAuth flow...');

      // 2️⃣ Authorize and get tokens using PKCE
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          clientId,
          redirectUri,
          issuer: 'https://accounts.google.com',
          scopes: _scopes,
          promptValues: ['consent'], // ensure upload scope consent every time
        ),
      );

      if (result == null || result.accessToken == null) {
        debugPrint('❌ OAuth flow canceled or failed.');
        return null;
      }

      debugPrint('✅ Got access token: ${result.accessToken!.substring(0, 15)}...');

      // 3️⃣ Build authorized client
      final client = authenticatedClient(
        http.Client(),
        AccessCredentials(
          AccessToken(
            'Bearer',
            result.accessToken!,
            result.accessTokenExpirationDateTime?.toUtc() ?? DateTime.now().toUtc().add(const Duration(hours: 1)),
          ),
          result.refreshToken,
          [yt.YouTubeApi.youtubeUploadScope],
        ),
      );

      final youtube = yt.YouTubeApi(client);
      _youtubeApiClient = youtube;

      // 4️⃣ Create video metadata
      final snippet = yt.VideoSnippet()
        ..title = title
        ..description = description
        ..categoryId = '10'; // "Music" category

      final status = yt.VideoStatus()..privacyStatus = privacy;

      final video = yt.Video()
        ..snippet = snippet
        ..status = status;

      // 5️⃣ Prepare video media stream
      final media = yt.Media(file.openRead(), await file.length());

      debugPrint('⬆️ Uploading video "${file.path}"...');

      // 6️⃣ Upload
      final response = await youtube.videos.insert(
        video,
        ['snippet', 'status'],
        uploadMedia: media,
      );

      if (response.id != null) {
        debugPrint('✅ Upload complete! Video ID: ${response.id}');
        return response.id;
      } else {
        debugPrint('⚠️ Upload finished but no video ID returned.');
        return null;
      }
    } catch (e, st) {
      debugPrint('❌ YouTube upload failed: $e');
      debugPrint(st.toString());
      return null;
    }
  }

  static Future<void> uploadThumbnail(String videoId, File thumbnail) async {
    final media = yt.Media(thumbnail.openRead(), thumbnail.lengthSync());
    await _youtubeApiClient!.thumbnails.set(videoId, uploadMedia: media);
  }
}



// import 'dart:io';
// import 'package:http/http.dart' as http;
// import 'package:googleapis/youtube/v3.dart';
// import 'package:google_sign_in/google_sign_in.dart';

// class YoutubeService {
//   static const List<String> scopes = [
//     YouTubeApi.youtubeUploadScope,
//     YouTubeApi.youtubeReadonlyScope,
//   ];

//   static Future<YouTubeApi> _getYouTubeApi() async {
//     final signIn = GoogleSignIn.instance;

//     await signIn.disconnect(); // clears cached session
//     // await signIn.authenticate(scopeHint: [
//     //     'https://www.googleapis.com/auth/youtube.upload',
//     //     'https://www.googleapis.com/auth/youtube.readonly',
//     //   ]
//     // );

// print("pass 1");
//     await signIn.initialize(
//       // serverClientId: 'YOUR_SERVER_CLIENT_ID.apps.googleusercontent.com',
//       serverClientId: '697048427229-emv8c52vi41a4c9tfdnip56ll3ee42mf.apps.googleusercontent.com', // Web
//     );
// print("pass 12");
//     // Authenticate and get user
//     // final GoogleSignInAccount user =
//     //     await signIn.authenticate(scopeHint: scopes);


// Map<String, String>? headers;

//     try {
//       print("pass 3");
//       final GoogleSignInAccount user = await signIn.authenticate(scopeHint: [
//         'https://www.googleapis.com/auth/youtube.upload',
//         'https://www.googleapis.com/auth/youtube.readonly',
//       ]);
//       print("✅ Signed in as: ${user.displayName}");


// print("signin5");
//       final auth = await user.authorizationClient.authorizeScopes(scopes);
//       print("signin6");
//       // Get headers
//       headers =
//           await user.authorizationClient.authorizationHeaders(scopes);
//           print("signin7");
//       if (headers == null) throw Exception('Failed to get auth headers');
    

//     } catch (e) {
//       print("❌ Sign-in failed: $e");
//     }

//     print("headers: ${headers}");

//     return YouTubeApi(_AuthorizedClient(headers!));
//   }

//   static Future<String> uploadVideo({
//     required File file,
//     required String title,
//     required String description,
//     String privacy = 'public',
//   }) async {

//     print("file name: ${file.absolute}");
// print("here");
//     final youtube = await _getYouTubeApi();
// print("here2");
//     final snippet = VideoSnippet()
//       ..title = title
//       ..description = description
//       ..categoryId = '10'; // default is 'music'; TODO: allow user to select with dropdown menu

//     final status = VideoStatus()..privacyStatus = privacy;

//     final video = Video()
//       ..snippet = snippet
//       ..status = status;

//     final media = Media(file.openRead(), await file.length());

//     final response = await youtube.videos.insert(
//       video,
//       ['snippet', 'status'],
//       uploadMedia: media,
//     );

//     return response.id ?? '';
//   }
// }

// class _AuthorizedClient extends http.BaseClient {
//   final Map<String, String> _headers;
//   final http.Client _inner = http.Client();

//   _AuthorizedClient(this._headers);

//   @override
//   Future<http.StreamedResponse> send(http.BaseRequest request) {
//     request.headers.addAll(_headers);
//     return _inner.send(request);
//   }
// }













// import 'dart:io';
// // import 'package:flutter_appauth/flutter_appauth.dart';
// // import 'package:googleapis_auth/googleapis_auth.dart';
// // import 'package:googleapis/youtube/v3.dart' as yt;
// // import 'package:http/http.dart' as http;
// import 'package:yt/yt.dart';

// Future<String?> uploadVideoToYouTube({
//   required File videoFile,
//   required String title,
//   required String description,
// }) async {
//   // 1. Create an authenticated Yt instance
//   // This will prompt user login / consent if needed
//   print("sup");
//   final ytClient = await Yt.withOAuth();
// print("sup1");
//   // 2. Prepare metadata body
//   final body = <String, dynamic>{
//     'snippet': {
//       'title': title,
//       'description': description,
//       // optionally tags, categoryId, etc
//       'tags': <String>[],
//       'categoryId': '10',  // music (music by default, but allow them to select from dropdown)
//     },
//     'status': {
//       'privacyStatus': 'public',  // or "private" / "unlisted"
//       'embeddable': true,
//       'license': 'youtube',
//     },
//   };
// print("sup2");
//   // 3. Call insert with video file
//   final uploaded = await ytClient.videos.insert(
//     body: body,
//     videoFile: videoFile,
//     notifySubscribers: false,
//   );
// print("sup3");
//   return uploaded.id;
// }














// final FlutterAppAuth _appAuth = const FlutterAppAuth();

// Future<String?> uploadVideoToYouTube({
//   required File videoFile,
//   required String title,
//   required String description,
//   required String clientId,            // from OAuth config
//   required String redirectUri,         // e.g. "com.yourapp:/oauthredirect"
// }) async {
//   print("printed here..1");
//   // 1. Authorize & exchange code
//   final AuthorizationTokenResponse? result =
//       await _appAuth.authorizeAndExchangeCode(
//     AuthorizationTokenRequest(
//       clientId,
//       redirectUri,
//       issuer: 'https://accounts.google.com',
//       scopes: [
//         yt.YouTubeApi.youtubeUploadScope,
//         'openid',
//         'email',
//         'profile'
//       ],
//       // use PKCE by default
//     ),
//   );
// print("printed here..11");
//   if (result == null || result.accessToken == null) {
//     print("printed here..2");
//     // User canceled or error
//     return null;
//   }

//   print("printed here..3");

//   final String accessToken = result.accessToken!;
//   final DateTime expiresIn = result.accessTokenExpirationDateTime ??
//       DateTime.now().add(const Duration(hours: 1));

//   final String? refreshToken = result.refreshToken;

//   // 2. Build authenticated client
//   final client = authenticatedClient(
//     http.Client(),
//     AccessCredentials(
//       AccessToken('Bearer', accessToken, expiresIn),
//       refreshToken,
//       [yt.YouTubeApi.youtubeUploadScope],
//     ),
//   );

//   final ytApi = yt.YouTubeApi(client);

//   // 3. Prepare video metadata
//   final snippet = yt.VideoSnippet()
//     ..title = title
//     ..description = description
//     ..categoryId = '10';  // music (music by default, but allow them to select from dropdown)

//   final status = yt.VideoStatus()..privacyStatus = 'public';

//   final video = yt.Video()
//     ..snippet = snippet
//     ..status = status;

//   final media = yt.Media(videoFile.openRead(), videoFile.lengthSync());

//   // 4. Upload
//   final response = await ytApi.videos.insert(
//     video,
//     ['snippet', 'status'],
//     uploadMedia: media,
//   );

//   return response.id;
// }
