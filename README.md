# iBetoo Media 2.0

Native Android + Flutter browser, smart link analysis, media library and background player.

**What changed:**
- Android MediaStore native bridge lists indexed phone music and videos (after granular runtime user consent), with search, filters and sorting.
- Audio queues: next/previous, shuffle, repeat, lock-screen controls and system media notifications.
- Device video playback through content URIs, a next-video playlist, PiP and an explicit handoff to background audio for supported local media.
- Smart paste analyzer recognizes direct HTTPS media using HEAD metadata, downloads original files using DownloadManager, and presents genuine HLS quality variants for playback.
- Improved coherent editorial UI, dark/light themes and in-app browsing including public YouTube pages.
- Android permissions requested for audio, video and notifications; no all-files unrestricted permission.
- New native permissions/MediaStore bridge is checked by manual GitHub Actions before building an APK.

**Boundaries:** YouTube/DRM downloading, video-to-MP3 conversion, invented quality labels and ad blocking on external sites are not implemented. Google sign-in inside WebView can be restricted. HLS source variants are for playback, not MP4 download. Some formats/codecs may be unsupported; background audio handoff from phone content currently needs a temporary file and has a 180 MB per-track limit. Not validated on a device yet.

**Build:** GitHub Actions > Build iBetoo Media APK - Manual Only > Run workflow on main. The workflow runs Dart analysis/tests, Kotlin/Gradle release build, APK checks and emulator startup before publishing a direct APK. No local tool installation required.
