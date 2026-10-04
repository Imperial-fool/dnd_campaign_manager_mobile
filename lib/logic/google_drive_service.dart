import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

class DriveJsonFile {
  const DriveJsonFile({required this.id, required this.name});

  final String id;
  final String name;
}

/// Optional Google Drive access for character backups and content-pack imports.
class GoogleDriveService extends ChangeNotifier {
  static const _oauthClientId =
      String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID');
  static const _characterIdProperty = 'campaignCharacterId';
  static const _scopes = [
    drive.DriveApi.driveFileScope,
    drive.DriveApi.driveReadonlyScope,
  ];

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  GoogleSignInAccount? _account;
  bool _driveAuthorized = false;
  bool _initialized = false;
  String? authenticationError;

  bool get isPlatformSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  bool get isConfigured => _oauthClientId.isNotEmpty;
  bool get isSignedIn => _account != null;
  bool get isDriveAuthorized => _driveAuthorized;
  String? get accountEmail => _account?.email;

  Future<void> initialize() async {
    if (!isPlatformSupported || !isConfigured) return;
    await _googleSignIn.initialize(
      clientId: kIsWeb ||
              defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS
          ? _oauthClientId
          : null,
      serverClientId: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? _oauthClientId
          : null,
    );
    _initialized = true;
    _googleSignIn.authenticationEvents.listen(
      (event) {
        switch (event) {
          case GoogleSignInAuthenticationEventSignIn(:final user):
            _account = user;
            _driveAuthorized = false;
            authenticationError = null;
          case GoogleSignInAuthenticationEventSignOut():
            _account = null;
            _driveAuthorized = false;
        }
        notifyListeners();
      },
      onError: (Object error) {
        authenticationError = error.toString();
        notifyListeners();
      },
    );
  }

  Future<void> signIn() async {
    _ensureAvailable();
    if (kIsWeb) {
      throw UnsupportedError(
        'Use the Google-rendered sign-in button on web.',
      );
    }
    final account =
        _account ?? await _googleSignIn.authenticate(scopeHint: _scopes);
    await account.authorizationClient.authorizeScopes(_scopes);
    _account = account;
    _driveAuthorized = true;
    authenticationError = null;
    notifyListeners();
  }

  Future<void> authorizeDriveAccess() async {
    _ensureAvailable();
    final account = _account;
    if (account == null) {
      throw StateError('Sign in with Google before authorizing Drive access.');
    }
    await account.authorizationClient.authorizeScopes(_scopes);
    _driveAuthorized = true;
    authenticationError = null;
    notifyListeners();
  }

  Future<void> signOut() async {
    _ensureAvailable();
    await _googleSignIn.signOut();
    _account = null;
    _driveAuthorized = false;
    notifyListeners();
  }

  Future<void> saveCharacterJson({
    required String id,
    required String name,
    required String json,
  }) async {
    await _withDrive((api) async {
      final escapedId = id.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
      final matches = await api.files.list(
        q: "appProperties has { key='$_characterIdProperty' and value='$escapedId' } and trashed = false",
        pageSize: 1,
        spaces: 'drive',
        $fields: 'files(id)',
      );
      final existing =
          matches.files?.isNotEmpty == true ? matches.files!.first : null;
      final metadata = drive.File(
        name: '$name.json',
        mimeType: 'application/json',
        appProperties: {_characterIdProperty: id},
      );
      final bytes = utf8.encode(json);
      final media = drive.Media(
        Stream<List<int>>.value(bytes),
        bytes.length,
        contentType: 'application/json',
      );
      final existingId = existing?.id;
      if (existingId != null) {
        await api.files.update(metadata, existingId, uploadMedia: media);
      } else {
        await api.files.create(metadata, uploadMedia: media);
      }
    });
  }

  Future<List<DriveJsonFile>> listJsonFiles() => _withDrive((api) async {
        final files = <DriveJsonFile>[];
        String? pageToken;
        do {
          final page = await api.files.list(
            q: "trashed = false and (mimeType = 'application/json' or name contains '.json')",
            pageSize: 100,
            orderBy: 'name',
            pageToken: pageToken,
            spaces: 'drive',
            $fields: 'nextPageToken,files(id,name,appProperties)',
          );
          for (final file in page.files ?? <drive.File>[]) {
            if (file.id != null &&
                file.name != null &&
                file.appProperties?.containsKey(_characterIdProperty) != true) {
              files.add(DriveJsonFile(id: file.id!, name: file.name!));
            }
          }
          pageToken = page.nextPageToken;
        } while (pageToken != null);
        return files;
      });

  Future<List<DriveJsonFile>> listCharacterFiles() => _withDrive((api) async {
        final files = <DriveJsonFile>[];
        String? pageToken;
        do {
          final page = await api.files.list(
            q: "trashed = false and appProperties has { key='$_characterIdProperty' }",
            pageSize: 100,
            orderBy: 'name',
            pageToken: pageToken,
            spaces: 'drive',
            $fields: 'nextPageToken,files(id,name,appProperties)',
          );
          for (final file in page.files ?? <drive.File>[]) {
            if (file.id != null &&
                file.name != null &&
                file.appProperties?.containsKey(_characterIdProperty) == true) {
              files.add(DriveJsonFile(id: file.id!, name: file.name!));
            }
          }
          pageToken = page.nextPageToken;
        } while (pageToken != null);
        return files;
      });

  Future<String> readJsonFile(String fileId) => _withDrive((api) async {
        final content = await api.files.get(
          fileId,
          downloadOptions: drive.DownloadOptions.fullMedia,
        );
        if (content is! drive.Media) {
          throw StateError('Google Drive did not return a JSON file.');
        }
        return content.stream.transform(utf8.decoder).join();
      });

  Future<T> _withDrive<T>(Future<T> Function(drive.DriveApi api) action) async {
    _ensureAvailable();
    final account = _account;
    if (account == null) {
      throw StateError('Connect Google Drive in Campaign Settings first.');
    }
    final authorization =
        await account.authorizationClient.authorizationForScopes(_scopes) ??
            await account.authorizationClient.authorizeScopes(_scopes);
    _driveAuthorized = true;
    final client = _BearerClient(authorization.accessToken);
    try {
      return await action(drive.DriveApi(client));
    } finally {
      client.close();
    }
  }

  void _ensureAvailable() {
    if (!isPlatformSupported) {
      throw UnsupportedError(
        'Google Drive is available in web, Android, iOS, and macOS builds.',
      );
    }
    if (!isConfigured) {
      throw StateError(
        'Google Drive is not configured. Set GOOGLE_OAUTH_CLIENT_ID when building the app.',
      );
    }
    if (!_initialized) {
      throw StateError('Google Drive has not been initialized.');
    }
  }
}

class _BearerClient extends http.BaseClient {
  _BearerClient(this._accessToken);

  final String _accessToken;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
