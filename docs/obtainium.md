# Distributing Fermata through Obtainium

Obtainium installs and updates Android apps straight from the project's own
release page. Fermata publishes GitHub Releases, Obtainium reads them, and the
user never touches a store.

Two halves, and they are genuinely separate:

| Half | Where it lives | What breaks if it is wrong |
| --- | --- | --- |
| **Distribution** — APKs on GitHub Releases, signed with one stable key | `.github/workflows/release.yml` | Obtainium finds nothing, or refuses to install over an existing copy |
| **Hand-off** — a deep link from inside Fermata | `app/lib/src/update/`, `app/lib/src/features/settings/settings_screen.dart` | The in-app button does nothing; Obtainium itself is fine |

## The one file that matters

`app/assets/distribution/obtainium_config.json`

```json
{
  "id": "com.hoid.fermata",
  "url": "https://github.com/CephandriusMaxtori/Fermata",
  "author": "CephandriusMaxtori",
  "name": "Fermata",
  "additionalSettings": {
    "apkFilterRegEx": "Fermata-[0-9.]+\\.apk",
    "includePrereleases": false,
    "sortMethodChoice": "smartname-datefallback"
  }
}
```

- `id` **must** equal `applicationId` in `app/android/app/build.gradle.kts`. It
  is how Obtainium decides the app it is tracking is the one Android has
  installed; a mismatch means updates are reported but never applied.
- `url` is the GitHub repo. Obtainium resolves it to the GitHub source and polls
  `/releases/latest`, so no access token is needed unless the user adds a lot of
  GitHub apps and hits the 60/hour anonymous rate limit.
- `apkFilterRegEx` matters because the release workflow also attaches a `.sha256`
  checksum. Without a filter Obtainium sees two assets per release and prompts
  for one on every update, which is exactly the friction the app exists to remove.

The in-app deep link is built from this file at runtime
(`ObtainiumApp.fromJson`), and `obtainium_app_test.dart` asserts the encoding
round-trips. Do not copy the JSON into Dart.

## Versioning, and why both halves of `version:` matter

`app/pubspec.yaml`:

```yaml
version: 1.2.0+3
```

- **`1.2.0` is the version name.** Obtainium compares the release tag against
  the installed version name to decide whether an update exists. So the tag
  **must** be `v1.2.0` — the `v` is stripped on both sides, the number is not.
  A release tagged `1.2` against an installed `1.2.0` still reads as equal,
  because the comparison pads with zeroes, but a release tagged `v1.2.1` against
  `1.2.0` is the normal path and it has to be exact.
- **`3` is the version code.** Android refuses to install over an existing app
  unless the code increases. Bumping only the name leaves Obtainium reporting an
  update forever while the installer declines it.

The release workflow **fails the build** if the tag and `pubspec.yaml` disagree,
so the two cannot drift:

```
tag v1.2.0 does not match pubspec version 1.3.0+4
```

## Releasing

```bash
# 1. Bump app/pubspec.yaml: name AND build code.
# 2. Merge to main, let CI go green.
# 3.
git tag v1.2.0
git push origin v1.2.0
```

The `release.yml` workflow then:

1. Checks the tag against `pubspec.yaml` and fails on a mismatch.
2. Decodes the signing keystore from the `RELEASE_KEYSTORE_BASE64`,
   `RELEASE_KEYSTORE_PASSWORD`, `RELEASE_KEY_ALIAS` and `RELEASE_KEY_PASSWORD`
   secrets.
3. Builds a **universal** release APK (`--split-per-abi` is not used: Obtainium's
   CPU filter is a filename heuristic and a universal APK sidesteps it, at the
   cost of size).
4. Verifies the signature with `apksigner`, so a keystore that failed to decode
   is caught here rather than by a user's install.
5. Attaches `Fermata-<version>.apk` and `Fermata-<version>.apk.sha256` to a
   GitHub Release.

### One-time repository setup

```bash
keytool -genkey -v -keystore fermata-release.jks \
  -keyalg RSA -keysize 4096 -validity 10000 -alias fermata

base64 -w 0 fermata-release.jks > fermata-release.b64
```

Add `fermata-release.b64` and the passwords as the four repository secrets.
**Keep the keystore file itself.** GitHub secrets are write-only: the base64 blob
is the only copy, and losing it means every future release is signed with a
different key, which no Android device will accept as an update over the
previous one. `docs/obtainium.md` cannot recover it.

`build.gradle.kts` falls back to the debug signing config when no `key.properties`
exists, so a contributor with no secrets can still build. A locally-built release
APK is debug-signed and **cannot** be replaced by a CI-built one — sign it locally
too, or install it with `adb install -r -d` knowing the next real update will need
a clean install.

## Using it as a user

1. Install Obtainium (F-Droid, IzzyOnDroid, or its own GitHub releases).
2. Tap the add button in Fermata's Settings → *Install and update with Obtainium*,
   or open [apps.obtainium.imranr.dev](https://apps.obtainium.imranr.dev/) and
   search for Fermata.
3. Obtainium asks once, shows the raw JSON, then tracks the repo. Background
   updates are on by default.

Fermata's Settings tab also checks GitHub Releases itself, so an update is
visible before Obtainium's next poll. That check is manual, not on launch:
Obtainium exists to run these on a schedule, and a second poller inside the app
would spend battery to reach the same answer.

## Permissions

Fermata declares exactly one: `INTERNET`, and only for that release check.
Obtainium itself needs none of Fermata's storage; the library is untouched by an
update.