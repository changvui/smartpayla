# Firebase / Firestore setup

The app runs in **local-only mode** without Firebase. Firestore sync is enabled only when the `FIREBASE_*` values are supplied at build/run time.

## 1. Create the Firebase project

1. Open <https://console.firebase.google.com>.
2. Create a project (for example `smartpayla-fyp`).
3. Add a **Web app** (the `</>` icon).
4. Copy the `firebaseConfig` values.
5. In **Firestore Database**, create a database in test mode for development.
6. In **Authentication**, enable the sign-in method used by the partner module (email/password or Google). The transaction module does not implement login itself.

## 2. Run with the config

```powershell
flutter run -d chrome `
  --dart-define=FIREBASE_API_KEY=... `
  --dart-define=FIREBASE_APP_ID=... `
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... `
  --dart-define=FIREBASE_PROJECT_ID=... `
  --dart-define=FIREBASE_AUTH_DOMAIN=... `
  --dart-define=FIREBASE_STORAGE_BUCKET=... `
  --dart-define=APP_USER_ID=demo-agent `
  --dart-define=DEMO=true
```

`APP_USER_ID` is the owner segment of the Firestore path:

```text
users/{APP_USER_ID}/transactions/{transactionId}
```

The transaction module does not create users. In the integrated build, pass the UID from the partner's Firebase Authentication module instead of `demo-agent`.

## 3. Firestore rules

For the final integrated build, scope every transaction to its signed-in owner:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId}/transactions/{transactionId} {
      allow read, write: if request.auth != null
                         && request.auth.uid == userId;
    }
  }
}
```

While developing the standalone module, there is no auth layer yet. Use test-mode rules **temporarily**:

```javascript
allow read, write: if true;
```

Do not ship test-mode rules. The sync badge will show **Sync error** if Firestore rejects the request.

## 4. Build for GitHub Pages

```powershell
flutter build web --release --base-href /smartpayla/ `
  --dart-define=DEMO=true `
  --dart-define=FIREBASE_API_KEY=... `
  --dart-define=FIREBASE_APP_ID=... `
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... `
  --dart-define=FIREBASE_PROJECT_ID=... `
  --dart-define=APP_USER_ID=demo-agent
```

Add the GitHub Pages domain (`<user>.github.io`) to **Authentication → Settings → Authorized domains** if the partner's auth uses popup/redirect sign-in.

To put the values in GitHub Actions, add them to `.github/workflows/deploy.yml` under the `flutter build web` step. The Firebase web config is not a secret (it identifies the project, it does not grant admin access), but never put a service-account key in a public repo.

## 5. What sync does

- Local storage is the offline cache.
- On start, the app pulls remote transactions and merges by `updatedAt`.
- Every save/delete writes locally first, then pushes to Firestore.
- A Firestore snapshot listener updates the local cache and UI when another device changes a transaction.
- If Firebase is not configured, the app stays fully functional in local mode.

## 6. Troubleshooting

| Symptom | Check |
|---|---|
| Badge stays “Local” | `FIREBASE_PROJECT_ID` / `FIREBASE_API_KEY` not passed; `FirebaseConfig.configured` is false. |
| Badge shows “Sync error” | Firestore rules, `APP_USER_ID`, or the browser being offline. |
| `permission-denied` | Rules require `request.auth.uid == userId`; the standalone build has no auth. Use test rules or the partner's UID. |
| No data after redeploy | Local storage is per browser origin; a new domain starts empty. Demo mode seeds again. |
| Web popup login blocked | Add the deployed domain under Authorized domains. |

See [INTEGRATION.md](INTEGRATION.md) for the partner contract.
