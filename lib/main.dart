import 'dart:async';

import 'package:flutter/cupertino.dart';

import 'diary_controller.dart';
import 'entry_editor_screen.dart';
import 'models.dart';
import 'ui_widgets.dart';

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
    if (mounted) setState(() => _loaded = true);
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
              await showInfoDialog(context, 'Choose a diary folder first in Settings.');
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
              return const EmptyState(
                title: 'No folder selected',
                message: 'Open Settings and choose a folder to store .md diary files.',
              );
            }

            if (controller.entries.isEmpty) {
              return ListView(
                children: [
                  FolderBanner(
                    label: 'Diary Folder',
                    path: controller.diaryFolderPath!,
                  ),
                  const SizedBox(height: 16),
                  const EmptyState(
                    title: 'No diary entries',
                    message: 'Tap + to create your first markdown note.',
                  ),
                ],
              );
            }

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: FolderBanner(
                    label: 'Diary Folder',
                    path: controller.diaryFolderPath!,
                  ),
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
                              .take(4)
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
                                style: CupertinoTheme.of(context)
                                    .textTheme
                                    .textStyle
                                    .copyWith(
                                      fontSize: 12,
                                      color: CupertinoColors.secondaryLabel.resolveFrom(
                                        context,
                                      ),
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (preview.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  preview,
                                  style: CupertinoTheme.of(context)
                                      .textTheme
                                      .textStyle
                                      .copyWith(
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
    for (final line in entry.bodyMarkdown.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#')) {
        return trimmed.replaceFirst(RegExp(r'^#+\s*'), '');
      }
      if (trimmed.isNotEmpty) return trimmed;
    }
    return entry.fileName;
  }

  String _previewLine(String markdown) {
    for (final line in markdown.split('\n')) {
      final cleaned = line.trim();
      if (cleaned.isEmpty || cleaned.startsWith('#')) continue;
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
                        onChanged: (value) => controller.setDarkMode(value),
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
                          ? 'Diary folder: not selected'
                          : 'Diary folder: ${controller.diaryFolderPath!}',
                      'Media folder: ${controller.mediaFolderPath ?? '(same as diary folder)'}',
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
                      title: const Text('Choose Media Folder'),
                      trailing: const Icon(CupertinoIcons.photo),
                      onTap: controller.chooseMediaFolder,
                    ),
                    PlainCupertinoListTile(
                      title: const Text('Use Diary Folder for Media'),
                      trailing: const Icon(CupertinoIcons.refresh),
                      onTap: controller.clearMediaFolder,
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
