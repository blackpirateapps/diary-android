import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DiaryAppBootstrap());
}

class DiaryAppBootstrap extends StatefulWidget {
  const DiaryAppBootstrap({super.key});

  @override
  State<DiaryAppBootstrap> createState() => _DiaryAppBootstrapState();
}

class _DiaryAppBootstrapState extends State<DiaryAppBootstrap> {
  final DiaryController _controller = DiaryController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    await _controller.load();
    if (mounted) {
      setState(() => _loaded = true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const CupertinoApp(
        home: CupertinoPageScaffold(
          child: Center(child: CupertinoActivityIndicator()),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CupertinoApp(
          title: 'Diary',
          theme: CupertinoThemeData(
            brightness: _controller.darkMode ? Brightness.dark : Brightness.light,
          ),
          home: HomeScreen(controller: _controller),
        );
      },
    );
  }
}

class DiaryController extends ChangeNotifier {
  static const _prefsDarkMode = 'dark_mode';
  static const _prefsFolderPath = 'folder_path';

  bool darkMode = false;
  bool hasFileAccessPermission = false;
  String? diaryFolderPath;
  List<DiaryEntryFile> entries = const [];
  String? lastError;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    darkMode = prefs.getBool(_prefsDarkMode) ?? false;
    diaryFolderPath = prefs.getString(_prefsFolderPath);
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
    try {
      final allowed = await ensureStorageAccess(interactive: true);
      if (!allowed) {
        lastError = 'File access permission is required to read/write diary files.';
        notifyListeners();
        return;
      }
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose diary folder',
      );
      if (selected == null || selected.isEmpty) {
        return;
      }
      diaryFolderPath = selected;
      lastError = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsFolderPath, selected);
      await refreshEntries();
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
        if (item is! File) {
          continue;
        }
        if (p.extension(item.path).toLowerCase() != '.md') {
          continue;
        }
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
      ..writeln('---')
      ..writeln()
      ..writeln('# ${_dateTitle(now)}')
      ..writeln()
      ..writeln('Write here...');

    final file = File(filePath);
    await file.writeAsString(template.toString());
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
    final file = File(path);
    await file.writeAsString(rawContent, flush: true);
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

  String _fileTimestamp(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}_${two(d.hour)}-${two(d.minute)}-${two(d.second)}';
  }

  String _dateTitle(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
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
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final DiaryController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        currentIndex: _tabIndex,
        onTap: (index) => setState(() => _tabIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.book),
            label: 'Entries',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.settings),
            label: 'Settings',
          ),
        ],
      ),
      tabBuilder: (context, index) {
        return CupertinoTabView(
          builder: (context) {
            if (index == 0) {
              return EntriesScreen(controller: widget.controller);
            }
            return SettingsScreen(controller: widget.controller);
          },
        );
      },
    );
  }
}

class EntriesScreen extends StatelessWidget {
  const EntriesScreen({super.key, required this.controller});

  final DiaryController controller;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Diary'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () async {
            if (controller.diaryFolderPath == null) {
              await _showInfo(context, 'Choose a diary folder first in Settings.');
              return;
            }
            final created = await controller.createEntry();
            if (created != null && context.mounted) {
              await Navigator.of(context).push(
                CupertinoPageRoute(
                  builder: (_) => EntryEditorScreen(
                    controller: controller,
                    initialEntry: created,
                  ),
                ),
              );
            }
          },
          child: const Icon(CupertinoIcons.add),
        ),
      ),
      child: SafeArea(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            if (controller.diaryFolderPath == null) {
              return const _EmptyState(
                title: 'No folder selected',
                message: 'Open Settings and choose a folder to store .md diary files.',
              );
            }

            if (controller.entries.isEmpty) {
              return ListView(
                children: [
                  _FolderBanner(path: controller.diaryFolderPath!),
                  const SizedBox(height: 16),
                  const _EmptyState(
                    title: 'No diary entries',
                    message: 'Tap + to create your first markdown note.',
                  ),
                ],
              );
            }

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _FolderBanner(path: controller.diaryFolderPath!),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                    final entry = controller.entries[index];
                    final title = _entryDisplayTitle(entry);
                    final preview = _previewLine(entry.bodyMarkdown);
                    final metadataText = entry.frontmatter.isEmpty
                        ? 'No frontmatter'
                        : entry.frontmatter.entries
                            .take(3)
                            .map((e) => '${e.key}: ${e.value}')
                            .join('  •  ');

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () async {
                        await Navigator.of(context).push(
                          CupertinoPageRoute(
                            builder: (_) => EntryEditorScreen(
                              controller: controller,
                              initialEntry: entry,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: CupertinoColors.separator.resolveFrom(context),
                              width: 0.0,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: CupertinoTheme.of(context)
                                  .textTheme
                                  .navTitleTextStyle
                                  .copyWith(fontSize: 17),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              metadataText,
                              style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                                    fontSize: 12,
                                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (preview.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                preview,
                                style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                                      fontSize: 14,
                                      color: CupertinoColors.label.resolveFrom(context),
                                    ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                    },
                    childCount: controller.entries.length,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _entryDisplayTitle(DiaryEntryFile entry) {
    final frontmatterTitle = entry.frontmatter['title']?.toString().trim();
    if (frontmatterTitle != null && frontmatterTitle.isNotEmpty) return frontmatterTitle;
    for (final line in const LineSplitter().convert(entry.bodyMarkdown)) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#')) {
        return trimmed.replaceFirst(RegExp(r'^#+\s*'), '');
      }
      if (trimmed.isNotEmpty) return trimmed;
    }
    return entry.fileName;
  }

  String _previewLine(String markdown) {
    final lines = const LineSplitter().convert(markdown);
    for (final line in lines) {
      final cleaned = line.trim();
      if (cleaned.isEmpty) continue;
      if (cleaned.startsWith('#')) continue;
      return cleaned;
    }
    return '';
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final DiaryController controller;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Settings')),
      child: SafeArea(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return ListView(
              children: [
                CupertinoListSection.insetGrouped(
                  header: const Text('Appearance'),
                  children: [
                    PlainCupertinoListTile(
                      title: const Text('Dark Mode'),
                      trailing: CupertinoSwitch(
                        value: controller.darkMode,
                        onChanged: (value) {
                          controller.setDarkMode(value);
                        },
                      ),
                    ),
                  ],
                ),
                CupertinoListSection.insetGrouped(
                  header: const Text('Storage'),
                  footer: Text(
                    [
                      controller.hasFileAccessPermission
                          ? 'File access: granted'
                          : 'File access: not granted (needed for .md files in external folders)',
                      controller.diaryFolderPath == null
                          ? 'No folder selected. Pick an Android folder to store markdown files.'
                          : controller.diaryFolderPath!,
                    ].join('\n'),
                  ),
                  children: [
                    PlainCupertinoListTile(
                      title: const Text('Grant Full File Access'),
                      trailing: Icon(
                        controller.hasFileAccessPermission
                            ? CupertinoIcons.check_mark_circled_solid
                            : CupertinoIcons.lock,
                      ),
                      onTap: controller.requestFullFileAccess,
                    ),
                    PlainCupertinoListTile(
                      title: const Text('Open App Settings'),
                      trailing: const Icon(CupertinoIcons.gear),
                      onTap: controller.openSystemAppSettings,
                    ),
                    PlainCupertinoListTile(
                      title: const Text('Choose Diary Folder'),
                      trailing: const Icon(CupertinoIcons.folder),
                      onTap: controller.chooseDiaryFolder,
                    ),
                    PlainCupertinoListTile(
                      title: const Text('Refresh Entries'),
                      trailing: const Icon(CupertinoIcons.refresh),
                      onTap: controller.refreshEntries,
                    ),
                  ],
                ),
                if (controller.lastError != null)
                  CupertinoListSection.insetGrouped(
                    header: const Text('Last Error'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          controller.lastError!,
                          style: TextStyle(
                            color: CupertinoColors.systemRed.resolveFrom(context),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class EntryEditorScreen extends StatefulWidget {
  const EntryEditorScreen({
    super.key,
    required this.controller,
    required this.initialEntry,
  });

  final DiaryController controller;
  final DiaryEntryFile initialEntry;

  @override
  State<EntryEditorScreen> createState() => _EntryEditorScreenState();
}

class _EntryEditorScreenState extends State<EntryEditorScreen> {
  late final TextEditingController _textController;
  late MarkdownFrontmatterResult _parsed;
  bool _saving = false;
  int _editorMode = 0; // 0 = write, 1 = preview

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialEntry.rawContent);
    _parsed = MarkdownFrontmatter.parse(_textController.text);
    _textController.addListener(_onChanged);
  }

  void _onChanged() {
    setState(() {
      _parsed = MarkdownFrontmatter.parse(_textController.text);
    });
  }

  @override
  void dispose() {
    _textController.removeListener(_onChanged);
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.initialEntry.fileName),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _saving ? null : _saveAndClose,
              child: _saving
                  ? const CupertinoActivityIndicator()
                  : const Text('Save'),
            ),
            CupertinoButton(
              padding: const EdgeInsets.only(left: 8),
              onPressed: _saving ? null : () => _showMoreMenu(context),
              child: const Icon(CupertinoIcons.ellipsis_circle),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            if (_parsed.frontmatter.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                color: CupertinoColors.systemGrey6.resolveFrom(context),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _parsed.frontmatter.entries
                      .map(
                        (e) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemGrey5.resolveFrom(context),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${e.key}: ${e.value}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoSlidingSegmentedControl<int>(
                      groupValue: _editorMode,
                      onValueChanged: (value) {
                        if (value == null) return;
                        setState(() => _editorMode = value);
                      },
                      children: const {
                        0: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Text('Write'),
                        ),
                        1: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Text('Preview'),
                        ),
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (_editorMode == 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: _EditorToolbar(
                  onInsertHeading: () => _prefixLine('# '),
                  onBold: () => _wrapSelection('**', '**'),
                  onItalic: () => _wrapSelection('_', '_'),
                  onBullet: () => _prefixLine('- '),
                  onCheckbox: () => _prefixLine('- [ ] '),
                  onCode: () => _wrapSelection('`', '`'),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: CupertinoColors.secondarySystemBackground.resolveFrom(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: CupertinoColors.separator.resolveFrom(context),
                    ),
                  ),
                  child: _editorMode == 0
                      ? CupertinoTextField(
                          controller: _textController,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          padding: const EdgeInsets.all(12),
                          placeholder: 'Markdown entry...',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 15,
                            height: 1.4,
                          ),
                          decoration: null,
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: DefaultTextStyle(
                            style: CupertinoTheme.of(context).textTheme.textStyle,
                            child: MarkdownBody(
                              data: _textController.text,
                              selectable: true,
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAndClose() async {
    setState(() => _saving = true);
    try {
      await widget.controller.saveEntry(
        widget.initialEntry.path,
        _textController.text,
      );
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        await _showInfo(context, 'Save failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _showMoreMenu(BuildContext context) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop('delete'),
            child: const Text('Delete Entry'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );

    if (action == 'delete') {
      final confirmed = await _confirmDelete(context);
      if (confirmed != true || !context.mounted) return;
      await widget.controller.deleteEntry(widget.initialEntry.path);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _wrapSelection(String prefix, String suffix) {
    final value = _textController.value;
    final selection = value.selection;
    if (!selection.isValid) return;
    final start = selection.start;
    final end = selection.end;
    if (start < 0 || end < 0) return;
    final text = value.text;
    final selected = text.substring(start, end);
    final replacement = '$prefix$selected$suffix';
    final updated = text.replaceRange(start, end, replacement);
    _textController.value = value.copyWith(
      text: updated,
      selection: TextSelection.collapsed(offset: start + replacement.length),
      composing: TextRange.empty,
    );
  }

  void _prefixLine(String prefix) {
    final value = _textController.value;
    final selection = value.selection;
    if (!selection.isValid) return;
    final text = value.text;
    final cursor = selection.start;
    if (cursor < 0) return;
    final lineStart = text.lastIndexOf('\n', cursor - 1);
    final insertAt = lineStart == -1 ? 0 : lineStart + 1;
    final updated = text.replaceRange(insertAt, insertAt, prefix);
    final movedBy = prefix.length;
    _textController.value = value.copyWith(
      text: updated,
      selection: TextSelection(
        baseOffset: selection.baseOffset + movedBy,
        extentOffset: selection.extentOffset + movedBy,
      ),
      composing: TextRange.empty,
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Delete entry?'),
        content: Text(widget.initialEntry.fileName),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.onInsertHeading,
    required this.onBold,
    required this.onItalic,
    required this.onBullet,
    required this.onCheckbox,
    required this.onCode,
  });

  final VoidCallback onInsertHeading;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onBullet;
  final VoidCallback onCheckbox;
  final VoidCallback onCode;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _ToolbarChip(label: 'H1', onTap: onInsertHeading),
          _ToolbarChip(label: 'B', onTap: onBold),
          _ToolbarChip(label: 'I', onTap: onItalic),
          _ToolbarChip(label: '• List', onTap: onBullet),
          _ToolbarChip(label: '☑', onTap: onCheckbox),
          _ToolbarChip(label: '</>', onTap: onCode),
        ],
      ),
    );
  }
}

class _ToolbarChip extends StatelessWidget {
  const _ToolbarChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: CupertinoButton(
        minSize: 0,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
        borderRadius: BorderRadius.circular(999),
        onPressed: onTap,
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class DiaryEntryFile {
  const DiaryEntryFile({
    required this.path,
    required this.fileName,
    required this.rawContent,
    required this.bodyMarkdown,
    required this.frontmatter,
    required this.modifiedAt,
  });

  final String path;
  final String fileName;
  final String rawContent;
  final String bodyMarkdown;
  final Map<String, Object?> frontmatter;
  final DateTime modifiedAt;
}

class MarkdownFrontmatter {
  static MarkdownFrontmatterResult parse(String raw) {
    final normalized = raw.replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---\n')) {
      return MarkdownFrontmatterResult(frontmatter: const {}, body: raw);
    }

    final end = normalized.indexOf('\n---\n', 4);
    if (end == -1) {
      return MarkdownFrontmatterResult(frontmatter: const {}, body: raw);
    }

    final yamlPart = normalized.substring(4, end);
    final body = normalized.substring(end + 5);
    try {
      final doc = loadYaml(yamlPart);
      if (doc is YamlMap) {
        return MarkdownFrontmatterResult(
          frontmatter: _yamlToMap(doc),
          body: body,
        );
      }
    } catch (_) {
      // Invalid frontmatter should not block editing; surface as raw markdown body.
    }
    return MarkdownFrontmatterResult(frontmatter: const {}, body: body);
  }

  static Map<String, Object?> _yamlToMap(YamlMap yaml) {
    final result = <String, Object?>{};
    yaml.nodes.forEach((keyNode, valueNode) {
      result[keyNode.toString()] = _normalizeYamlValue(valueNode.value);
    });
    return result;
  }

  static Object? _normalizeYamlValue(Object? value) {
    if (value is YamlMap) {
      final map = <String, Object?>{};
      value.nodes.forEach((k, v) {
        map[k.toString()] = _normalizeYamlValue(v.value);
      });
      return map;
    }
    if (value is YamlList) {
      return value.nodes.map((e) => _normalizeYamlValue(e.value)).toList();
    }
    return value;
  }
}

class MarkdownFrontmatterResult {
  const MarkdownFrontmatterResult({
    required this.frontmatter,
    required this.body,
  });

  final Map<String, Object?> frontmatter;
  final String body;
}

class PlainCupertinoListTile extends StatelessWidget {
  const PlainCupertinoListTile({
    super.key,
    required this.title,
    this.trailing,
    this.onTap,
  });

  final Widget title;
  final Widget? trailing;
  final FutureOr<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null ? null : () => onTap!.call(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(child: title),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

class _FolderBanner extends StatelessWidget {
  const _FolderBanner({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: CupertinoColors.separator.resolveFrom(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Diary Folder',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              path,
              style: TextStyle(
                fontSize: 12,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Text(
            title,
            style: CupertinoTheme.of(context).textTheme.navLargeTitleTextStyle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

Future<void> _showInfo(BuildContext context, String message) {
  return showCupertinoDialog<void>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: const Text('Diary'),
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

extension _FirstOrNullExtension<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
