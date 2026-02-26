# AI Handoff: `diary-android`

## Project Summary

This repository contains a Flutter Android diary app that uses a **Cupertino (iOS-style) UI** instead of Material Design. The app stores diary entries as Markdown files (`.md`) in a user-selected folder on Android and supports **YAML frontmatter** parsing.

The repository also includes a **GitHub Actions workflow** that builds a debug APK, intended for use on weak local machines that cannot build Android apps.

## Implemented Features

- Cupertino-only application shell (`CupertinoApp`)
- Diary entries stored as raw `.md` files in a chosen folder
- Folder selection via `file_picker` directory picker
- Folder path persisted via `SharedPreferences`
- Entry listing (top-level `.md` files only, non-recursive)
- New entry creation with default markdown + YAML frontmatter template
- Entry editor (raw markdown editor)
- Frontmatter metadata parsing and display (read/preview in list + editor chips)
- Delete entry support
- Settings page with:
  - Dark mode toggle (persisted)
  - Choose diary folder
  - Refresh entries
  - Last error display
- GitHub Actions CI to build and upload a debug APK artifact

## Key Architecture Decisions

### 1) Flutter + Cupertino Widgets (No Material UI)

- The app uses `CupertinoApp` and Cupertino widgets directly.
- `uses-material-design: false` is set in `pubspec.yaml`.
- No Material page scaffolds/components are used.

Note: Flutter still relies on Android/Gradle infrastructure for packaging, but the **app UI layer** is Cupertino.

### 2) File-Based Storage Model

- Each diary entry is a `.md` file in the selected folder.
- The app reads and writes files using `dart:io`.
- This keeps the format portable and easy to edit outside the app.

### 3) Frontmatter Support

- Frontmatter format is expected at the top of the file:
  - Opening delimiter: `---`
  - Closing delimiter: `---`
- YAML is parsed using the `yaml` package.
- Parsing failures are tolerated (editor remains usable).

### 4) Lightweight State Management

- `DiaryController` extends `ChangeNotifier`.
- Root widget rebuilds via `AnimatedBuilder`.
- No external state-management package added.

## File Map

- `lib/main.dart`
  - App bootstrap
  - `DiaryController`
  - Entries screen, settings screen, editor screen
  - Frontmatter parsing utilities
- `pubspec.yaml`
  - Flutter dependencies and project metadata
- `.github/workflows/build-apk.yml`
  - CI workflow to build/upload APK
- `android/...`
  - Manually-created Flutter Android wrapper project files

## Important Constraints / Caveats

### Android Folder Access Caveat

The implementation currently uses `file_picker` directory selection and `dart:io` file access with a filesystem path. On some Android versions/devices/ROMs, selecting arbitrary folders can behave differently due to scoped storage / SAF constraints.

What this means:

- It will work on many setups where the picker returns a valid readable/writable path.
- It may need a SAF-specific plugin (tree URI-based access) for maximum compatibility on all Android devices.

If reliability across many Android versions is critical, migrate storage access to a SAF-native plugin (tree URI operations) instead of raw path IO.

### Gradle Wrapper JAR Not Committed

`android/gradle/wrapper/gradle-wrapper.jar` is not included (binary not generated locally in this environment). The GitHub workflow compensates by running:

- `gradle wrapper --gradle-version 8.4`

before `flutter build apk`.

If you later run `flutter create .` or build locally with Flutter installed, commit the generated wrapper files (including the jar) for a more standard setup.

### Android Icon Resource

The manifest temporarily points `android:icon` to `@drawable/launch_background` to avoid missing generated launcher icon assets in this manual scaffold.

Recommended follow-up:

- Run `flutter create .` (or add proper launcher icons)
- Replace icon with standard mipmap resources

## How to Use (User Flow)

1. Open app
2. Go to `Settings`
3. Tap `Choose Diary Folder`
4. Return to `Entries`
5. Tap `+` to create a markdown entry
6. Edit raw markdown/frontmatter and save

## Markdown Frontmatter Behavior

Example entry format:

```md
---
title: 2026-02-26
created: 2026-02-26T12:34:56.000Z
tags: [personal, work]
mood: calm
---

# 2026-02-26

Today I...
```

Behavior:

- `title` (if present) is used in the entry list title.
- If missing, first markdown heading or first non-empty line is used.
- First few frontmatter properties are shown as metadata preview.

## CI / GitHub Actions Build

Workflow file: `.github/workflows/build-apk.yml`

Triggers:

- Push to `main` or `master`
- Pull requests
- Manual run (`workflow_dispatch`)

Artifact output:

- `diary-android-debug-apk` containing `app-debug.apk`

## Suggested Next Improvements

1. SAF-native folder/tree URI support for better Android compatibility
2. Recursive folder scanning option
3. Search/filter entries by title/tags/date
4. Markdown preview mode (still Cupertino-themed)
5. Frontmatter form editor (title/tags/mood/date fields)
6. Import/export/backup helpers
7. Automated tests (parser + controller logic)
8. Release signing pipeline and release APK/AAB workflow

## Handoff Notes for Future AI/Developer

- The app was authored without local Flutter tooling available, so build validation was not performed locally.
- Prioritize the first remote CI run and fix any version mismatches reported by GitHub Actions.
- If CI fails due to Android/Gradle template drift, the fastest stabilization path is:
  1. Install Flutter locally (or use Codespaces)
  2. Run `flutter create .`
  3. Reapply `lib/main.dart` and workflow/docs
  4. Commit the generated Android wrapper artifacts

