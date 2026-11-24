import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';

/// Dart values to JS (maps, lists, numbers, text, booleans, null).
JSAny? toJs(Object? v) => _plain(v).jsify();

Object? _plain(Object? v) => switch (v) {
  Map() => {for (final e in v.entries) '${e.key}': _plain(e.value)},
  List() => [for (final x in v) _plain(x)],
  _ => v,
};

/// JS values to what the Flutter API reads: String-keyed maps, and whole
/// numbers as int (JS has one number type), as the native plugins send.
Object? fromJs(JSAny? v) => _ints(v.dartify());

Object? _ints(Object? v) => switch (v) {
  Map() => <String, Object?>{for (final e in v.entries) '${e.key}': _ints(e.value)},
  List() => [for (final x in v) _ints(x)],
  double() when v.isFinite && v == v.truncateToDouble() && v.abs() < 9007199254740992 => v.toInt(),
  _ => v,
};

/// Epoch ms from a number or ISO text (the web SDK keeps server times as text).
int? millis(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? DateTime.tryParse(v)?.millisecondsSinceEpoch;
  return null;
}

/// A web SDK document as the Flutter API reads it (`{id, data, createdAt,
/// updatedAt, version}`, times in ms).
Map<String, Object?>? docMap(JSAny? doc) {
  final m = fromJs(doc);
  if (m is! Map<String, Object?>) return null;
  final now = DateTime.now().millisecondsSinceEpoch;
  final updated = millis(m['updatedAt']) ?? now;
  return {
    'id': m['id'] is String ? m['id'] : '',
    'data': m['data'] is Map ? m['data'] : <String, Object?>{},
    'createdAt': millis(m['createdAt']) ?? updated,
    'updatedAt': updated,
    'version': m['version'] is num ? (m['version'] as num).toInt() : 1,
  };
}

/// `DatabaseInfo` / `CollectionInfo` maps with times in ms.
Map<String, Object?> infoMap(JSAny? info) {
  final m = (fromJs(info) as Map<String, Object?>?) ?? {};
  return {...m, 'createdAt': millis(m['createdAt']) ?? 0, 'updatedAt': millis(m['updatedAt']) ?? 0};
}

/// Reads a JS error (`AbrovaSyncError`): code, reason, message, status, fields.
class JsErrorInfo {
  JsErrorInfo(Object e)
    : _o = _jsObject(e),
      _text = '$e';

  /// A thrown JS value as an object (a Dart exception gives null).
  static JSObject? _jsObject(Object e) {
    try {
      final any = e as JSAny;
      return any.isA<JSObject>() ? any as JSObject : null;
    } on Object {
      return null;
    }
  }

  final JSObject? _o;
  final String _text;

  String? _s(String k) => (_o?[k] as JSString?)?.toDart;

  String get message => _s('message') ?? _text;
  String? get reason => _s('reason');

  /// The error code's name (`CONNECTION_FAILED`, `DATA_WRITE_FAILED`, …): the web
  /// SDK's codes are numbers of a TypeScript enum, read back through its names.
  String? get code {
    final raw = _o?['code'];
    if (raw == null) return null;
    if (raw.isA<JSString>()) return (raw as JSString).toDart;
    if (!raw.isA<JSNumber>()) return null;
    final names = (globalContext['AbrovaSync'] as JSObject?)?['AbrovaSyncErrorCode'] as JSObject?;
    final name = names?[(raw as JSNumber).toDartInt.toString()];
    return name != null && name.isA<JSString>() ? (name as JSString).toDart : null;
  }
  int? get status => ((_o?['statusCode'] ?? _o?['status']) as JSNumber?)?.toDartInt;
  List<String> get fields => [for (final f in (fromJs(_o?['fields']) as List?) ?? const []) if (f is String) f];
  bool get queryNotAllowed => reason == 'query_not_allowed' || code == 'QUERY_NOT_ALLOWED';

  /// As the native plugins' `Result.fail`.
  PlatformException platform(String fallbackCode) => queryNotAllowed
      ? PlatformException(code: 'query_not_allowed', message: message, details: {'fields': fields, 'statusCode': status ?? 403})
      : PlatformException(
          code: fallbackCode,
          message: message,
          details: status == null && reason == null ? null : {'statusCode': status, 'serverCode': reason},
        );

  /// The error a stopped listener carries (native `listenerErrorMap`).
  Map<String, Object?> listenerError() => queryNotAllowed
      ? {'code': 'query_not_allowed', 'message': message, 'fields': fields, 'statusCode': status ?? 403}
      : {'code': reason ?? (status == 403 ? 'permission_denied' : 'UNKNOWN_ERROR'), 'message': message, 'statusCode': status};
}
