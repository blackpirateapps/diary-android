import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class DiaryController extends ChangeNotifier {
  static const _prefsDarkMode = 'dark_mode';
  static const _prefsFolderPath = 'folder_path';
  static const _prefsMediaFolderPath = 'media_folder_path';

  bool darkMode = false;
  bool hasFileAccessPermission = false;
  String? diaryFolderPath;
  String? mediaFolderPath;
  List<DiaryEntryFile> entries = const [];
  String? lastError;

  String? get effectiveMediaFolderPath => mediaFolderPath ?? diaryFolderPath;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    darkMode = prefs.getBool(_prefsDarkMode) ?? false;
    diaryFolderPath = prefs.getString(_prefsFolderPath);
    mediaFolderPath = prefs.getString(_prefsMediaFolderPath);
    await refreshStoragePermissionStatus();
    await refreshEntries();
  }

  Future<void> setDarkMode(bool value) async {
    darkMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsDarkMode, value);
  }

  Future<void> chooseDiaryFolder() async {
    await _chooseFolder(
      dialogTitle: 'Choose diary folder',
      onSelected: (path) async {
        diaryFolderPath = path;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsFolderPath, path);
        await refreshEntries();
      },
    );
  }

  Future<void> chooseMediaFolder() async {
    await _chooseFolder(
      dialogTitle: 'Choose media folder',
      onSelected: (path) async {
        mediaFolderPath = path;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsMediaFolderPath, path);
        notifyListeners();
      },
    );
  }

  Future<void> clearMediaFolder() async {
    mediaFolderPath = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsMediaFolderPath);
  }

  Future<void> _chooseFolder({
    required String dialogTitle,
    required Future<void> Function(String path) onSelected,
  }) async {
    try {
      final allowed = await ensureStorageAccess(interactive: true);
      if (!allowed) {
        lastError = 'File access permission is required to read/write diary files.';
        notifyListeners();
        return;
      }
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: dialogTitle,
      );
      if (selected == null || selected.isEmpty) return;
      lastError = null;
      await onSelected(selected);
      notifyListeners();
    } catch (e) {
      lastError = 'Folder picker failed: $e';
      notifyListeners();
    }
  }

  Future<void> refreshEntries() async {
    await refreshStoragePermissionStatus();
    final folder = diaryFolderPath;
    if (folder == null || folder.isEmpty) {
      entries = const [];
      notifyListeners();
      return;
    }

    try {
      final dir = Directory(folder);
      if (!await dir.exists()) {
        entries = const [];
        lastError = 'Selected folder no longer exists.';
        notifyListeners();
        return;
      }

      final found = <DiaryEntryFile>[];
      final items = await dir.list(recursive: false, followLinks: false).toList();
      for (final item in items) {
        if (item is! File) continue;
        if (p.extension(item.path).toLowerCase() != '.md') continue;
        final content = await item.readAsString();
        final parsed = MarkdownFrontmatter.parse(content);
        final stat = await item.stat();
        found.add(
          DiaryEntryFile(
            path: item.path,
            fileName: p.basename(item.path),
            rawContent: content,
            bodyMarkdown: parsed.body,
            frontmatter: parsed.frontmatter,
            modifiedAt: stat.modified,
          ),
        );
      }

      found.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
      entries = found;
      lastError = null;
      notifyListeners();
    } catch (e) {
      lastError = 'Failed to read diary folder: $e';
      notifyListeners();
    }
  }

  Future<DiaryEntryFile?> createEntry() async {
    final folder = diaryFolderPath;
    if (folder == null || folder.isEmpty) return null;
    final allowed = await ensureStorageAccess(interactive: true);
    if (!allowed) {
      lastError = 'File access permission is required to create entries.';
      notifyListeners();
      return null;
    }

    final now = DateTime.now();
    final safeStamp = _fileTimestamp(now);
    final filename = '$safeStamp.md';
    final filePath = p.join(folder, filename);
    final template = StringBuffer()
      ..writeln('---')
      ..writeln('title: ${_dateTitle(now)}')
      ..writeln('created: ${now.toIso8601String()}')
      ..writeln('tags: []')
      ..writeln('mood: ')
      ..writeln('images: []')
      ..writeln('---')
      ..writeln()
      ..writeln('Write here...');

    await File(filePath).writeAsString(template.toString());
    await refreshEntries();
    return entries.where((e) => e.path == filePath).firstOrNull;
  }

  Future<void> saveEntry(String path, String rawContent) async {
    final allowed = await ensureStorageAccess(interactive: true);
    if (!allowed) {
      lastError = 'File access permission is required to save entries.';
      notifyListeners();
      return;
    }
    await File(path).writeAsString(rawContent, flush: true);
    await refreshEntries();
  }

  Future<void> deleteEntry(String path) async {
    final allowed = await ensureStorageAccess(interactive: true);
    if (!allowed) {
      lastError = 'File access permission is required to delete entries.';
      notifyListeners();
      return;
    }
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    await refreshEntries();
  }

  Future<void> refreshStoragePermissionStatus() async {
    if (!Platform.isAndroid) {
      hasFileAccessPermission = true;
      notifyListeners();
      return;
    }
    try {
      final fullAccess = await Permission.manageExternalStorage.status;
      final storageAccess = await Permission.storage.status;
      hasFileAccessPermission = fullAccess.isGranted || storageAccess.isGranted;
    } catch (_) {
      hasFileAccessPermission = false;
    }
    notifyListeners();
  }

  Future<bool> ensureStorageAccess({required bool interactive}) async {
    if (!Platform.isAndroid) {
      hasFileAccessPermission = true;
      return true;
    }
    final fullAccessStatus = await Permission.manageExternalStorage.status;
    if (fullAccessStatus.isGranted) {
      hasFileAccessPermission = true;
      notifyListeners();
      return true;
    }
    final storageStatus = await Permission.storage.status;
    if (storageStatus.isGranted) {
      hasFileAccessPermission = true;
      notifyListeners();
      return true;
    }
    if (!interactive) {
      hasFileAccessPermission = false;
      notifyListeners();
      return false;
    }
    final requestedFull = await Permission.manageExternalStorage.request();
    if (requestedFull.isGranted) {
      hasFileAccessPermission = true;
      lastError = null;
      notifyListeners();
      return true;
    }
    final requestedStorage = await Permission.storage.request();
    if (requestedStorage.isGranted) {
      hasFileAccessPermission = true;
      lastError = null;
      notifyListeners();
      return true;
    }
    hasFileAccessPermission = false;
    lastError = 'Grant "All files access" in Android settings for folder-based diary storage.';
    notifyListeners();
    return false;
  }

  Future<void> requestFullFileAccess() async {
    await ensureStorageAccess(interactive: true);
  }

  Future<void> openSystemAppSettings() async {
    await openAppSettings();
    await refreshStoragePermissionStatus();
  }

  String _fileTimestamp(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}_${two(d.hour)}-${two(d.minute)}-${two(d.second)}';
  }

  String _dateTitle(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}

