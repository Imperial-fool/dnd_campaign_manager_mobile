# D&D Campaign Manager

A Flutter app for managing campaign characters, equipment, skills, features,
and JSON-defined content.

## Features

- Create, edit, duplicate, and delete characters.
- Save character data locally in the app.
- Export a character to a local JSON file, or view and copy its JSON.
- Import a character from JSON.
- Import standalone JSON content packs at runtime from the Catalog screen.
- Define classes, subclasses, level progression, and level-up choices in JSON.
- Optionally require enough XP before a character can level up.
- Optionally connect Google Drive to back up character JSON and import JSON
  content packs.

The bundled Tarkov content pack can be imported directly from the Catalog
screen without selecting a file. Additional packs can be imported from a JSON
file or pasted into the app. See
[`content/tarkov_character_options.json`](content/tarkov_character_options.json)
for the bundled pack and [`CONTENT_GUIDE.md`](CONTENT_GUIDE.md) for the JSON
schema and authoring instructions.

## Run the app

Run Flutter commands from the project root—the directory containing
`pubspec.yaml` (this `dnd_campaign_manager_mobile` folder). If your terminal is
in the parent directory, first change into the project folder:

```powershell
cd .\dnd_campaign_manager_mobile
```

Install Flutter and fetch dependencies:

```sh
flutter pub get
```

Run on an available target:

```sh
flutter run
```

### Windows desktop

Windows desktop builds require Visual Studio with the **Desktop development
with C++** workload installed.

```powershell
flutter run -d windows
flutter build windows
```

The release application is created in
`build\windows\x64\runner\Release`. Distribute the contents of that directory
together; the executable alone is not sufficient.

### Web

Run the web app locally with:

```sh
flutter run -d chrome
```

Build a release web app for a subpath (replace `repository-name` with the
GitHub repository name):

```sh
flutter build web --release --base-href /repository-name/
```

The static site is generated in `build/web`.

## GitHub Pages

The workflow at
[`deploy-pages.yml`](.github/workflows/deploy-pages.yml) builds the Flutter
web app and deploys it to GitHub Pages on pushes to the repository's default
branch. It can also be started manually from the Actions tab.

To enable deployment, open the repository's **Settings → Pages** and set
**Build and deployment → Source** to **GitHub Actions**. The published URL is
shown in the workflow run and in the repository's Pages settings.

GitHub Pages provides static hosting only. Character data and imported
content stay in each user's browser unless they connect Google Drive.

## Google Drive

Google Drive is optional. Local character storage and JSON import/export remain
available without connecting an account. When connected, **Save to Google
Drive** creates or updates that character's JSON file in the signed-in user's
Drive. The character roster can import those saved character sheets from that
same account. Imports create a separate local character with a fresh ID, so they
do not overwrite an existing local character. The Catalog screen can also list
Drive JSON files and import a selected content pack, including classes,
features, traits, and items. Imports use the same validation and merge behavior
as local JSON imports.

To enable Drive access:

1. In a Google Cloud project, enable the **Google Drive API** and configure the
   OAuth consent screen. Create a **Web application** OAuth client ID. Add the
   exact deployed site origin (for example, `https://owner.github.io`) to its
   authorized JavaScript origins.
2. Create any additional OAuth client IDs needed for the platforms you will
   build. Android clients need the app's
   package name and signing-certificate SHA-1; also create a web OAuth client
   and use its ID as the Android server client ID. iOS/macOS clients need the
   platform client ID and the reversed client ID URL scheme configured in the
   platform's `Info.plist`.
3. Build or run with `GOOGLE_OAUTH_CLIENT_ID` set to the appropriate client ID:

   ```powershell
   flutter run -d chrome --dart-define=GOOGLE_OAUTH_CLIENT_ID=your-web-client-id
   flutter run -d android --dart-define=GOOGLE_OAUTH_CLIENT_ID=your-web-client-id
   ```

   For iOS/macOS builds, pass that platform's client ID instead. OAuth client
   IDs are public identifiers, not secrets; never put a client secret in the
   app. Configure the consent screen and any verification required by Google's
   Drive read-only scope before distributing the app publicly.

   To enable Google Drive in the GitHub Pages deployment, add a repository
   **Actions variable** named `GOOGLE_OAUTH_CLIENT_ID` under **Settings →
   Secrets and variables → Actions → Variables**, with the Web application
   client ID as its value. The Pages workflow passes this variable to the web
   build. It is a public client identifier, not a secret or an access token.

4. Open **Campaign Settings → Google Drive → Connect** and choose the Google
   account whose Drive should hold the character files. Each user connects their
   own account. On web, use Google's rendered sign-in button, then select
   **Allow Drive access** to authorize file operations. Disconnecting removes
   the app's in-memory account connection; it does not delete files already
   saved in Drive.

Drive sign-in is supported on web, Android, iOS, and macOS. Windows desktop
continues to support local storage and file import/export, but not Google Drive
sign-in.

## Tests and analysis

```sh
flutter test
flutter analyze
```
