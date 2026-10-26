# NovaCut

NovaCut is an offline-first Flutter video-editor prototype.

## Editing tools
- Multi-video import, ordered timeline, drag reordering, split, delete, undo, and redo.
- Preview and playback-speed control.
- Export aspect ratios 9:16, 16:9, 1:1, and 4:5.
- Grayscale, warm, and vintage presets plus manual brightness, contrast, and saturation controls.
- Title/caption overlay.
- Original-audio volume control, separate music selection, and configurable video/audio fade-in/fade-out.
- MP4 export, sharing, local JSON project save/load, and project-file import/export.

## Project portability
Project JSON stores edit settings and media paths, not source media bytes. Original files must remain accessible; moving a project to another device may require re-importing media.

## QA and limitations
Test on Android with media that does and does not contain audio. FFmpeg package compatibility, font availability, codecs, memory use, and export behavior still require verification. The project currently uses an ordered clip list, not a true multi-track timeline. Animated transitions, keyframes, stickers, picture-in-picture, chroma key, automatic captions, voice recording, waveform editing, and a rich effects library are not implemented. NovaCut is not yet a complete CapCut replacement.


## KIE AI Music Studio setup

The Music Studio includes KIE AI song generation, generated audio import, stem extraction, and destructive-copy-free beat cutting. KIE credentials must remain on the server.

1. Deploy `supabase/functions/kie-music/index.ts` to your Supabase project as the `kie-music` Edge Function.
2. Add the server secret `KIE_API_KEY` in Supabase Edge Function secrets.
3. Build the app with `--dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co` and `--dart-define=SUPABASE_ANON_KEY=YOUR_LEGACY_SUPABASE_ANON_JWT_KEY`. The current mobile function call sends this key as a bearer token, so a non-JWT publishable key alone will not pass Supabase's default Edge Function JWT verification.
4. Check KIE credits and pricing before generating or separating stems. KIE media URLs expire after a limited retention period.

This integration keeps the KIE secret out of the mobile app. For production, add user authentication and per-user rate limiting to the Edge Function before public release. Build and test the Flutter app on Android before distributing an APK.


## Music Studio upgrades

The Music Studio now includes microphone vocal recording (via the `record` package), per-track audio preview (via `just_audio`), waveform-style visual lanes, a 16-step synthesized drum sequencer that creates a local WAV loop at the selected BPM, audio section cutting, per-track gain/mute/reordering, and MP3 mixing with Echo, Reverb, Warmth, Bass, Bright, Compressor, or Normalize processing. The waveform display is a visual guide, not a decoded sample-accurate waveform; audio preview is per-track and is not synchronized multi-track playback. The drum maker uses synthesized sounds rather than a bundled sample library.

For Android vocal recording, ensure the app manifest includes `android.permission.RECORD_AUDIO` and test the runtime microphone permission on-device. The KIE integration still requires deploying the Supabase Edge Function and setting `KIE_API_KEY` as a server secret; KIE request/response compatibility, stem separation, Flutter dependency resolution, and Android build must be tested before release. No API secret should be committed to the repository.


## Music Studio: recent implementation notes

- Repaired the mobile request wrapper for the Supabase `kie-music` Edge Function. It sends JSON plus the Supabase `apikey` and bearer headers and surfaces backend error messages.
- Added per-track start offsets (0–120 seconds). The mixer applies these offsets when rendering, so tracks can be arranged relative to each other in the exported mix.
- Added WAV PCM 16-bit / 44.1 kHz export alongside MP3. Export still uses the installed FFmpeg package and must be exercised on a real Android build.
- Session JSON now persists track offsets and export format; older sessions without those fields load with defaults.

## Before release

The repository's Android workflow generates the Android platform scaffold during CI; Android platform files are not currently committed. The CI workflow must pass before treating this as a buildable APK. Verify microphone permission and runtime behavior on a physical device. The track waveform remains a visual guide rather than a sample-accurate waveform, and start offsets affect the rendered mix rather than providing a low-latency live DAW playback engine. Add authenticated user-level quotas/rate limiting to the Edge Function before public launch; keep `KIE_API_KEY` exclusively in Supabase Function secrets.


## Android APK size optimization

The Android CI workflow now builds ABI-specific release APKs (`armeabi-v7a`, `arm64-v8a`, and `x86_64`) instead of relying only on a universal APK, applies Dart obfuscation with separate symbol files, reports each APK's actual size, and creates an Android App Bundle for Play Store delivery. Download the generated artifacts from GitHub Actions after the workflow succeeds.

A strict 4 MB installable APK is not a realistic target for this Flutter app while it includes Flutter runtime, FFmpeg-based video processing, audio recording, and media playback plugins. ABI splitting avoids bundling every CPU architecture into each APK and is the safe first optimization; actual size must be measured by CI. Do not remove FFmpeg or core editor features solely to hit a number without agreeing to those feature trade-offs.
