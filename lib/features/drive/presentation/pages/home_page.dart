import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/zx_file.dart';
import '../providers/drive_providers.dart';
import '../widgets/storage_card.dart';
import '../widgets/file_grid.dart';
import '../widgets/upload_queue_bar.dart';
import '../widgets/folder_row.dart';
import 'search_page.dart';
import 'starred_page.dart';
import 'trash_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _currentIndex = 0;

  // Folder navigation stack
  // Each entry: (folderId, folderName)
  final List<({String id, String name})> _folderStack = [];

  String? get _currentFolderId =>
      _folderStack.isEmpty ? null : _folderStack.last.id;

  void _openFolder(FolderItem folder) {
    setState(() {
      _folderStack.add((id: folder.uuid, name: folder.name));
    });
    // Clear selection when navigating
    ref.read(selectionProvider.notifier).clear();
  }

  void _popFolder() {
    setState(() {
      _folderStack.removeLast();
    });
    ref.read(selectionProvider.notifier).clear();
  }

  void _popToRoot() {
    setState(() => _folderStack.clear());
    ref.read(selectionProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final uploads = ref.watch(uploadNotifierProvider);
    final selectedUuids = ref.watch(selectionProvider);
    final isSelectionMode = selectedUuids.isNotEmpty;

    return PopScope(
      // Handle back button: exit selection → pop folder → system back
      canPop: !isSelectionMode && _folderStack.isEmpty,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (isSelectionMode) {
          ref.read(selectionProvider.notifier).clear();
        } else if (_folderStack.isNotEmpty) {
          _popFolder();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.bgDark,
        appBar: isSelectionMode
            ? _buildSelectionAppBar(selectedUuids)
            : _buildNormalAppBar(),
        body: Column(
          children: [
            if (uploads.isNotEmpty) const UploadQueueBar(),
            // Breadcrumb bar
            if (_folderStack.isNotEmpty && _currentIndex == 0)
              _buildBreadcrumb(),
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: [
                  _DriveTab(
                    currentFolderId: _currentFolderId,
                    folderStack: _folderStack,
                    onFolderTap: _openFolder,
                  ),
                  const StarredPage(),
                  const TrashPage(),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _buildBottomNav(),
        floatingActionButton:
            _currentIndex == 0 && !isSelectionMode ? _buildFAB() : null,
        // Bulk action bar at bottom when in selection mode
        bottomSheet: isSelectionMode
            ? _buildBulkActionBar(selectedUuids)
            : null,
      ),
    );
  }

  PreferredSizeWidget _buildNormalAppBar() {
    return AppBar(
      backgroundColor: AppTheme.bgDark,
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, AppTheme.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                const Icon(Icons.cloud_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          const Text('ZX Drive',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              )),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search_rounded, color: AppTheme.textPrimary),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SearchPage()),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(Set<String> selectedUuids) {
    return AppBar(
      backgroundColor: AppTheme.bgCard,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded, color: AppTheme.textPrimary),
        onPressed: () => ref.read(selectionProvider.notifier).clear(),
      ),
      title: Text(
        '${selectedUuids.length} selected',
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildBreadcrumb() {
    return Container(
      height: 40,
      color: AppTheme.bgCard,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            GestureDetector(
              onTap: _popToRoot,
              child: const Text('Home',
                  style: TextStyle(
                      color: AppTheme.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
            ..._folderStack.asMap().entries.map((entry) {
              final isLast = entry.key == _folderStack.length - 1;
              return Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.chevron_right_rounded,
                        color: AppTheme.textSecondary, size: 16),
                  ),
                  GestureDetector(
                    onTap: isLast
                        ? null
                        : () {
                            setState(() {
                              _folderStack.removeRange(
                                  entry.key + 1, _folderStack.length);
                            });
                          },
                    child: Text(
                      entry.value.name,
                      style: TextStyle(
                        color: isLast
                            ? AppTheme.textPrimary
                            : AppTheme.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildBulkActionBar(Set<String> selectedUuids) {
    return Container(
      color: AppTheme.bgCard,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _BulkActionButton(
              icon: Icons.download_rounded,
              label: 'Download',
              color: AppTheme.primary,
              onTap: () => _bulkDownload(selectedUuids),
            ),
            _BulkActionButton(
              icon: Icons.drive_file_move_rounded,
              label: 'Move',
              color: AppTheme.accent,
              onTap: () => _showMoveToFolderSheet(selectedUuids),
            ),
            _BulkActionButton(
              icon: Icons.star_rounded,
              label: 'Star',
              color: AppTheme.warning,
              onTap: () => _bulkStar(selectedUuids),
            ),
            _BulkActionButton(
              icon: Icons.delete_rounded,
              label: 'Delete',
              color: AppTheme.error,
              onTap: () => _bulkDelete(selectedUuids),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _bulkDownload(Set<String> uuids) async {
    final repo = ref.read(fileRepositoryProvider);
    final files = await repo.getFilesByUuids(uuids.toList());

    // Check if any file exceeds 20 MB limit
    final oversized =
        files.where((f) => f.sizeBytes > 20 * 1024 * 1024).toList();
    if (oversized.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${oversized.length} file(s) exceed 20 MB and cannot be downloaded via Bot API yet.'),
          backgroundColor: AppTheme.warning,
        ),
      );
    }

    final downloadable =
        files.where((f) => f.sizeBytes <= 20 * 1024 * 1024).toList();
    ref.read(selectionProvider.notifier).clear();

    for (final file in downloadable) {
      try {
        await repo.downloadFile(file: file);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Downloaded: ${file.name}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed: ${file.name}'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      }
    }
  }

  void _showMoveToFolderSheet(Set<String> uuids) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MoveFolderSheet(
        uuids: uuids.toList(),
        onMoved: () => ref.read(selectionProvider.notifier).clear(),
      ),
    );
  }

  Future<void> _bulkStar(Set<String> uuids) async {
    await ref
        .read(fileRepositoryProvider)
        .bulkStar(uuids.toList(), star: true);
    ref.read(selectionProvider.notifier).clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${uuids.length} file(s) starred')),
      );
    }
  }

  Future<void> _bulkDelete(Set<String> uuids) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Files',
            style: TextStyle(
                color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(
          'Move ${uuids.length} file(s) to trash?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref
        .read(fileRepositoryProvider)
        .bulkDelete(uuids.toList());
    ref.read(selectionProvider.notifier).clear();
  }

  Widget _buildBottomNav() {
    const items = [
      BottomNavigationBarItem(
          icon: Icon(Icons.folder_rounded), label: 'Drive'),
      BottomNavigationBarItem(
          icon: Icon(Icons.star_rounded), label: 'Starred'),
      BottomNavigationBarItem(
          icon: Icon(Icons.delete_rounded), label: 'Trash'),
    ];

    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (i) {
        setState(() => _currentIndex = i);
        ref.read(selectionProvider.notifier).clear();
      },
      items: items,
      backgroundColor: AppTheme.bgCard,
      selectedItemColor: AppTheme.primary,
      unselectedItemColor: AppTheme.textSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    );
  }

  Widget _buildFAB() {
    return FloatingActionButton(
      backgroundColor: AppTheme.primary,
      onPressed: _pickAndUpload,
      child: const Icon(Icons.upload_rounded, color: Colors.white),
    );
  }

  Future<void> _pickAndUpload() async {
    final activeUploads = ref
        .read(uploadNotifierProvider)
        .where((t) => t.status == UploadStatus.uploading)
        .length;

    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;

    final remaining =
        AppConstants.maxConcurrentUploads - activeUploads;
    if (result.files.length > remaining) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            remaining <= 0
                ? 'Upload queue is full (${AppConstants.maxConcurrentUploads} max). Wait for current uploads to finish.'
                : 'Only $remaining upload slot(s) free. First ${remaining > 0 ? remaining : 0} file(s) will be queued.',
          ),
          backgroundColor: AppTheme.warning,
        ),
      );
      if (remaining <= 0) return;
    }

    final filesToUpload = result.files.take(remaining).toList();

    for (final pFile in filesToUpload) {
      if (pFile.path == null) continue;
      try {
        await ref.read(uploadNotifierProvider.notifier).addUpload(
              file: File(pFile.path!),
              folderId: _currentFolderId,
            );
      } on UploadLimitException catch (e) {
        if (!mounted) break;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: AppTheme.warning,
          ),
        );
        break;
      }
    }
  }
}

// ── Drive Tab ─────────────────────────────────────────────

class _DriveTab extends ConsumerWidget {
  final String? currentFolderId;
  final List<({String id, String name})> folderStack;
  final void Function(FolderItem folder) onFolderTap;

  const _DriveTab({
    required this.currentFolderId,
    required this.folderStack,
    required this.onFolderTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        // Only show storage card at root
        if (folderStack.isEmpty)
          const SliverToBoxAdapter(child: StorageCard()),
        if (folderStack.isEmpty)
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        SliverToBoxAdapter(
          child: FolderRow(
            parentFolderId: currentFolderId,
            onFolderTap: onFolderTap,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              folderStack.isEmpty
                  ? 'Recent Files'
                  : '${folderStack.last.name}',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(
          child: FileGrid(folderId: currentFolderId),
        ),
        // Bottom padding so FAB doesn't cover last file
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}

// ── Move to Folder Sheet ──────────────────────────────────

class _MoveFolderSheet extends ConsumerWidget {
  final List<String> uuids;
  final VoidCallback onMoved;

  const _MoveFolderSheet({required this.uuids, required this.onMoved});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref.read(folderRepositoryProvider).getAllFolders(),
      builder: (context, snapshot) {
        final folders = snapshot.data ?? [];

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Move to...',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 8),
              // Root option
              ListTile(
                leading: const Icon(Icons.home_rounded,
                    color: AppTheme.primary),
                title: const Text('Home (root)',
                    style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () async {
                  await ref
                      .read(fileRepositoryProvider)
                      .bulkMove(uuids, null);
                  onMoved();
                  if (context.mounted) Navigator.pop(context);
                },
              ),
              if (folders.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No folders created yet',
                      style: TextStyle(color: AppTheme.textSecondary)),
                )
              else
                ...folders.map((folder) {
                  final color = Color(
                    int.parse((folder.colorHex ?? '#4F6FFF')
                        .replaceFirst('#', '0xFF')),
                  );
                  return ListTile(
                    leading:
                        Icon(Icons.folder_rounded, color: color),
                    title: Text(folder.name,
                        style: const TextStyle(
                            color: AppTheme.textPrimary)),
                    onTap: () async {
                      await ref
                          .read(fileRepositoryProvider)
                          .bulkMove(uuids, folder.uuid);
                      onMoved();
                      if (context.mounted) Navigator.pop(context);
                    },
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

// ── Bulk Action Button ────────────────────────────────────

class _BulkActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _BulkActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
