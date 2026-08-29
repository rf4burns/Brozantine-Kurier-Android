<div align="center">
  <img src="https://sharkord.brozantine.com/icons/Icon-512.png" alt="Kurier" width="128" height="128">
  <h1>Kurier Frontend</h1>
  <p><strong>Flutter web overlay for Kurier: a Discord-style SPA for phones, tablets, and desktop that talks to your own host.</strong></p>

  <p>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License"></a>
    <a href="https://github.com/rf4burns/Brozantine-Kurier-Frontend/commits"><img src="https://img.shields.io/github/last-commit/rf4burns/Brozantine-Kurier-Frontend" alt="Last commit"></a>
    <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.44.9-02569B?logo=flutter&logoColor=white" alt="Flutter 3.44.9"></a>
    <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-3.12.2-0175C2?logo=dart&logoColor=white" alt="Dart 3.12.2"></a>
    <a href="https://mediasoup.org"><img src="https://img.shields.io/badge/mediasoup--client-v3.18.3-green" alt="mediasoup-client 3.18.3"></a>
  </p>

  <p>
    <a href="https://sharkord.brozantine.com">Live</a> ·
    <a href="https://github.com/rf4burns/brozantine-sharkord-server">Server</a> ·
    <a href="https://github.com/rf4burns/brozantine-sharkord-server/releases">Releases</a>
  </p>
</div>

Native Android is in this tree (`android/`). See [ANDROID.md](ANDROID.md). That app does not ship a default host. This overlay remains the web client.

[Brozantine-Kurier-Android](https://github.com/rf4burns/Brozantine-Kurier-Android) is a mirror of this repository. Push to `main` here; GitHub Actions copies that commit to the Android repo. Do not commit in the Android repo.

This repo is the Brozantine **Flutter web overlay** for [Kurier](https://github.com/rf4burns/brozantine-sharkord-server): a self-hosted messenger (Sharkord fork) with a Bun server, tRPC, SQLite, and mediasoup. It is a separate client, not a patch of the in-tree React UI.

> [!NOTE]
> Kurier is still in alpha. Bugs, incomplete features, and breaking changes are expected. This overlay is the phone / tablet / desktop web client. The stock React UI still ships with the server and remains available at `/vanilla/` when this overlay is served in front.

## What it is

Kurier is a self-hosted communication platform for families, friends, and small teams. Think TeamSpeak: focused, lightweight, easy to run, no paywalls. It is not a Discord clone and is not aimed at huge communities.

This repository is **only the Flutter web client**. It talks to a running Kurier host over HTTP login, tRPC v11 WebSocket, and mediasoup. It does not bundle the server, does not write into Kurier’s `interface/{version}/` tree, and does not replace the in-tree React client.

All data stays on the Kurier host. Voice, video, and screen share run through mediasoup on that host. Persistent state lives in SQLite on the server.

Brozantine production is [sharkord.brozantine.com](https://sharkord.brozantine.com). Caddy serves this build at `GET /` and proxies API traffic to Kurier on port **4991**.

## Features

### Chat

- Text channels, DMs, replies, threads, reactions, pins, and file uploads
- Message list with jump-to-bottom, older-history load, and unread / mention badges
- Message search with operators (`from:`, `mentions:`, `in:`, `has:`, `before:`, `after:`, `during:`, `pinned:`)
- Discord-style emoji picker (Twemoji + custom emoji) and a KLIPY GIF picker with favourites
- In-app playback of attached audio and video, plus YouTube (privacy-enhanced iframe)
- Kurier-styled context menus for messages, members, and channels
- Per-channel notification overrides, `@everyone` / `@here`, and mention sounds
- Optimistic image paste-send with a local preview until the server row lands
- Typing indicators, edit / delete, HTML message rendering, and link / media embeds

### Voice and video

- Voice channels with webcam and screen share (change source mid-share)
- Push-to-talk, device picker, input volume, and a pre-join device check
- Speaker / Bluetooth output switch on the voice stage (tap to toggle, long-press to pick a device)
- Tap the stage to unlock audio when the browser blocks autoplay
- Optional keep-screen-on in voice so auto-lock does not cut the microphone
- Always-on mute / deafen on the account bar, plus server mute and deafen
- Occupancy timers, voice channel status, connection quality, and ICE / TURN
- Move members between voice channels (Move Members)
- Music bot panel when the `music-bot` plugin is installed (commands work; React plugin widgets are not rendered)

### Roles, members, and moderation

- Role hierarchy, hoist, and drag-reorder
- Split moderation permissions (kick, ban, mute, deafen, nicknames, audit log)
- Hoisted member-list groups, nicknames, pronouns, and status messages
- Server audit log and privileged backup export
- User tombstone delete (messages keep the same user id and name)
- Invites, access bans (IP, hardware, and browser device token), custom emoji, and channel / category management

### Client and ops

- Saved-host server rail (add / switch / remove Kurier hosts, JWT per host)
- Persistent browser device token (survives reload; clearing site data mints a new one)
- UI sound library for messages, voice join/leave, mute, camera, and screen share
- 12 appearance presets plus accent swatches
- Phone, tablet, and desktop layouts (breakpoints at 768px and 1024px)
- Resizable channel and member sidebars on desktop; sheets / drawers on smaller screens
- Plugin settings and marketplace-style install / update / remove (React plugin widgets are not rendered in this overlay)
- PWA manifest, dynamic tab title / favicon from the host
- UI in English, Čeština, Español, Français, Italiano, Русский, and 中文

## Getting started

This client needs a running [Kurier server](https://github.com/rf4burns/brozantine-sharkord-server). Install that first (binary, Docker, or from source), then point this overlay at the host.

### Requirements

- [Flutter](https://flutter.dev) **stable** with the **web** toolchain (`flutter doctor` should list Chrome). This repo is developed against Flutter **3.44.9** / Dart **3.12.2**.
- A Kurier host on **port 4991**. Voice / WebRTC uses **port 40000** (TCP and UDP) on the server.

### Develop

```bash
flutter pub get
flutter run -d chrome
```

The page origin is the Kurier host when served behind Caddy. For local Chrome dev, add a host on the login rail (for example `localhost:4991`).

> [!IMPORTANT]
> Browsers block mic and camera on plain HTTP except localhost. Use HTTPS (or `localhost`) for voice and video.
>
> Remote voice on the **server** still needs `[webRtc] announcedAddress` in `config.ini` (or `KURIER_WEBRTC_ANNOUNCED_ADDRESS`) set to the host’s public IP or hostname. If it is empty, clients may connect but hear nothing.

### Production build

```powershell
powershell -File tool/build_web.ps1
```

Or:

```bash
flutter pub get
flutter build web --release --base-href / --no-wasm-dry-run \
  --dart-define=WEBRTC_USE_HTML_ELEMENT_VIEW=true \
  --dart-define=KURIER_WEB_STAMP=1.0.2
```

The script writes `build/web/` and a `web_releases.json` stamp. Copy that folder onto the Caddy site root (for Brozantine: `/var/www/brozantine`) and reload Caddy:

```bash
caddy reload --config deploy/Caddyfile
```

Do **not** copy into Kurier’s data `interface/{version}/` folder. Caddy must win `GET /`. Stock Kurier remains at `/vanilla/` on the same host.

## Deploy

`deploy/Caddyfile` is the production pattern used at [sharkord.brozantine.com](https://sharkord.brozantine.com):

| Path | What happens |
| --- | --- |
| `GET /` | Flutter overlay (`file_server` from the site root, SPA fallback to `index.html`) |
| `/vanilla/` | Stock Kurier React client (in-page load of `/vanilla/client`) |
| `/login`, `/upload*`, `/info`, `/healthz`, `/backup`, `/public*`, `/reset-password*` | Proxied to Kurier on `127.0.0.1:4991` |
| `/plugins*`, `/plugin-bundle*`, `/plugin-components*` | Proxied to Kurier |
| WebSocket upgrade | Proxied to Kurier (tRPC subscriptions) |

Vite JS/CSS for `/vanilla/` is also proxied so the stock client’s root-absolute assets still load.

## Configuration

Compile-time `--dart-define` values (empty TURN defines mean host ICE only):

| Define | Purpose | Default |
| --- | --- | --- |
| `KURIER_WEB_STAMP` | Version shown in Settings → About (`WEB vX.Y.Z`) | `dev` |
| `KURIER_TURN_HOST` | TURN host for cellular WebRTC | empty |
| `KURIER_TURN_USER` | TURN username | empty |
| `KURIER_TURN_PASS` | TURN password | empty |
| `KURIER_KLIPY_KEY` | Default KLIPY GIF key | empty |
| `WEBRTC_USE_HTML_ELEMENT_VIEW` | Required for Flutter web media tiles | set in the release build |

Runtime preferences (theme, locale, hosts, JWT, devices, notification / sound flags, sidebar widths) live in the browser via `shared_preferences`. They are not server `config.ini` keys.

The overlay’s default saved host is `sharkord.brozantine.com`. Add others from the login rail.

Server-side ports, data directories, and `config.ini` keys are documented in the [Kurier server README](https://github.com/rf4burns/brozantine-sharkord-server#configuration).

## Architecture

Flutter web app. `flutter pub get` at the repo root, then `flutter run -d chrome` or `tool/build_web.ps1`.

| Path | Role |
| --- | --- |
| `lib/main.dart` | `ProviderScope` + `KurierApp` |
| `lib/app/` | Theme (12 presets), l10n tables, breakpoints, browser tab branding |
| `lib/protocol/` | tRPC v11 WebSocket client, HTTP login / upload / info, models, permissions, search operators, voice and audio-output helpers |
| `lib/session/` | `SessionController` (connection, chat, voice, settings), saved-host store, message history |
| `lib/core/` | Emoji catalog / codec, GIF search, quick reactions |
| `lib/ui/` | Login, home shell (phone / tablet / desktop), chat, voice stage, settings, pickers |
| `web/` | `index.html`, PWA manifest, `mediasoup_bridge.js` (loads `mediasoup-client`), `sounds.js` |
| `deploy/` | Production Caddyfile |
| `tool/` | Release web build script |
| `test/` | Widget, protocol, GIF, and branding tests |

Client and server talk over **tRPC** (queries, mutations, WebSocket subscriptions with `PING` / `PONG` keepalive). Login, uploads, static files, health, backup export, and plugin bundles live on the Kurier HTTP surface and are proxied by Caddy.

Voice uses **mediasoup-client** in the page (`web/mediasoup_bridge.js`) plus `flutter_webrtc` for local devices. Optional TURN (`KURIER_TURN_*`) is for cellular ICE; STUN falls back to Google’s public server.

React plugin widgets are not mounted. Plugin settings, commands, and music-bot actions still go through tRPC.

## Tests

```bash
flutter test
```

Before finishing a change:

```bash
flutter analyze
```

## License

MIT. See [LICENSE](LICENSE).

## Acknowledgments

Kurier is a Brozantine fork of [Sharkord](https://github.com/Sharkord/sharkord) by the Sharkord team. The server and in-tree React client live in [rf4burns/brozantine-sharkord-server](https://github.com/rf4burns/brozantine-sharkord-server).

Built with [Flutter](https://flutter.dev), [Dart](https://dart.dev), [Riverpod](https://riverpod.dev), [tRPC](https://trpc.io), [Mediasoup](https://mediasoup.org), and [Caddy](https://caddyserver.com).
