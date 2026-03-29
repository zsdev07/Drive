import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/drive_providers.dart';
import '../widgets/file_card.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Search files...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: AppTheme.textSecondary),
          ),
          onChanged: (v) => ref.read(searchQueryProvider.notifier).state = v,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: results.when(
        data: (files) {
          if (_controller.text.isEmpty) {
            return const Center(
              child: Text('Type to search your files',
                  style: TextStyle(color: AppTheme.textSecondary)),
            );
          }
          if (files.isEmpty) {
            return const Center(
              child: Text('No files found',
                  style: TextStyle(color: AppTheme.textSecondary)),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            itemCount: files.length,
            itemBuilder: (_, i) => FileCard(file: files[i]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
        error: (e, _) => Center(child: Text('$e', style: const TextStyle(color: AppTheme.error))),
      ),
    );
  }
}
