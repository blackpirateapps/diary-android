import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as p;

import 'diary_controller.dart';
import 'models.dart';
import 'ui_widgets.dart';

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
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final Map<String, Object?> _frontmatterDraft;
  bool _saving = false;
  bool _previewMode = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    final parsed = MarkdownFrontmatter.parse(widget.initialEntry.rawContent);
    _frontmatterDraft = Map<String, Object?>.from(parsed.frontmatter);
    _titleController = TextEditingController(
      text: (_frontmatterDraft['title']?.toString().trim().isNotEmpty ?? false)
          ? _frontmatterDraft['title']!.toString()
          : _fallbackTitle(widget.initialEntry, parsed.body),
    );
    _bodyController = TextEditingController(text: parsed.body);
    _titleController.addListener(_onChanged);
    _bodyController.addListener(_onChanged);
  }

  @override
  void dispose() {
    _titleController.removeListener(_onChanged);
    _bodyController.removeListener(_onChanged);
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
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
              onPressed: _saving ? null : _showMoreMenu,
              child: const Icon(CupertinoIcons.ellipsis_circle),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: CupertinoTextField(
                controller: _titleController,
                placeholder: 'Title',
                style: CupertinoTheme.of(context)
                    .textTheme
                    .navLargeTitleTextStyle
                    .copyWith(fontSize: 20),
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                decoration: null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _InlinePillButton(
                        icon: CupertinoIcons.location_solid,
                        label: 'Add Place',
                        onTap: _addManualLocation,
                      ),
                      const SizedBox(width: 8),
                      _InlinePillButton(
                        icon: CupertinoIcons.location,
                        label: _locating ? 'Locating...' : 'Current Location',
                        onTap: _locating ? null : _useCurrentLocation,
                      ),
                      if (_locationLabel != null) ...[
                        const Spacer(),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          onPressed: _clearLocation,
                          child: const Icon(CupertinoIcons.clear_circled_solid, size: 18),
                        ),
                      ],
                    ],
                  ),
                  if (_locationLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _locationLabel!,
                        style: TextStyle(
                          fontSize: 14,
                          color: CupertinoColors.secondaryLabel.resolveFrom(context),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_imageNames.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: _ImageGallery(
                  imageNames: _imageNames,
                  resolveImagePath: _resolveMediaImagePath,
                  onRemove: _removeImageName,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: _EditorToolbar(
                onInsertHeading: () => _prefixLine('# '),
                onBold: () => _wrapSelection('**', '**'),
                onItalic: () => _wrapSelection('_', '_'),
                onBullet: () => _prefixLine('- '),
                onCheckbox: () => _prefixLine('- [ ] '),
                onCode: () => _wrapSelection('`', '`'),
                previewEnabled: _previewMode,
                onTogglePreview: () => setState(() => _previewMode = !_previewMode),
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
                  child: !_previewMode
                      ? CupertinoTextField(
                          controller: _bodyController,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          padding: const EdgeInsets.all(12),
                          placeholder: 'Start writing...',
                          style: TextStyle(
                            fontSize: 17,
                            height: 1.35,
                            color: CupertinoColors.label.resolveFrom(context),
                          ),
                          decoration: null,
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: DefaultTextStyle(
                            style: CupertinoTheme.of(context).textTheme.textStyle,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_titleController.text.trim().isNotEmpty) ...[
                                  Text(
                                    _titleController.text.trim(),
                                    style: CupertinoTheme.of(context)
                                        .textTheme
                                        .navLargeTitleTextStyle
                                        .copyWith(fontSize: 22),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                if (_locationLabel != null) ...[
                                  Row(
                                    children: [
                                      Icon(
                                        CupertinoIcons.location_solid,
                                        size: 14,
                                        color: CupertinoColors.secondaryLabel.resolveFrom(
                                          context,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _locationLabel!,
                                          style: TextStyle(
                                            color: CupertinoColors.secondaryLabel.resolveFrom(
                                              context,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                if (_imageNames.isNotEmpty) ...[
                                  _ReadOnlyImageGallery(
                                    imageNames: _imageNames,
                                    resolveImagePath: _resolveMediaImagePath,
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                MarkdownBody(
                                  data: _bodyController.text,
                                  selectable: true,
                                ),
                              ],
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

  List<String> get _imageNames {
    final raw = _frontmatterDraft['images'];
    if (raw is List) {
      return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }

  String? get _locationLabel {
    final value = _frontmatterDraft['location']?.toString().trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  String? _resolveMediaImagePath(String imageName) {
    final mediaDir = widget.controller.effectiveMediaFolderPath;
    if (mediaDir == null || mediaDir.isEmpty) return null;
    return p.join(mediaDir, imageName);
  }

  Future<void> _saveAndClose() async {
    setState(() => _saving = true);
    try {
      await widget.controller.saveEntry(widget.initialEntry.path, _buildRawContent());
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      await showInfoDialog(context, 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showMoreMenu() async {
    if (!mounted) return;
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop('add_images'),
            child: const Text('Add Images'),
          ),
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

    if (action == 'add_images') {
      await _addImages();
      return;
    }
    if (action == 'delete') {
      if (!mounted) return;
      final confirmed = await _confirmDelete();
      if (confirmed != true || !mounted) return;
      await widget.controller.deleteEntry(widget.initialEntry.path);
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  Future<void> _addImages() async {
    final mediaDir = widget.controller.effectiveMediaFolderPath;
    if (mediaDir == null || mediaDir.isEmpty) {
      await showInfoDialog(
        context,
        'Set a media location in Settings first (or choose a diary folder).',
      );
      return;
    }

    final allowed = await widget.controller.ensureStorageAccess(interactive: true);
    if (!allowed) {
      if (!mounted) return;
      await showInfoDialog(context, 'File access permission is required to add images.');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final targetDir = Directory(mediaDir);
    await targetDir.create(recursive: true);

    final current = [..._imageNames];
    final added = <String>[];
    for (final file in result.files) {
      final originalName = p.basename(file.name);
      final outputName = await _uniqueMediaName(targetDir.path, originalName);
      final outputPath = p.join(targetDir.path, outputName);

      if (file.path != null && file.path!.isNotEmpty) {
        await File(file.path!).copy(outputPath);
        added.add(outputName);
      } else if (file.bytes != null) {
        await File(outputPath).writeAsBytes(file.bytes!, flush: true);
        added.add(outputName);
      }
    }

    if (!mounted) return;
    if (added.isEmpty) {
      await showInfoDialog(context, 'No images could be imported from the selected files.');
      return;
    }

    setState(() {
      _frontmatterDraft['images'] = [...current, ...added];
    });
  }

  Future<String> _uniqueMediaName(String folderPath, String originalName) async {
    final base = p.basenameWithoutExtension(originalName);
    final ext = p.extension(originalName);
    var candidate = originalName;
    var i = 1;
    while (await File(p.join(folderPath, candidate)).exists()) {
      candidate = '${base}_$i$ext';
      i++;
    }
    return candidate;
  }

  void _removeImageName(String imageName) {
    setState(() {
      _frontmatterDraft['images'] =
          _imageNames.where((element) => element != imageName).toList();
    });
  }

  void _wrapSelection(String prefix, String suffix) {
    final value = _bodyController.value;
    final selection = value.selection;
    if (!selection.isValid) return;
    final start = selection.start;
    final end = selection.end;
    if (start < 0 || end < 0) return;
    final selected = value.text.substring(start, end);
    final replacement = '$prefix$selected$suffix';
    final updated = value.text.replaceRange(start, end, replacement);
    _bodyController.value = value.copyWith(
      text: updated,
      selection: TextSelection.collapsed(offset: start + replacement.length),
      composing: TextRange.empty,
    );
  }

  void _prefixLine(String prefix) {
    final value = _bodyController.value;
    final selection = value.selection;
    if (!selection.isValid) return;
    final cursor = selection.start;
    if (cursor < 0) return;
    final lineStart = value.text.lastIndexOf('\n', cursor - 1);
    final insertAt = lineStart == -1 ? 0 : lineStart + 1;
    final updated = value.text.replaceRange(insertAt, insertAt, prefix);
    final movedBy = prefix.length;
    _bodyController.value = value.copyWith(
      text: updated,
      selection: TextSelection(
        baseOffset: selection.baseOffset + movedBy,
        extentOffset: selection.extentOffset + movedBy,
      ),
      composing: TextRange.empty,
    );
  }

  Future<bool?> _confirmDelete() {
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

  void _clearLocation() {
    setState(() {
      _frontmatterDraft.remove('location');
      _frontmatterDraft.remove('latitude');
      _frontmatterDraft.remove('longitude');
    });
  }

  Future<void> _addManualLocation() async {
    final controller = TextEditingController(text: _locationLabel ?? '');
    final value = await showCupertinoDialog<String>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Add Place'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            placeholder: 'Place name',
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (!mounted || value == null) return;
    final trimmed = value.trim();
    setState(() {
      if (trimmed.isEmpty) {
        _frontmatterDraft.remove('location');
      } else {
        _frontmatterDraft['location'] = trimmed;
      }
    });
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        await showInfoDialog(context, 'Location services are off. Enable GPS/location first.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        await showInfoDialog(
          context,
          'Location permission is required to fetch current location.',
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      String label =
          '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final pm = placemarks.first;
          final parts = [
            pm.subLocality,
            pm.locality,
            pm.administrativeArea,
            pm.country,
          ]
              .whereType<String>()
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
          if (parts.isNotEmpty) {
            label = parts.toSet().join(', ');
          }
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _frontmatterDraft['location'] = label;
        _frontmatterDraft['latitude'] = position.latitude;
        _frontmatterDraft['longitude'] = position.longitude;
      });
    } catch (e) {
      if (!mounted) return;
      await showInfoDialog(context, 'Could not get current location: $e');
    } finally {
      if (mounted) {
        setState(() => _locating = false);
      }
    }
  }

  String _buildRawContent() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _frontmatterDraft.remove('title');
    } else {
      _frontmatterDraft['title'] = title;
    }
    _frontmatterDraft['images'] = _imageNames;
    return MarkdownFrontmatter.compose(
      frontmatter: _frontmatterDraft,
      body: _bodyController.text,
    );
  }

  String _fallbackTitle(DiaryEntryFile entry, String body) {
    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#')) {
        return trimmed.replaceFirst(RegExp(r'^#+\s*'), '');
      }
      if (trimmed.isNotEmpty) return trimmed;
    }
    return entry.fileName;
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
    required this.previewEnabled,
    required this.onTogglePreview,
  });

  final VoidCallback onInsertHeading;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onBullet;
  final VoidCallback onCheckbox;
  final VoidCallback onCode;
  final bool previewEnabled;
  final VoidCallback onTogglePreview;

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
          _ToolbarChip(label: 'Preview', onTap: onTogglePreview, selected: previewEnabled),
        ],
      ),
    );
  }
}

class _ToolbarChip extends StatelessWidget {
  const _ToolbarChip({
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: CupertinoButton(
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        color: selected
            ? CupertinoColors.systemBlue.withValues(alpha: 0.14)
            : CupertinoColors.tertiarySystemFill.resolveFrom(context),
        borderRadius: BorderRadius.circular(999),
        onPressed: onTap,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected
                ? CupertinoColors.systemBlue.resolveFrom(context)
                : CupertinoColors.label.resolveFrom(context),
          ),
        ),
      ),
    );
  }
}

class _InlinePillButton extends StatelessWidget {
  const _InlinePillButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minimumSize: Size.zero,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
      borderRadius: BorderRadius.circular(10),
      onPressed: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: CupertinoColors.secondaryLabel.resolveFrom(context)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

class _ImageGallery extends StatelessWidget {
  const _ImageGallery({
    required this.imageNames,
    required this.resolveImagePath,
    required this.onRemove,
  });

  final List<String> imageNames;
  final String? Function(String imageName) resolveImagePath;
  final void Function(String imageName) onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 170,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: imageNames.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final imageName = imageNames[index];
          return _EditableImageCard(
            imageName: imageName,
            path: resolveImagePath(imageName),
            onRemove: () => onRemove(imageName),
          );
        },
      ),
    );
  }
}

class _EditableImageCard extends StatelessWidget {
  const _EditableImageCard({
    required this.imageName,
    required this.path,
    required this.onRemove,
  });

  final String imageName;
  final String? path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CupertinoColors.separator.resolveFrom(context)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: _ImagePreview(path: path),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: CupertinoButton(
              minimumSize: Size.zero,
              padding: EdgeInsets.zero,
              onPressed: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: CupertinoColors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.clear_circled_solid,
                  color: CupertinoColors.white,
                  size: 20,
                ),
              ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: CupertinoColors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                imageName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: CupertinoColors.white, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyImageGallery extends StatelessWidget {
  const _ReadOnlyImageGallery({
    required this.imageNames,
    required this.resolveImagePath,
  });

  final List<String> imageNames;
  final String? Function(String imageName) resolveImagePath;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: imageNames.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final imageName = imageNames[index];
          return Container(
            width: 180,
            decoration: BoxDecoration(
              color: CupertinoColors.secondarySystemBackground.resolveFrom(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: CupertinoColors.separator.resolveFrom(context)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: _ImagePreview(path: resolveImagePath(imageName)),
            ),
          );
        },
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    if (path == null || path!.isEmpty) {
      return _placeholder(context);
    }
    final file = File(path!);
    return FutureBuilder<bool>(
      future: file.exists(),
      builder: (context, snapshot) {
        if (snapshot.data == true) {
          return Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder(context),
          );
        }
        return _placeholder(context);
      },
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
      child: Center(
        child: Icon(
          CupertinoIcons.photo,
          size: 30,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }
}
