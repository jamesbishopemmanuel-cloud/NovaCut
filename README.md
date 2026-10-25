# NovaCut — Mobile Video Editor

NovaCut is an original Flutter-based, CapCut-inspired Android video editor project. It uses its own name and interface rather than copying CapCut's proprietary branding or assets.

## Implemented in the current starter
- Dark editor UI with a video preview
- Import one local video from device storage
- Play/pause and seek/scrub through the clip
- Preview mute/unmute and playback-speed selection
- Selectable trim-in and trim-out points with duration display
- Canvas ratio selection UI (9:16, 16:9, 1:1, 4:5)
- Timeline-style clip row and project settings sheet
- GitHub Actions workflow to analyze and build an Android release APK

## Important current limitations
- Trim points are currently UI state only; the app does not yet cut the source media or export the selected range.
- Canvas ratio currently updates the project setting label; it does not yet crop or transform the video.
- Audio import/mixing, text overlays, effects, transitions, multi-clip editing, captions, and MP4 rendering are not implemented yet.
- The app has not been device-tested in this repository workflow. Treat build status as unverified until GitHub Actions finishes successfully.

## Build an APK
1. Open the **Actions** tab in this repository and select **Build NovaCut Android APK**.
2. Run the workflow manually, or push a commit to `main`.
3. Wait for the job to complete successfully.
4. Open the completed workflow run and download the `novacut-release-apk` artifact.

To build locally with Flutter installed:

```bash
flutter pub get
flutter analyze
flutter build apk --release
```

## Project files
- `lib/main.dart` — editor UI and preview controls
- `pubspec.yaml` — Flutter dependencies
- `.github/workflows/android.yml` — Android APK build workflow

## Planned milestones
1. Real trim/split and MP4 export using an Android-compatible media pipeline.
2. Multiple video/image clips, title cards, and transitions.
3. Audio tracks, text overlays, and adjustable effects.
4. Offline-first project saving and export presets.
5. Optional remote AI generation service for text-to-video and image-to-video; actual generation requires a configured backend/GPU service.
