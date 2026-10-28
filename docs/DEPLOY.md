# Deploy SmartPayLA (free, permanent URL, auto-update)

The recommended setup is **GitHub Pages + GitHub Actions**:

- The link stays the same every time you push code.
- Every push to `main` rebuilds the Flutter web app and redeploys it.
- Free for **public** repositories.
- The app is static, so there is no server to keep awake.

The workflow is already in this repo at `.github/workflows/deploy.yml`.

---

## 1. Create the GitHub repository

1. Sign in to <https://github.com>.
2. Click **New repository**.
3. Name it **`smartpayla`**.
4. Choose **Public** (required for free GitHub Pages).
5. Do **not** add a README, `.gitignore` or licence — this project already has them.
6. Click **Create repository**.

The project is already a local git repo with one commit. You only need to add the remote and push.

### Easiest: GitHub Desktop

1. Install [GitHub Desktop](https://desktop.github.com/) and sign in.
2. **File → Add local repository**.
3. Choose `C:\Users\chang\Desktop\DSH\FYP\smartpayla`.
4. Click **Publish repository**.
5. Keep the name `smartpayla`, uncheck **Keep this code private**, publish.

### Or: terminal

```powershell
cd C:\Users\chang\Desktop\DSH\FYP\smartpayla
$env:Path = "C:\Users\chang\Desktop\DSH\flutter\bin\mingit\cmd;" + $env:Path
git remote add origin https://github.com/<your-username>/smartpayla.git
git push -u origin main
```

If Git asks for a password, GitHub requires a **Personal Access Token**, not your account password. GitHub Desktop avoids this.

---

## 2. Turn on GitHub Pages

1. Open the repository on GitHub.
2. **Settings → Pages**.
3. Under **Build and deployment → Source**, choose **GitHub Actions**.
4. Open the **Actions** tab. The workflow “Deploy SmartPayLA to GitHub Pages” should be running.
5. Wait 1–2 minutes. The URL is:

```text
https://<your-username>.github.io/smartpayla/
```

Open it on iPhone Safari and Android Chrome.

---

## 3. Update the app later

After changing the code:

```powershell
cd C:\Users\chang\Desktop\DSH\FYP\smartpayla
git add .
git commit -m "Describe your change"
git push
```

GitHub Actions rebuilds and redeploys automatically. The link does **not** change. Refresh the browser (or close/reopen the PWA) to see the new version.

In GitHub Desktop: write a summary → **Commit to main** → **Push origin**.

---

## Notes and limits

- **Free GitHub Pages needs a public repository.** Anyone can read the code. If the code must stay private, use Netlify Drop (manual update) or a private Netlify site connected to a private repo.
- No free host offers a 100% uptime guarantee. GitHub Pages is stable and has no expiry date, but it is not an SLA-backed service.
- The workflow builds with `--dart-define=DEMO=true`, so a new browser gets the five sample transactions. Remove that flag in `.github/workflows/deploy.yml` for an empty ledger.
- The URL is a **project page** (`/smartpayla/`). The workflow sets `--base-href` from the repository name automatically. If you rename the repo, the base href follows the new name; if you use a `<username>.github.io` repository, change the base href to `/`.
- **Transaction data is local to each browser.** Updating the hosted code does not sync data between iPhone and Android. That needs the Firestore layer in Increment 2.

---

## Alternative: Netlify Drop (no GitHub, manual update)

Use this if you do not want a GitHub account or a public repo:

1. Run `flutter build web --release --dart-define=DEMO=true`.
2. Zip the contents of `build/web` (the project already produces `build/smartpayla-web.zip`).
3. Open <https://app.netlify.com/drop>.
4. Drag the zip in.
5. Claim the site (free account) to keep the URL permanently.
6. To update, drag a new zip onto the same site.

The URL is permanent after claiming, but **you must re-upload** after every change. There is no automatic deploy.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| 404 on the GitHub Pages URL | Settings → Pages → Source must be **GitHub Actions**; check the Actions tab for a failed workflow. |
| Blank page | Check the workflow’s `--base-href`; it must match `/<repo-name>/`. |
| Workflow fails at “Set up Flutter” | Re-run the workflow; GitHub Actions occasionally has a transient download failure. |
| Old version still shows | Hard refresh (Ctrl+F5), close/reopen the PWA, or clear the site data. Flutter web uses a service worker cache. |
| Works on PC but not phone | Use the public GitHub Pages URL, not the LAN IP. Phones may be on a different Wi-Fi subnet or the router may isolate clients. |
