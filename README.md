# NovaCut — Offline-first Mobile Video Editor

NovaCut is an original Flutter-based, CapCut-inspired Android editor with its own name and interface.

## Implemented in code
- Import and preview one local video.
- Select trim-in/trim-out points and export the selected range as MP4 using FFmpeg.
- Render H.264 video and AAC audio to the app's NovaCut documents folder.
- Choose 9:16, 16:9, 1:1 or 4:5 output framing.
- Add a text overlay to preview and exported video.
- Import an audio file and mix it with the source video's audio.
- Apply fade-in/fade-out to the exported clip.
- Save/load project settings and local media paths as an offline JSON project.
- Share an exported MP4 through the Android share sheet.
- GitHub Actions workflow builds an Android APK.

## Limitations and release notes
- This is an early single-video editor, not a full CapCut replacement. Multi-clip timelines, transitions between clips, keyframes, filters, captions and undo/redo are not implemented.
- Music mixing expects the source video to contain an audio stream. Some input codecs may fail on some devices.
- Project files store local media paths. Moving/deleting the original media can make it unavailable when reopening the project.
- Export runs on-device and may take time; keep enough free storage.
- The dependency ffmpeg_kit_flutter_new is the full-GPL variant. Review license and distribution obligations before publishing the app.
- Repository changes are committed, but build and runtime must still be verified by GitHub Actions and on a physical device.

## Build APK
1. Open the repository's Actions tab.
2. Run the Build NovaCut Android APK workflow, or push a commit to main.
3. Wait for dependency resolution, analysis and APK build to finish.
4. Download the novacut-release-apk artifact from a successful run.

## Main files
- lib/main.dart — editor UI, local project save/load and FFmpeg export.
- pubspec.yaml — Flutter dependencies.
- .github/workflows/android.yml — APK build workflow.
