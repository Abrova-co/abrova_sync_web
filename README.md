# AbrovaSync Flutter SDK for the web

The web part of [`abrova_sync`](https://center.abrova.ir), the Flutter SDK of Abrova Sync: a realtime database with
offline-first sync.

[![Flutter 3.44+](https://img.shields.io/badge/Flutter-3.44+-blue.svg)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Installation

**You don't add this package yourself.** Add `abrova_sync` (0.4.1 or later) from
[Abrova Center](https://center.abrova.ir); when you build for the web, Flutter uses this package by itself:

```yaml
dependencies:
  abrova_sync:
    hosted: https://center.abrova.ir/api/packages/abrova/pub
    version: ^0.4.1
```

```bash
flutter pub get
flutter run -d chrome
```

## Usage

The same code as on Android, iOS, macOS, Windows and Linux. Databases and collections are addressed by their
**name**, exactly as shown in Abrova Console:

```dart
import 'package:abrova_sync/abrova_sync.dart';

await AbrovaSync.init(AbrovaSyncConfig(
  apiKey: 'YOUR_API_KEY',
  tokenProvider: () => myBackend.fetchAbrovaToken(), // null when signed out
  offlineEnabled: true, // optional
));
await AbrovaSync.connect();

final todos = AbrovaSync.database('my-app').collection('todos');

final saved = await todos.add({'title': 'Buy milk', 'completed': false});
final updated = await todos.update(saved.id, {'completed': true}); // the saved document, with its version

final listener = todos.listen((documents) {
  print('Todos updated: ${documents.length}');
});
```

## What works on the web

Everything `abrova_sync` does on phones and computers:

- Documents: add, get, getAll, update, set (with merge), delete; `set` and `update` return the saved document
- Queries: filters, order, limit, offset
- Realtime listeners: collections, documents and queries, under your security rules
- Batches
- Verified users: `tokenProvider`, waiting for a sign-in (`onAwaitingUserToken`) and switching users
- Offline persistence in the browser: writes made offline are queued and sent in order when the connection is back;
  conflict strategies and `onDocumentRejected`

## Good to know

- **Your API key is public on the web.** Everyone who opens your page can see it. Protect your data with security
  rules and signed user tokens, and mint the tokens on your own server: the server secret never goes in a web page.
- **Content-Security-Policy:** the SDK ships inside this package (no script from another site). If your page sets a
  Content-Security-Policy, allow `blob:` in `script-src`.
- **Errors** are the same `AbrovaSyncError` codes as on the other platforms.

## Example

[`example/`](example) is the abrova_sync demo (documents, queries, realtime, batches, offline, security rules)
running in the browser. Copy `example/config/local.example.json` to `example/config/local.json`, put in your API key
and database name, then `flutter run -d chrome`.

## Documentation

- [Installation](https://abrova.ir/docs/sync/installation)
- [Security rules](https://abrova.ir/docs/sync/rules)
- [Offline persistence](https://abrova.ir/docs/sync/offline)

## License

MIT
