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
- Define campaign skills and class feat progression in JSON.
- Manage equipment in a player-owned stash shared across that player's characters.
- Optionally require enough XP before a character can level up.
- Optionally connect Google Drive to back up character JSON and import JSON
  content packs.

The bundled Tarkov character options pack can be imported from the Catalog
screen. The armory, ammunition, skill definitions, and class-neutral action
lookup are loaded from structured JSON at startup. Weapon profiles support
semi, burst, and full-auto modes; inventory items can define damage, area, and
saving-throw data. See
[`content/tarkov_character_options.json`](content/tarkov_character_options.json)
for classes and choices, [`content/tarkov_armory.json`](content/tarkov_armory.json)
for 105 parsed weapon profiles and 88 ammunition entries,
[`content/skills.json`](content/skills.json) for data-defined skills,
[`content/tarkov_mechanics.json`](content/tarkov_mechanics.json) for action and
ballistics rules, and [`CONTENT_GUIDE.md`](CONTENT_GUIDE.md) for JSON schemas
and authoring instructions.

The player stash is keyed to the character's **Player** field rather than its
character ID. Assign the same player name to multiple characters to share
weapons, armor, ammunition, and other items between them.

## Optional Firebase campaign sharing

Campaign sharing is optional; without Firebase client configuration, the app
continues to use its existing local storage. To configure the Firebase project:
Firebase/Firestore being active in the console is not sufficient by itself:
the running platform must also have non-empty client options in
`lib/firebase_options.dart`. The supplied Android config only enables Android;
Windows and web will continue in local mode until their own options are
generated.

1. Android is wired to the supplied `google-services.json` for package
   `com.example.dnd_campaign_manager_mobile`; its Firebase client options are
   in `lib/firebase_options.dart`. To configure the other platforms, install
   Node.js/npm, the Firebase CLI, and FlutterFire CLI, then run these commands
   from the project root:

   ```powershell
   npm install -g firebase-tools
   firebase login
   dart pub global activate flutterfire_cli
   flutterfire configure --project=dnd-character-manager-80981 --platforms=android,web,windows,ios,macos
   firebase deploy --only firestore:rules --project=dnd-character-manager-80981
   ```

   FlutterFire creates or selects the platform apps and generates
   `lib/firebase_options.dart`; accept the existing Android app when prompted.
   Register each target in the Firebase project (including its exact app or
   bundle ID) if FlutterFire asks for one. Enable **Authentication → Sign-in
   method → Anonymous** and create a **Cloud Firestore** database in the
   Firebase console before using sharing. Commit the generated options file
   and Android `google-services.json`; they contain public client
   configuration, not credentials. Never commit user credentials or service
   account files. For GitHub Pages, add the published site host to Firebase
   Authentication's authorized domains.
2. In **Campaign Settings → Shared campaign**, the DM creates a campaign and
   shares its 16-character join code privately. Players enter that code and a
   display name; Firebase anonymous authentication runs in the background, so
   players do not create accounts or sign in.
3. The DM assigns characters to joined players. Players receive live updates
   to their assigned character and the DM's catalog/rules. The DM can enable
   **Allow players to create characters** in Campaign Settings. When enabled,
   players can use the guided character creator; their new level-1 character is
   assigned to them automatically, or import a character JSON sheet from the
   character list. Imported player sheets are assigned to that player, reset
   to level 1 and 0 XP, and stripped of weapons, armor, and inventory. Level
   progression and gear definitions remain DM-controlled. Players can edit
   their assigned sheet, use items, and roll dice. The creator's ability-score
   rule is defined in
   [`content/character_creation.json`](content/character_creation.json) and
   defaults to six rolls of 4d6, dropping the lowest die from each roll; it
   displays all individual dice and lets players assign scores to abilities.
   The DM dashboard shows HP separately for each character, alongside AC,
   equipment counts, and recent player rolls. Opening a character shows the
   live player view; the DM can select **Edit character** to make changes.

Firestore access is restricted by [`firestore.rules`](firestore.rules): only
the DM can change campaign rules, assignments, and stash contents. Players can
read only characters assigned to their anonymous account, create a level-1
character assigned to themselves when the DM enables that option, update only
player-owned sheet state, and submit their own rolls. A join code is a bearer
invitation—share it only with intended players. Redeploy these rules after
updating the application.
The anonymous DM identity is device/browser-installation bound; clearing app
data or browser storage can permanently remove the DM's ownership identity.
Keep a separate local/exported backup of important characters and campaign
configuration.

Firebase client options generated in `lib/firebase_options.dart` are public
application identifiers, not credentials. No Firebase auth tokens, service
account keys, or admin credentials belong in source, GitHub Actions variables,
or `--dart-define` values. Firebase Auth manages short-lived user credentials
at runtime, while Firestore rules enforce access; never deploy privileged
service-account credentials in this client app.
Until platform-specific options are generated, Android has Firebase client
configuration and other targets remain local-only. Linux remains local-only.

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
