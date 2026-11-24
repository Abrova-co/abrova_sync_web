/// abrova_sync in Flutter web apps. Apps add `abrova_sync`; Flutter uses this
/// package on the web by itself.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'src/convert.dart';
import 'src/js_sdk.dart';
import 'src/sync_web_sdk.g.dart';

const _main = 'ir.abrova.sync/abrova_sync';
const _collections = 'ir.abrova.sync/collection_events';
const _documents = 'ir.abrova.sync/document_events';
const _queries = 'ir.abrova.sync/query_events';

/// Answers the same channel as the Android and iOS plugins, with the Abrova
/// Sync web SDK (embedded: the app loads nothing from a CDN, and phone or
/// computer apps don't carry it). The Dart API in abrova_sync is unchanged.
class AbrovaSyncWeb {
  AbrovaSyncWeb._(this._channel, Registrar registrar) {
    for (final name in [_collections, _documents, _queries]) {
      final controller = StreamController<Object?>.broadcast();
      PluginEventChannel<Object?>(name, const StandardMethodCodec(), registrar).setController(controller);
      _events[name] = controller;
    }
  }

  static void registerWith(Registrar registrar) {
    final channel = MethodChannel(_main, const StandardMethodCodec(), registrar);
    final plugin = AbrovaSyncWeb._(channel, registrar);
    channel.setMethodCallHandler(plugin._handle);
  }

  final MethodChannel _channel;
  final _events = <String, StreamController<Object?>>{};
  final _listeners = <String, JSFunction>{};
  JsSync? _sdk;
  static Future<void>? _loading;

  Future<Object?> _handle(MethodCall call) async {
    final a = call.arguments is Map ? (call.arguments as Map).cast<String, Object?>() : const <String, Object?>{};
    if (call.method == 'init') return _init(a);
    final s = _sdk;
    switch (call.method) {
      case 'isConnected':
        return s?.isConnected() ?? false;
      case 'isAwaitingUserToken':
        return s?.isAwaitingUserToken ?? false;
      case 'disconnect':
        s?.disconnect();
        return null;
      case 'setUserToken':
        if (s == null) throw PlatformException(code: 'notInitialized', message: 'AbrovaSync is not initialized');
        await s.setUserToken(a['token'] as String?).toDart;
        return null;
      case 'removeCollectionListener' || 'removeDocumentListener' || 'removeQueryListener':
        _stop(_req(a, 'listenerId'));
        return null;
    }
    if (s == null) {
      if (call.method == 'executeBatch') throw PlatformException(code: 'NOT_INITIALIZED', message: 'AbrovaSync is not initialized');
      return switch (call.method) {
        'listDatabases' || 'listCollections' || 'getAllDocuments' || 'queryDocuments' => const <Object?>[],
        'getSyncState' => 'idle',
        'getPendingCount' => 0,
        _ => null,
      };
    }
    final code = _codeOf(call.method);
    try {
      return await _call(s, call.method, a);
    } on PlatformException {
      rethrow;
    } on Object catch (e) {
      throw JsErrorInfo(e).platform(code);
    }
  }

  Future<Object?> _init(Map<String, Object?> a) async {
    final apiKey = a['apiKey'];
    if (apiKey is! String || apiKey.isEmpty) throw PlatformException(code: 'INVALID_ARGS', message: 'apiKey is required');
    await (_loading ??= _load());
    final ns = globalContext['AbrovaSync'] as JSObject?;
    final ctor = ns?['default'] as JSFunction?;
    if (ctor == null) throw PlatformException(code: 'web_sdk_missing', message: 'The Abrova Sync web SDK did not load');
    _sdk?.disconnect();
    final host = (a['emulatorHost'] as String?)?.trim();
    final config = <String, Object?>{
      'apiKey': apiKey,
      'userId': ?a['userId'],
      'userToken': ?a['userToken'],
      // As on phones: off unless the app turns it on (the web SDK's own default is on).
      'offlineEnabled': a['offlineEnabled'] == true || a['offlineEnabled'] == 'true',
      'syncOnReconnect': a['syncOnReconnect'] != false,
      'conflictStrategy': a['conflictStrategy'] ?? 'serverWins',
      'logLevel': a['debugMode'] == true ? 4 : 1,
      if (host != null && host.isNotEmpty) 'useEmulator': {'host': host, 'port': a['emulatorPort'] ?? 3006},
      if (a['wrapperSdkName'] is String && a['wrapperSdkVersion'] is String)
        'wrapperSdk': {'name': a['wrapperSdkName'], 'version': a['wrapperSdkVersion']},
    };
    final sdk = JsSync(ctor.callAsConstructor<JSObject>(toJs(config)));
    _sdk = sdk;
    sdk.onConnectionState(((JSString state) {
      final st = state.toDart;
      if (st == 'connected' || st == 'disconnected') _send('onConnectionState', st == 'connected');
    }).toJS);
    sdk.onError(((JSAny error) {
      final info = JsErrorInfo(error);
      // Flutter's onError hears connection problems, as on phones.
      if ((info.code ?? '').startsWith('CONNECTION') || info.code == 'INVALID_CONFIG' || info.code == 'BROKER_UNAVAILABLE') {
        _send('onError', {'code': 'connectionError', 'message': info.message});
      }
    }).toJS);
    sdk.onAwaitingUserToken((() => _send('onAwaitingUserToken')).toJS);
    sdk.onSyncState(((JSString state) => _send('onSyncState', state.toDart)).toJS);
    sdk.onPendingCount(((JSNumber n) => _send('onPendingCount', n.toDartInt)).toJS);
    sdk.onDocumentRejected(((JSString id, JSString op, JSAny error) {
      final info = JsErrorInfo(error);
      _send('onDocumentRejected', {
        'documentId': id.toDart,
        'operation': op.toDart,
        'error': {
          'code': info.queryNotAllowed ? 'query_not_allowed' : 'DOCUMENT_ERROR',
          'message': info.message,
          if (info.status != null || info.reason != null) ...{'statusCode': info.status, 'serverCode': info.reason},
          if (info.queryNotAllowed) 'fields': info.fields,
        },
      });
    }).toJS);
    return null;
  }

  /// The embedded SDK as a `blob:` script, once per page (nothing from a CDN).
  static Future<void> _load() async {
    if (globalContext['AbrovaSync'] != null) return;
    final blob = web.Blob([syncWebSdkJs.toJS].toJS, web.BlobPropertyBag(type: 'text/javascript'));
    final url = web.URL.createObjectURL(blob);
    final script = web.HTMLScriptElement()..src = url;
    final done = Completer<void>();
    script.onload = ((web.Event _) => done.complete()).toJS;
    script.onerror = ((web.Event _) => done.completeError(PlatformException(code: 'web_sdk_missing', message: 'The Abrova Sync web SDK did not load'))).toJS;
    web.document.head!.append(script);
    try {
      await done.future;
    } finally {
      web.URL.revokeObjectURL(url);
    }
  }

  Future<Object?> _call(JsSync s, String method, Map<String, Object?> a) async {
    JsCollection col() => s.database(_req(a, 'databaseId')).collection(_req(a, 'collectionId'));
    switch (method) {
      case 'connect':
        if (!s.isConnected()) s.reconnect();
        return null;
      case 'listDatabases':
        return [for (final d in (await s.listDatabases().toDart).toDart) infoMap(d)];
      case 'createDatabase':
        return infoMap(await s.createDatabase(_req(a, 'name')).toDart);
      case 'deleteDatabase':
        await s.deleteDatabase(_req(a, 'databaseId')).toDart;
        return null;
      case 'listCollections':
        return [for (final c in (await s.listCollections(_req(a, 'databaseId')).toDart).toDart) infoMap(c)];
      case 'createCollection':
        return infoMap(await s.createCollection(_req(a, 'databaseId'), _req(a, 'name')).toDart);
      case 'deleteCollection':
        _req(a, 'collectionId');
        return null; // as Android: the API has no databaseId for it
      case 'addDocument':
        return docMap(await col().add(toJs(_data(a))).toDart);
      case 'getDocument':
        return docMap(await col().document(_req(a, 'documentId')).get().toDart);
      case 'getAllDocuments':
        return [for (final d in (await col().get().toDart).toDart) ?docMap(d)];
      case 'updateDocument':
        return docMap(await col().document(_req(a, 'documentId')).update(toJs(_data(a))).toDart);
      case 'setDocument':
        return docMap(
          await col().document(_req(a, 'documentId')).set(toJs(_data(a)), toJs({'merge': a['merge'] == true})).toDart,
        );
      case 'deleteDocument':
        await col().document(_req(a, 'documentId')).delete().toDart;
        return null;
      case 'queryDocuments':
        return [for (final d in (await _query(s, a).get().toDart).toDart) ?docMap(d)];
      case 'listenCollection':
        final id = _req(a, 'listenerId');
        _listen(id, col().onSnapshot(_onDocs(id, _collections), null, _onListenerError(id, _collections)));
        return null;
      case 'listenDocument':
        final id = _req(a, 'listenerId');
        _listen(id, col().document(_req(a, 'documentId')).onSnapshot(_onDoc(id), _onListenerError(id, _documents)));
        return null;
      case 'listenQuery':
        final id = _req(a, 'listenerId');
        _listen(id, _query(s, a).onSnapshot(_onDocs(id, _queries), _onListenerError(id, _queries)));
        return null;
      case 'executeBatch':
        final ops = a['operations'];
        if (ops is! List) throw PlatformException(code: 'INVALID_ARGS', message: 'operations required');
        await s.executeBatch(toJs(ops) as JSArray<JSAny?>).toDart;
        return null;
      case 'getSyncState':
        return (await s.getSyncState().toDart).toDart;
      case 'getPendingCount':
        return (await s.getPendingCount().toDart).toDartInt;
      case 'forceSyncNow':
        await s.forceSyncNow().toDart;
        return null;
      case 'clearOfflineCache':
        await s.clearOfflineCache().toDart;
        return null;
    }
    throw MissingPluginException('No implementation found for method $method on the web');
  }

  /// A query from the Flutter API's arguments (filters, one order, limit, offset).
  static JsQuery _query(JsSync s, Map<String, Object?> a) {
    final ns = globalContext['AbrovaSync'] as JSObject;
    var q = JsQuery((ns['SyncQuery'] as JSFunction).callAsConstructor<JSObject>(s, _req(a, 'databaseId').toJS, _req(a, 'collectionId').toJS));
    for (final f in (a['filters'] as List?) ?? const []) {
      if (f is Map) q = q.where('${f['field']}', '${f['operator']}', toJs(f['value']));
    }
    final order = a['orderBy'];
    if (order is Map) q = q.orderBy('${order['field']}', order['direction'] == 'desc' ? 'desc' : 'asc');
    if (a['limit'] is num) q = q.limit((a['limit'] as num).toInt());
    if (a['offset'] is num) q = q.offset((a['offset'] as num).toInt());
    return q;
  }

  JSFunction _onDocs(String id, String channel) => ((JSArray<JSObject> docs) {
    _events[channel]?.add({'listenerId': id, 'documents': [for (final d in docs.toDart) ?docMap(d)]});
  }).toJS;

  JSFunction _onDoc(String id) => ((JSObject? doc) {
    _events[_documents]?.add({'listenerId': id, 'document': doc == null ? null : docMap(doc)});
  }).toJS;

  JSFunction _onListenerError(String id, String channel) => ((JSAny error) {
    _events[channel]?.add({'listenerId': id, 'error': JsErrorInfo(error).listenerError()});
  }).toJS;

  void _listen(String id, JSFunction unsubscribe) {
    _stop(id);
    _listeners[id] = unsubscribe;
  }

  void _stop(String id) => _listeners.remove(id)?.callAsFunction();

  void _send(String method, [Object? arguments]) =>
      unawaited(_channel.invokeMethod<void>(method, arguments).then((_) {}, onError: (Object _) {}));

  static String _req(Map<String, Object?> a, String key) {
    final v = a[key];
    if (v is! String || v.isEmpty) throw PlatformException(code: 'INVALID_ARGS', message: '$key required');
    return v;
  }

  static Map<String, Object?> _data(Map<String, Object?> a) {
    final d = a['data'];
    if (d is! Map) throw PlatformException(code: 'INVALID_ARGS', message: 'data required');
    return d.cast<String, Object?>();
  }

  static String _codeOf(String method) => switch (method) {
    'connect' => 'CONNECTION_ERROR',
    'listDatabases' || 'createDatabase' || 'deleteDatabase' => 'DATABASE_ERROR',
    'listCollections' || 'createCollection' || 'deleteCollection' => 'COLLECTION_ERROR',
    'queryDocuments' || 'listenQuery' => 'QUERY_ERROR',
    'executeBatch' => 'BATCH_ERROR',
    'forceSyncNow' => 'SYNC_ERROR',
    'clearOfflineCache' => 'CACHE_ERROR',
    _ => 'DOCUMENT_ERROR',
  };
}
