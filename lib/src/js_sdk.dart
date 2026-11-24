import 'dart:js_interop';

/// The web SDK's objects (`@abrova/sync-web`), as the bridge uses them.
extension type JsSync(JSObject _) implements JSObject {
  external JSPromise<JSAny?> setUserToken(String? token);
  external bool get isAwaitingUserToken;
  external bool isConnected();
  external void disconnect();
  external void reconnect();
  external JsDatabase database(String name);
  external JSPromise<JSArray<JSObject>> listDatabases();
  external JSPromise<JSObject> createDatabase(String name);
  external JSPromise<JSAny?> deleteDatabase(String databaseId);
  external JSPromise<JSArray<JSObject>> listCollections(String databaseName);
  external JSPromise<JSObject> createCollection(String databaseName, String name);
  external JSPromise<JSAny?> executeBatch(JSArray<JSAny?> operations);
  external JSPromise<JSString> getSyncState();
  external JSPromise<JSNumber> getPendingCount();
  external JSPromise<JSAny?> forceSyncNow();
  external JSPromise<JSAny?> clearOfflineCache();
  external JSFunction onConnectionState(JSFunction callback);
  external JSFunction onError(JSFunction callback);
  external JSFunction onAwaitingUserToken(JSFunction callback);
  external JSFunction onSyncState(JSFunction callback);
  external JSFunction onPendingCount(JSFunction callback);
  external JSFunction onDocumentRejected(JSFunction callback);
}

extension type JsDatabase(JSObject _) implements JSObject {
  external JsCollection collection(String name);
}

extension type JsCollection(JSObject _) implements JSObject {
  external JSPromise<JSObject> add(JSAny? data);
  external JSPromise<JSArray<JSObject>> get();
  external JsDocument document(String id);
  external JSFunction onSnapshot(JSFunction callback, [JSAny? options, JSFunction? onError]);
}

extension type JsDocument(JSObject _) implements JSObject {
  external JSPromise<JSObject?> get();
  external JSPromise<JSObject?> set(JSAny? data, [JSAny? options]);
  external JSPromise<JSObject?> update(JSAny? data);
  external JSPromise<JSAny?> delete();
  external JSFunction onSnapshot(JSFunction callback, [JSFunction? onError]);
}

extension type JsQuery(JSObject _) implements JSObject {
  external JsQuery where(String field, String operator, JSAny? value);
  external JsQuery orderBy(String field, [String direction]);
  external JsQuery limit(int count);
  external JsQuery offset(int count);
  external JSPromise<JSArray<JSObject>> get();
  external JSFunction onSnapshot(JSFunction callback, [JSFunction? onError]);
}
