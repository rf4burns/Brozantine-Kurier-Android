# Kurier for Android

Kurier is a self-hosted messenger. This app is the Android client: add your own host, then chat, DM, and join voice.

The source of truth is [Brozantine-Kurier-Frontend](https://github.com/rf4burns/Brozantine-Kurier-Frontend). This tree is mirrored to [Brozantine-Kurier-Android](https://github.com/rf4burns/Brozantine-Kurier-Android) on every push to `main`. Do not commit in the Android repo.

The app does not ship with a default server. On first launch the host list is empty. Type a hostname, confirm, and optionally set that host as the default for later launches.

## Requirements

- Flutter stable with the Android toolchain
- Android 6.0 (API 23) or later
- A running Kurier host (typical ports: HTTP 4991, WebRTC 40000)
- Optional: a Firebase project for closed-app notifications

## Build

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Release:

```bash
flutter build apk
```

## Firebase (optional)

Closed-app push needs:

1. A Firebase Android app with package id `com.brozantine.kurier`
2. Replace `android/app/google-services.json` with your real file (the committed file is a compile placeholder)
3. On the Kurier host, set `KURIER_FCM_SERVICE_ACCOUNT` to a service-account JSON path or the JSON itself

Chat alerts while the app is closed go through Firebase Cloud Messaging (Play Services), not a persistent Kurier process. There is no ongoing “Connected” notification. Voice still shows an ongoing notification while you are in a call.

If Firebase is missing, the app still runs. Text, voice, and in-app banners work; killed-process notifications do not.

## Permissions

Microphone, camera, Bluetooth, notifications, and foreground services are requested when you join voice, share, or enable alerts.

## Branding

Launcher, splash, and About use the Kurier chevron (navy + blue). Emoji artwork is Twemoji (Twitter), CC-BY 4.0.

## License

MIT. See [LICENSE](LICENSE).
