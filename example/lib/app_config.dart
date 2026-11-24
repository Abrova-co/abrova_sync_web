import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:abrova_sync/abrova_sync.dart';

import 'demo_token_minter.dart';

/// Configuration for the AbrovaSync Example App
///
/// Put your own values in `example/config/local.json` (not checked in; copy
/// `config/local.example.json`), then run as usual with `flutter run`. The app
/// reads the file at start-up ([load]).
///
/// - `apiKey`: your project's API key (Abrova Console > your project > settings)
/// - `databaseName`: your database NAME as shown in Abrova Console (not its
///   UUID). Realtime updates only arrive when you address the database by name.
/// - `tokenUrl` (debug builds only): your backend's endpoint that mints user
///   tokens, see [DemoTokenMinter]. Never put a server secret in a web page.
/// - `demoUserId`: the user the demo signs in as (default `flutter-web-demo-user`).
class AppConfig {
  static const String _file = 'config/local.json';
  static Map<String, dynamic> _values = const {};

  /// Reads `config/local.json`. Returns false when it is missing or has no API key.
  static Future<bool> load() async {
    try {
      final decoded = jsonDecode(await rootBundle.loadString(_file));
      if (decoded is Map<String, dynamic>) _values = decoded;
    } catch (_) {
      _values = const {};
    }
    return apiKey.startsWith('ab_live_');
  }

  static String _value(String key, String fallback) {
    final value = _values[key];
    return value is String && value.isNotEmpty ? value : fallback;
  }

  static String get apiKey => _value('apiKey', '');

  static String get databaseId => _value('databaseName', 'my-app');

  static String get demoUserId => _value('demoUserId', 'flutter-web-demo-user');

  /// Empty in release builds, whatever config/local.json says.
  static String get tokenUrl => kDebugMode ? _value('tokenUrl', '') : '';

  /// Null in release builds and when not set.
  static String? get emulatorHost {
    final host = kDebugMode ? _value('emulatorHost', '') : '';
    return host.isEmpty ? null : host;
  }

  // Demo collection names
  static const String todosCollection = 'todos';
  static const String usersCollection = 'users';
  static const String messagesCollection = 'messages';

  /// The signed-in user (the demo minter signs tokens for it). Documents carry
  /// it as `userId`, which the default "owner only" Security Rules check:
  /// `newData.userId === auth.uid`.
  static String get userId => DemoTokenMinter.currentUserId;

  /// The signed-in user's documents. Security Rules are not filters: a list or
  /// listener must filter on the field the rules read (here `userId`), or the
  /// server refuses it with `AbrovaSyncErrorCode.queryNotAllowed`.
  static SyncQuery mine(SyncCollection collection) =>
      collection.where('userId', QueryOperator.equal, userId);
}
