# abrova_sync web example

The `abrova_sync` demo (documents, queries, realtime, batches, offline, security rules) running in the browser.

1. Copy `config/local.example.json` to `config/local.json` and put in your project's API key and database name
   (Abrova Console > your project). `tokenUrl` is optional: your backend's endpoint that mints user tokens, for a
   project that requires signed user tokens.
2. `flutter run -d chrome`
