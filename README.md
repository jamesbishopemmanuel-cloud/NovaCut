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
- Choose export color looks: Original, Warm, Black & white, Vintage and Cool; the selected look is saved with the offline project.
- Save/load project settings and local media paths as an offline JSON project.
- Share an exported MP4 through the Android share sheet.
- GitHub Actions workflow builds an Android APK.

## Limitations and release notes
- This is still an early single-video editor, not a full CapCut replacement. It has basic export color looks, but multi-clip timelines, transitions between clips, keyframes, automatic captions and undo/redo are not implemented. Playback speed currently affects preview; exported speed changes still need implementation and testing.
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


## KIE AI through Supabase

NovaCut now includes a Supabase Edge Function proxy at `supabase/functions/kie-ai/index.ts`. It supports KIE asynchronous task creation and task-status lookup while keeping the KIE API key on the server.

### Configure and deploy

1. In the Supabase project intended for NovaCut, open **Edge Functions → Secrets** and add `KIE_API_KEY` with the key from your KIE account. Do not put this secret in Flutter, the APK, or GitHub.
2. Install the Supabase CLI and link this repository to that Supabase project.
3. Deploy the function: `supabase functions deploy kie-ai`.
4. The caller must be signed in to Supabase and send its session access token in `Authorization: Bearer <access-token>`.

### Request examples

Create an image/video/music task using the model's exact KIE model ID and its documented input parameters:

```json
{
  "action": "create",
  "model": "MODEL_ID_FROM_KIE_DOCS",
  "input": {
    "prompt": "Describe the content to generate"
  }
}
```

Check a task:

```json
{
  "action": "status",
  "taskId": "TASK_ID_RETURNED_BY_KIE"
}
```

Call the deployed function at `<SUPABASE_URL>/functions/v1/kie-ai` with `Content-Type: application/json`, the Supabase publishable key in the `apikey` header, and the signed-in user's access token in the Authorization header. Model IDs and input fields differ by KIE model; use the matching model documentation. A created task is not finished until its status reports completion.

**Important:** The Edge Function code is committed, but it has not been deployed to Supabase and no KIE key has been configured. NovaCut's Flutter UI is not yet wired to call this function; that requires connecting the app to the intended Supabase project and adding sign-in plus AI-generation screens.
