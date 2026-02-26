# Diary Android (Cupertino UI)

A Flutter-based Android diary app using Cupertino widgets instead of Material Design.

## Features

- Choose a folder on Android for diary storage
- Diary entries are `.md` files
- Markdown frontmatter (`---`) metadata parsing
- Dark mode toggle in Settings
- GitHub Actions builds APK (no local build required)

## Notes

- The UI intentionally uses `CupertinoApp` / Cupertino widgets.
- Folder access depends on Android file picker behavior and permissions on the device/ROM.
- GitHub Actions workflow builds a debug APK by default and stores it as an artifact.

