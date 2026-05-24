import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/note.dart';
import '../../models/folder.dart';
import '../../blocs/notes/notes_bloc.dart';

/// 侧边栏组件 - 文件夹和笔记列表
class Sidebar extends StatelessWidget {
  final List<Folder> folders;
  final List<Note> notes;
  final Folder? selectedFolder;
  final Note? selectedNote;
  final void Function(Folder?) onFolderSelected;
  final void Function(Note) onNoteSelected;
  final VoidCallback onCreateNote;
  final VoidCallback onOpenSettings;

  const Sidebar({
    super.key,
    required this.folders,
    required this.notes,
    this.selectedFolder,
    this.selectedNote,
    required this.onFolderSelected,
    required this.onNoteSelected,
    required this.onCreateNote,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Column(
        children: [
          // 标题栏
          _buildHeader(context),
          // 搜索框
          _buildSearchBar(context),
          // 文件夹列表
          _buildFolderList(context),
          const Divider(height: 1),
          // 笔记列表
          Expanded(child: _buildNoteList(context)),
          // 底部操作栏
          _buildBottomBar(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
      ),
      child: Row(
        children: [
          Icon(
            Icons.edit_note,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 8),
          Text(
            'Obsidian Git',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            onPressed: onOpenSettings,
            tooltip: '设置',
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        decoration: InputDecoration(
          hintText: '搜索笔记...',
          prefixIcon: const Icon(Icons.search, size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          isDense: true,
        ),
        onChanged: (query) {
          context.read<NotesBloc>().add(SearchNotes(query));
        },
      ),
    );
  }

  Widget _buildFolderList(BuildContext context) {
    if (folders.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 120,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: folders.length,
        itemBuilder: (context, index) {
          final folder = folders[index];
          final isSelected = selectedFolder?.path == folder.path;

          return ListTile(
            dense: true,
            leading: Icon(
              folder.isRoot ? Icons.folder_open : Icons.folder,
              size: 20,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            title: Text(
              folder.name,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : null,
              ),
            ),
            trailing: folder.noteCount > 0
                ? Text(
                    '${folder.noteCount}',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : null,
            selected: isSelected,
            selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
            onTap: () => onFolderSelected(folder),
          );
        },
      ),
    );
  }

  Widget _buildNoteList(BuildContext context) {
    if (notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.note_add_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              '暂无笔记',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('创建笔记'),
              onPressed: onCreateNote,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        final isSelected = selectedNote?.filePath == note.filePath;

        return ListTile(
          dense: true,
          leading: Icon(
            Icons.description_outlined,
            size: 20,
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          title: Text(
            note.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : null,
            ),
          ),
          subtitle: note.tags.isNotEmpty
              ? Wrap(
                  spacing: 4,
                  children: note.tags.take(3).map((tag) {
                    return Chip(
                      label: Text(
                        '#$tag',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    );
                  }).toList(),
                )
              : null,
          selected: isSelected,
          selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
          onTap: () => onNoteSelected(note),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'rename', child: Text('重命名')),
              const PopupMenuItem(value: 'move', child: Text('移动到...')),
              const PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
            onSelected: (value) {
              // TODO: 实现操作
            },
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新建笔记'),
              onPressed: onCreateNote,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () {
              context.read<NotesBloc>().add(const SyncWithGit());
            },
            tooltip: '同步',
          ),
        ],
      ),
    );
  }
}
