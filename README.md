# NovaCut

NovaCut is an original CapCut-inspired mobile video editor project. It aims to provide a polished editing workflow while using its own branding and UI rather than copying CapCut's proprietary assets or exact interface.

## Current starter scope
- Flutter Android app foundation
- Import a local video
- Video preview and playback controls
- Editing workspace with timeline-style clip lane
- Aspect-ratio presets and editing tool panels
- Clear project structure for implementing real trim, split, text, audio, transitions and export

## Build
1. Install Flutter stable and Android SDK.
2. Run `flutter pub get`.
3. Run `flutter run` on an Android device.
4. Build an APK with `flutter build apk --release`.

## Important
This is a starter implementation, not yet a full professional NLE. True frame-accurate edits, multi-track compositing, AI captions, and final rendering require dedicated native/media-processing integration and device testing. Never include private API keys in the mobile app.
