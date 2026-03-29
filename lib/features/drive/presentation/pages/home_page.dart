import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../../../../core/theme/app_theme.dart';
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
  String? _currentFolderId;
  final List<String> _folderStack = [];
  final List<String> _folderNameStack = [];

  final _pages = const [_DriveTab(), StarredPage(), TrashPage()];

  @override
  Widget build(BuildContext context) {
    final uploads = ref.watch(uploadNotifierProvider);
    final hasUploads = uploads.isNotEmpty;

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          if (hasUploads) const UploadQueueBar(),
          Expanded(child: _pages[_currentIndex]),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton: _currentIndex == 0 ? _buildFAB() : null,
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.bgDark,
      title: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, AppTheme.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.cloud_rounded, color: Colors.white, size: 18),
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

  Widget _buildBottomNav() {
    const items = [
      BottomNavigationBarItem(icon: Icon(Icons.folder_rounded), label: 'Drive'),
      BottomNavigationBarItem(icon: Icon(Icons.star_rounded), label: 'Starred'),
      BottomNavigationBarItem(icon: Icon(Icons.delete_rounded), label: 'Trash'),
    ];

    return BottomNavigationBar(
      currentIndex: _currentIndex,
      onTap: (i) => setState(() => _currentIndex = i),
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
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;

    for (final pFile in result.files) {
      if (pFile.path == null) continue;
      ref.read(uploadNotifierProvider.notifier).addUpload(
            file: File(pFile.path!),
            folderId: _currentFolderId,
          );
    }
  }
}

class _DriveTab extends ConsumerWidget {
  const _DriveTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: 16)),
        SliverToBoxAdapter(child: StorageCard()),
        SliverToBoxAdapter(child: SizedBox(height: 24)),
        SliverToBoxAdapter(child: FolderRow()),
        SliverToBoxAdapter(child: SizedBox(height: 24)),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text('Recent Files',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                )),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(child: FileGrid()),
      ],
    );
  }
}
