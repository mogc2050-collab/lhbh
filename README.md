# iBetoo Media 3.0

Arabic Android offline media library and Quetta-inspired browser. **No in-app file downloader.**

Core media: MediaStore index for audio/video/images, live Android ContentObserver updates, folders, albums, artists, thumbnails, playlists, smart favorites/history/resume, queue, background audio/lock-screen MediaSession, video PiP/gestures/next, SRT/VTT, Android equalizer, speed/sleep timer, SHA-256 duplicate detection (read-only), user-consented media imports, backup of library metadata and optional biometric/device-lock access.

Browser: simple bottom address bar, favorites, history, tabs, quick access sites, search engine choice, reader mode, experimental page darkening and local-history-free private tabs. Android WebView is not a full standalone Chromium browser. Chrome extensions and complete request-level ad blocking are not implemented. Private tabs share WebView cookie storage and are not fully isolated.

Original phone files are never silently renamed, moved or removed. Imported app-owned copies can be renamed and organized within the app. Backups restore metadata, not raw media files. Codec and DRM restrictions apply.

**All web-file download screens, smart link downloader and native DownloadManager code are removed.** APK artifact creation in GitHub Actions remains.

Manual APK: Actions > Build iBetoo Media APK - Manual Only > Run workflow on main. Full compile, Android checks, signature verification and emulator smoke test are required before treating the build as validated.

Google sign-in for this app still needs official OAuth SHA-1 setup; signing demo key in repository is not appropriate for production.

This release has not yet been validated on a physical Android device.
