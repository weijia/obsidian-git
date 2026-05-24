import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/folder.dart';
import '../../blocs/notes/notes_bloc.dart';
import '../widgets/markdown_editor.dart';
import '../widgets/sidebar.dart';
import '../../services/note_storage_service.dart';
import '../../services/git_service.dart';
import 'settings_screen.dart';

/// 主屏幕 - 参考 gitjournal 布局
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late NotesBloc _notesBloc;
  final NoteStorageService _storageService = NoteStorageService();
  final GitService _gitService = GitService();
  bool _sidebarVisible = true;
  double _sidebarWidth = 280;

  @override
  void initState() {
    super.initState();
    _notesBloc = NotesBloc(
      storageService: _storageService,
      gitService: _gitService,
    );
    _initServices();
  }

  Future<void> _initServices() async {
    await _storageService.init(null);
    _notesBloc.add(const LoadNotes());
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _notesBloc,
      child: Scaffold(
        body: BlocBuilder<NotesBloc, NotesState>(
          builder: (context, state) {
            if (state is NotesLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state is NotesError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('错误: ${state.message}'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => _notesBloc.add(const LoadNotes()),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              );
            }

            if (state is NotesLoaded) {
              return Row(
                children: [
                  // 侧边栏
                  if (_sidebarVisible)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: _sidebarWidth,
                      child: Sidebar(
                        folders: state.folders,
                        notes: state.notes,
                        selectedFolder: state.currentFolderPath != null
                            ? Folder.fromPath(state.currentFolderPath!)
                            : null,
                        selectedNote: state.selectedNote,
                        onFolderSelected: (folder) {
                          _notesBloc.add(LoadNotes(folderPath: folder?.path));
                        },
                        onNoteSelected: (note) {
                          _notesBloc.add(SelectNote(note));
                        },
                        onCreateNote: () => _showCreateNoteDialog(context, state),
                        onOpenSettings: () => _openSettings(context),
                      ),
                    ),
                  // 分隔条
                  if (_sidebarVisible)
                    GestureDetector(
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          _sidebarWidth = (_sidebarWidth + details.delta.dx)
                              .clamp(200.0, 400.0);
                        });
                      },
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: Container(
                          width: 4,
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                    ),
                  // 主内容区
                  Expanded(
                    child: _buildMainContent(context, state),
                  ),
                ],
              );
            }

            return const Center(child: Text('初始化中...'));
          },
        ),
        // 浮动按钮 - 切换侧边栏
        floatingActionButton: FloatingActionButton.small(
          onPressed: () => setState(() => _sidebarVisible = !_sidebarVisible),
          child: Icon(_sidebarVisible ? Icons.menu_open : Icons.menu),
        ),
      ),
    );
  }

  Widget _buildMainContent(BuildContext context, NotesLoaded state) {
    if (state.selectedNote == null) {
      return _buildEmptyState(context);
    }

    return Column(
      children: [
        // 标题栏
        _buildTitleBar(context, state),
        // 编辑器
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: MarkdownEditor(note: state.selectedNote!),
          ),
        ),
        // 同步状态栏
        if (state.isSyncing || state.syncError != null)
          _buildSyncStatusBar(context, state),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.edit_note,
            size: 80,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 24),
          Text(
            '选择或创建一个笔记开始编辑',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('创建新笔记'),
            onPressed: () => _showCreateNoteDialog(context, null),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleBar(BuildContext context, NotesLoaded state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.description_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.selectedNote?.title ?? '未命名笔记',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          // 同步状态
          if (state.isSyncing)
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('同步中...'),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: state.isSyncing
                ? null
                : () => _notesBloc.add(const SyncWithGit()),
            tooltip: '同步到 Git',
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              // TODO: 显示更多操作
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSyncStatusBar(BuildContext context, NotesLoaded state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: state.syncError != null
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.primaryContainer,
      child: Row(
        children: [
          Icon(
            state.syncError != null ? Icons.error_outline : Icons.sync,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            state.syncError ?? '正在同步...',
            style: TextStyle(
              color: state.syncError != null
                  ? Theme.of(context).colorScheme.onErrorContainer
                  : Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          const Spacer(),
          if (state.syncError != null)
            TextButton(
              onPressed: () => _notesBloc.add(const SyncWithGit()),
              child: const Text('重试'),
            ),
        ],
      ),
    );
  }

  void _showCreateNoteDialog(BuildContext context, NotesLoaded? state) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创建新笔记'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '笔记标题',
            hintText: '输入笔记标题',
          ),
          autofocus: true,
          onSubmitted: (value) {
            if (value.isNotEmpty) {
              Navigator.pop(context);
              _notesBloc.add(CreateNote(
                title: value,
                folderPath: state?.currentFolderPath,
              ));
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                Navigator.pop(context);
                _notesBloc.add(CreateNote(
                  title: controller.text,
                  folderPath: state?.currentFolderPath,
                ));
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SettingsScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _notesBloc.close();
    _gitService.close();
    super.dispose();
  }
}
