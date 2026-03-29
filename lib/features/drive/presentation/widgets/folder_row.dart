import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/drive_providers.dart';

class FolderRow extends ConsumerWidget {
  final String? parentFolderId;
  final void Function(FolderItem folder) onFolderTap;

  const FolderRow({
    super.key,
    this.parentFolderId,
    required this.onFolderTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(foldersProvider(parentFolderId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Folders',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  )),
              TextButton.icon(
                onPressed: () =>
                    _showCreateFolderDialog(context, ref, parentFolderId),
                icon: const Icon(Icons.add_rounded,
                    size: 16, color: AppTheme.primary),
                label: const Text('New',
                    style:
                        TextStyle(color: AppTheme.primary, fontSize: 13)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        foldersAsync.when(
          data: (folders) {
            if (folders.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.folder_open_rounded,
                          color: AppTheme.textSecondary, size: 20),
                      SizedBox(width: 12),
                      Text('No folders yet. Create one!',
                          style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 13)),
                    ],
                  ),
                ),
              );
            }
            return SizedBox(
              height: 100,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: folders.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final folder = folders[i];
                  final color = Color(
                    int.parse((folder.colorHex ?? '#4F6FFF')
                        .replaceFirst('#', '0xFF')),
                  );
                  return GestureDetector(
                    onTap: () => onFolderTap(folder),
                    onLongPress: () =>
                        _showFolderOptions(context, ref, folder),
                    child: Container(
                      width: 100,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: color.withOpacity(0.25), width: 1),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder_rounded,
                              color: color, size: 32),
                          const SizedBox(height: 8),
                          Text(
                            folder.name,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: LinearProgressIndicator(
              backgroundColor: AppTheme.bgSurface,
              valueColor: AlwaysStoppedAnimation(AppTheme.primary),
            ),
          ),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  void _showCreateFolderDialog(
      BuildContext context, WidgetRef ref, String? parentId) {
    final controller = TextEditingController();
    String selectedColor = '#4F6FFF';
    final colors = [
      '#4F6FFF', '#00C48C', '#FFB800',
      '#FF4D4D', '#7C3AED', '#DB2777'
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: const Text('New Folder',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Folder name',
                  prefixIcon: Icon(Icons.folder_rounded,
                      color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: colors.map((c) {
                  final color =
                      Color(int.parse(c.replaceFirst('#', '0xFF')));
                  return GestureDetector(
                    onTap: () => setState(() => selectedColor = c),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selectedColor == c
                              ? Colors.white
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  ref.read(folderRepositoryProvider).createFolder(
                        name: controller.text.trim(),
                        parentFolderId: parentId,
                        colorHex: selectedColor,
                      );
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showFolderOptions(
      BuildContext context, WidgetRef ref, FolderItem folder) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
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
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded,
                  color: AppTheme.accent),
              title: const Text('Rename',
                  style: TextStyle(color: AppTheme.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _showRenameFolderDialog(context, ref, folder);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_rounded, color: AppTheme.error),
              title: const Text('Delete Folder',
                  style: TextStyle(color: AppTheme.error)),
              onTap: () {
                ref.read(folderRepositoryProvider).deleteFolder(folder);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameFolderDialog(
      BuildContext context, WidgetRef ref, FolderItem folder) {
    final controller = TextEditingController(text: folder.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Rename Folder',
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(hintText: 'Folder name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                ref.read(folderRepositoryProvider).renameFolder(
                    folder, controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }
}
