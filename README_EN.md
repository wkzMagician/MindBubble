# MindBubble

MindBubble is a cross-platform, local-first concept reminder app. It supports Markdown notes, five appearance-frequency levels, Agent imports, and WebDAV sync.

## Supported platforms

Windows, macOS, Linux, and Android share the same SQLite model. Windows, macOS, and Linux provide a “launch at login” setting. Android restores local state and sync when the user next opens the app.

| Platform | Development requirements | Release artifact |
| --- | --- | --- |
| Windows | Flutter SDK; Visual Studio Desktop development with C++ | MSIX |
| macOS | Flutter SDK; Xcode | DMG |
| Linux | Flutter SDK; GTK/Clang build prerequisites | AppImage |
| Android | Flutter SDK; Android Studio/SDK | APK, AAB |

```powershell
flutter pub get
flutter run -d windows # or macos, linux, android
dart format lib test
flutter analyze
flutter test
```

## Daily selection

On its first Ocean view each day, the app caches up to five bubbles; changing frequency does not redraw that day’s selection. An unseen bubble gets `+100` on the day after creation; time since it was last shown contributes up to `+50`; the five frequencies from very rare to frequent contribute `-30/-15/0/+15/+30`; and a random component contributes up to `+20`. Bubbles shown in the past day receive `-50`, while those shown in the past three days receive `-20`. The app then samples without replacement using the resulting non-negative relative weights.

## Import

The import button in Manage Bubbles accepts CSV and XLSX. It recognizes `title`/`标题` and `description`/`正文`/`描述`; rows missing either field are skipped. Titles are deduplicated case-insensitively.

## Agent / MCP

The repository’s [MCP server](tools/mind_bubble_mcp.py) lets Codex, Claude Code, OpenCode, and other MCP clients work with the same local bubbles. It provides `import_bubbles`, `list_bubbles`, `search_bubbles`, `get_bubble`, `update_bubble`, and `delete_bubble`.

### Start the MCP server

Replace the placeholder paths below with your own paths:

```powershell
$env:MIND_BUBBLE_DB = "/path/to/your/data/mind_bubble.db"
python /path/to/your/project/tools/mind_bubble_mcp.py
```

The server waits for JSON-RPC requests from an MCP client; do not type requests into it manually. MindBubble creates the database when first launched.

### Configure an Agent

Use [the example](tools/mind-bubble.mcp.json) as a template:

```json
{
  "mcpServers": {
    "mind-bubble": {
      "command": "python",
      "args": ["/path/to/your/project/tools/mind_bubble_mcp.py"],
      "env": {
        "MIND_BUBBLE_DB": "/path/to/your/data/mind_bubble.db"
      }
    }
  }
}
```

- Codex: add this server through the MCP configuration UI or configuration file.
- Claude Code: add the object to `mcpServers` in the project `.mcp.json`.
- OpenCode: add the same `mcpServers` object to its project or user configuration.

Restart the Agent and ask it to list MindBubble bubbles to verify that it discovers `list_bubbles`.

## WebDAV sync

Open **Manage Bubbles → Settings → WebDAV sync**. The app works with Jianguoyun, Nextcloud, and other compatible WebDAV providers.

### Jianguoyun example

1. Create and sign in to a Jianguoyun account.
2. In account security settings, create an **app password**. Do not use your normal sign-in password.
3. In MindBubble, leave the server as `https://dav.jianguoyun.com/dav/`.
4. Enter your Jianguoyun email and the app password/API key.
5. Select **Save and enable**. The configuration persists; the password remains obscured in the UI.
6. Use the same WebDAV credentials on every device that should sync.

The WebDAV configuration is stored as `webdav_config.json` in the application support directory. Bubble content is not additionally end-to-end encrypted.

## Packaging

```powershell
flutter build windows
flutter build apk
flutter build appbundle
# On the corresponding host: flutter build macos / flutter build linux
```
