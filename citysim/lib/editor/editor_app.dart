import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'content_api.dart';
import 'pages/ambience_page.dart';
import 'pages/map_page.dart';
import 'pages/catalogue_page.dart';
import 'pages/economy_page.dart';
import 'pages/overview_page.dart';
import 'pages/sprites_page.dart';

/// The content editor dashboard shell: sidebar navigation over the
/// category editors, a shared save/validate bar, and unsaved-change
/// tracking with simple diffs.
class ContentEditorApp extends StatelessWidget {
  const ContentEditorApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Citysim Content Editor',
    theme: ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF276B58),
        surface: const Color(0xFFFCFBF6),
      ),
      scaffoldBackgroundColor: const Color(0xFFF4F3EA),
    ),
    home: const EditorShell(),
  );
}

class EditorShell extends StatefulWidget {
  const EditorShell({super.key});

  @override
  State<EditorShell> createState() => _EditorShellState();
}

class _EditorShellState extends State<EditorShell> {
  final ContentApi _api = ContentApi();

  /// Live editable category maps, keyed by file name.
  Map<String, Object?> _categories = {};
  Map<String, Object?> _saved = {};
  bool _loading = true;
  String? _error;
  bool _dirty = false;
  bool _saving = false;
  List<String> _issues = [];
  String _issuesStatus = '';

  int _pageIndex = 0;

  /// The sprite role to focus when the sprites page opens (set by
  /// clicking a catalogue variant); cleared on manual tab switches.
  String? _focusSpriteRole;

  /// Bumped whenever a page's data is reverted so the page subtree remounts
  /// and its uncontrolled text fields re-read the restored values.
  int _rebuildToken = 0;

  /// The category file each page edits; null for read-only pages.
  static const _pageCategories = <String?>[
    null,
    'terrain.json',
    'catalogue.json',
    'sprites.json',
    'economy.json',
    'ambience.json',
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final categories = await _api.loadContent();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _saved = _deepCopy(categories);
        _loading = false;
        _dirty = false;
        _issues = [];
        _issuesStatus = '';
      });
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showStartWarning());
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  /// The game loads its content once at startup; saving content while
  /// it runs can corrupt its save. Interim protection until proper
  /// session locking lands: warn when the dashboard starts.
  Future<void> _showStartWarning() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Before you edit'),
        content: const Text(
          'Make sure the game is not running anywhere. The game loads its '
          'content once at startup — saving content while it runs can '
          'corrupt its save. Stop the game first, edit, then relaunch it '
          'with dart run tool/run_game.dart.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  void _mutate(void Function(Map<String, Object?> categories) edit) {
    setState(() {
      edit(_categories);
      _dirty = !_deepEquals(_categories, _saved);
    });
  }

  Future<void> _validate() async {
    setState(() => _issuesStatus = 'Validating…');
    try {
      final result = await _api.validate(_categories);
      if (!mounted) return;
      setState(() {
        _issues = (result['issues'] as List?)?.cast<String>() ?? const [];
        _issuesStatus = _issues.isEmpty
            ? 'Content is valid.'
            : '${_issues.length} issue(s).';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _issuesStatus = 'Validation failed: $error');
    }
  }

  /// Saves the current categories. Returns whether the save succeeded —
  /// the tab-switch guard stays on the page when it fails so the user can
  /// see the rejected issues.
  Future<bool> _save() async {
    setState(() => _saving = true);
    try {
      await _api.save(_categories);
      if (!mounted) return false;
      setState(() {
        _saved = _deepCopy(_categories);
        _dirty = false;
        _issues = [];
        _issuesStatus = 'Saved. Hot-restart the game to see changes.';
      });
      return true;
    } on ContentApiException catch (error) {
      if (!mounted) return false;
      setState(() {
        _issues = error.issues;
        _issuesStatus = 'Save rejected: ${error.message}';
      });
      return false;
    } catch (error) {
      if (!mounted) return false;
      setState(() => _issuesStatus = 'Save failed: $error');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<String> _diffSummary() {
    if (!_dirty) return const [];
    final changes = <String>[];
    for (final entry in _categories.entries) {
      final before = _saved[entry.key];
      final after = entry.value;
      if (!_deepEquals(before, after)) {
        changes.add(entry.key);
      }
    }
    return changes;
  }

  bool _pageDirty(int index) {
    final file = _pageCategories[index];
    if (file == null) return false;
    return !_deepEquals(_categories[file], _saved[file]);
  }

  /// Reverts the current page's category to the last saved values. The
  /// rebuild token forces the page's form fields to remount so the
  /// restored values are actually displayed.
  void _revertPage() {
    final file = _pageCategories[_pageIndex];
    if (file == null || !_pageDirty(_pageIndex)) return;
    setState(() {
      _categories[file] = _deepCopy(_saved[file] as Map<String, Object?>);
      _rebuildToken++;
      _dirty = !_deepEquals(_categories, _saved);
      _issues = [];
      _issuesStatus = '';
    });
  }

  /// Jumps to the sprite editor for [role] (from a catalogue variant
  /// click). Edits made so far are preserved — only manual tab switches
  /// go through the unsaved-changes guard.
  void _openSpriteEditor(String role) {
    setState(() {
      _focusSpriteRole = role;
      _pageIndex = 3;
    });
  }

  /// Switching pages with unsaved changes warns first: save them, discard
  /// them, or stay. Discarding reverts every category to the last saved
  /// values.
  Future<void> _switchPage(int index) async {
    if (index == _pageIndex) return;
    if (_dirty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unsaved changes'),
          content: Text(
            'You have unsaved changes in ${_diffSummary().join(', ')}. '
            'Save them before switching pages — anything not saved will '
            'be discarded.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'stay'),
              child: const Text('Stay'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: const Text('Discard changes'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('Save & continue'),
            ),
          ],
        ),
      );
      if (choice == 'stay' || choice == null) return;
      if (choice == 'save') {
        final saved = await _save();
        if (!saved) return; // Rejected: stay here so the issues are visible.
      } else {
        setState(() {
          _categories = _deepCopy(_saved);
          _rebuildToken++;
          _dirty = false;
          _issues = [];
          _issuesStatus = 'Unsaved changes were discarded.';
        });
      }
    }
    setState(() {
      _focusSpriteRole = null;
      _pageIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 42),
                const SizedBox(height: 10),
                const Text('Could not reach the editor server.'),
                Text('$_error', textAlign: TextAlign.center),
                const SizedBox(height: 6),
                const Text(
                  'Start it with: dart run tool/content_editor/server.dart',
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    final pages = [
      ('Overview', OverviewPage(categories: _categories)),
      (
        'Map',
        MapPage(
          key: ValueKey('map-$_rebuildToken'),
          categories: _categories,
          onChanged: _mutate,
        ),
      ),
      (
        'Catalogue',
        CataloguePage(
          key: ValueKey('catalogue-$_rebuildToken'),
          categories: _categories,
          onChanged: _mutate,
          onOpenSprite: _openSpriteEditor,
        ),
      ),
      (
        'Sprites',
        SpritesPage(
          key: ValueKey('sprites-$_rebuildToken'),
          categories: _categories,
          onChanged: _mutate,
          focusRole: _focusSpriteRole,
        ),
      ),
      (
        'Economy',
        EconomyPage(
          key: ValueKey('economy-$_rebuildToken'),
          categories: _categories,
          onChanged: _mutate,
        ),
      ),
      (
        'Ambience',
        AmbiencePage(
          key: ValueKey('ambience-$_rebuildToken'),
          categories: _categories,
          onChanged: _mutate,
        ),
      ),
    ];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _pageIndex,
            onDestinationSelected: _switchPage,
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard_rounded),
                label: Text('Overview'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.map_outlined),
                selectedIcon: Icon(Icons.map_rounded),
                label: Text('Map'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.home_work_outlined),
                selectedIcon: Icon(Icons.home_work_rounded),
                label: Text('Catalogue'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.image_outlined),
                selectedIcon: Icon(Icons.image_rounded),
                label: Text('Sprites'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.toll_outlined),
                selectedIcon: Icon(Icons.toll_rounded),
                label: Text('Economy'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.air_outlined),
                selectedIcon: Icon(Icons.air_rounded),
                label: Text('Ambience'),
              ),
            ],
          ),
          Expanded(
            child: Column(
              children: [
                _toolbar(),
                Divider(height: 1, color: Colors.green.shade100),
                if (_issues.isNotEmpty)
                  Container(
                    width: double.infinity,
                    color: Colors.orange.shade50,
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final issue in _issues.take(8))
                          Text(
                            issue,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF7A5300),
                            ),
                          ),
                      ],
                    ),
                  ),
                Expanded(child: pages[_pageIndex].$2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Row(
      children: [
        Text('Content Editor', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(width: 8),
        if (_dirty)
          Chip(
            avatar: const Icon(Icons.edit_note_rounded, size: 18),
            label: Text('unsaved: ${_diffSummary().join(', ')}'),
            visualDensity: VisualDensity.compact,
            backgroundColor: Colors.amber.shade100,
          )
        else
          const Chip(
            avatar: Icon(Icons.check_rounded, size: 18),
            label: Text('no pending changes'),
            visualDensity: VisualDensity.compact,
          ),
        const Spacer(),
        if (_issuesStatus.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              _issuesStatus,
              style: TextStyle(
                fontSize: 12,
                color: _issues.isEmpty && _issuesStatus.startsWith('Saved')
                    ? Colors.green.shade700
                    : Colors.orange.shade900,
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _pageDirty(_pageIndex) ? _revertPage : null,
          icon: const Icon(Icons.undo_rounded),
          label: const Text('Cancel page changes'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _validate,
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Validate'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _saving || !_dirty ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_rounded),
          label: const Text('Save'),
        ),
      ],
    ),
  );
}

Map<String, Object?> _deepCopy(Map<String, Object?> source) =>
    jsonDecode(jsonEncode(source)) as Map<String, Object?>;

bool _deepEquals(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);
