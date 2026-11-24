import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:abrova_sync/abrova_sync.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';

/// Gets user tokens from YOUR backend, so this example can run against a
/// project that has "Require signed user tokens" turned on.
///
/// Security Rules read `auth.uid`. A web page cannot decide that value: its API
/// key is visible to everyone who opens the page, so anyone could claim any
/// user. Only a server holding the project's server secret can mint a user
/// token, and the server secret must never be in a web page.
///
/// Set `tokenUrl` in config/local.json to an endpoint of your own backend that
/// answers `POST {"userId": "..."}` with `{"token": "..."}` (the Node SDK's
/// `createUserToken` does the signing). In a real app that endpoint sits behind
/// your own login and mints a token for the user who is actually signed in.
class DemoTokenMinter {
  DemoTokenMinter._();

  static String _currentUserId = AppConfig.demoUserId;

  /// The user the demo asks tokens for: `demoUserId`, or a second demo user
  /// after [switchUser] (to see what Security Rules do with another user's
  /// data). A real app signs in through its own login instead.
  static String get currentUserId => _currentUserId;

  /// The other demo user's id (`demoUserId` + "-2").
  static String get otherUserId => _currentUserId == AppConfig.demoUserId
      ? '${AppConfig.demoUserId}-2'
      : AppConfig.demoUserId;

  /// True when config/local.json gave this debug build a `tokenUrl`.
  static bool get isConfigured => AppConfig.tokenUrl.isNotEmpty;

  /// Sign in as the other demo user: the SDK asks [fetchToken] again and
  /// reconnects as that user.
  static Future<void> switchUser() async {
    _currentUserId = otherUserId;
    await AbrovaSync.refreshUserToken();
  }

  /// Asks your backend for a token for the demo user. The SDK's token provider:
  /// called at init, shortly before the token expires, and on
  /// [AbrovaSync.refreshUserToken].
  static Future<String?> fetchToken() async {
    if (!isConfigured) return null;
    final userId = _currentUserId;
    try {
      final response = await http
          .post(
            Uri.parse(AppConfig.tokenUrl),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'userId': userId}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode > 299) {
        debugPrint('DemoTokenMinter: token request failed (${response.statusCode})');
        return null;
      }
      final json = jsonDecode(response.body);
      final body = json is Map && json['data'] is Map ? json['data'] as Map : json as Map;
      final token = body['token'] as String?;
      debugPrint('DemoTokenMinter: got a user token for $userId');
      return token;
    } catch (e) {
      debugPrint('DemoTokenMinter: could not reach ${AppConfig.tokenUrl}: $e');
      return null;
    }
  }
}
