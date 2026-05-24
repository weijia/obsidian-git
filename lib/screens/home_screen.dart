import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/folder.dart';
import '../../models/note.dart';
import '../../blocs/notes/notes_bloc.dart';
import '../widgets/markdown_editor.dart';
import '../widgets/sidebar.dart';
import '../../services/note_storage_service.dart';
import '../../services/git_service.dart';
import '../../services/settings_service.dart';
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
  final SettingsService _settingsService = SettingsService();
  bool _sidebarVisible = true;
  double _sidebarWidth = 280;
  bool _isInitialized = false;
  String? _initError;

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
    try {
      // 加载设置
      await _settingsService.loadSettings();

      // 确定存储路径
      String? storagePath;

      // 如果配置了 Git 仓库，使用 Git 仓库路径
      if (_settingsService.gitConfig != null &&
          _settingsService.gitConfig!.localPath.isNotEmpty) {
        storagePath = _settingsService.gitConfig!.localPath;

        // 初始化 Git 服务
        await _gitService.init(_settingsService.gitConfig!);
      }

      // 初始化存储服务（如果没有 Git 配置，会使用默认应用文档目录）
      await _storageService.init(storagePath);

      setState(() {
        _isInitialized = true;
      });

      _notesBloc.add(const LoadNotes());
    } catch (e) {
      setState(() {
        _initError = e.toString();
        _isInitialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在初始化...'),
            ],
          ),
        ),
      );
    }

    if (_initError != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('初始化失败: $_initError'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _initError = null;
                    _isInitialized = false;
                  });
                  _initServices();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return BlocProvider.value(
      value: _notesBloc,
      child: Scaffold(
        body: SafeArea(
          child: BlocBuilder<NotesBloc, NotesState>(
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
        ), // SafeArea
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
        // 本地存储提示
        if (_settingsService.gitConfig == null)
          _buildLocalStorageBanner(context),
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
          const SizedBox(height: 8),
          Text(
            _settingsService.gitConfig == null
                ? '当前使用本地存储，可在设置中配置 Git 同步'
                : '笔记将自动同步到 Git 仓库',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('创建新笔记'),
            onPressed: () => _showCreateNoteDialog(context, null),
          ),
          if (_settingsService.gitConfig == null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.settings),
              label: const Text('配置 Git 同步'),
              onPressed: () => _openSettings(context),
            ),
          ],
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
          // 存储模式指示器
          if (_settingsService.gitConfig == null)
            Tooltip(
              message: '本地存储模式 - 点击配置 Git 同步',
              child: TextButton.icon(
                onPressed: () => _openSettings(context),
                icon: const Icon(Icons.computer, size: 16),
                label: const Text('本地'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.outline,
                ),
              ),
            )
          else
            Tooltip(
              message: 'Git 同步已启用',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sync,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Git',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 8),
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多操作',
            onSelected: (value) {
              switch (value) {
                case 'settings':
                  _openSettings(context);
                  break;
                case 'export':
                  _exportNote(state.selectedNote);
                  break;
                case 'delete':
                  _deleteCurrentNote(state.selectedNote);
                  break;
                case 'share':
                  _shareNote(state.selectedNote);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings),
                    SizedBox(width: 8),
                    Text('设置'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.download),
                    SizedBox(width: 8),
                    Text('导出 Markdown'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share),
                    SizedBox(width: 8),
                    Text('分享'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                    const SizedBox(width: 8),
                    Text('删除笔记', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                ),
              ),
            ],
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
          Expanded(
            child: Text(
              state.syncError ?? '正在同步...',
              style: TextStyle(
                color: state.syncError != null
                    ? Theme.of(context).colorScheme.onErrorContainer
                    : Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          if (state.syncError != null)
            TextButton(
              onPressed: () => _notesBloc.add(const SyncWithGit()),
              child: const Text('重试'),
            ),
        ],
      ),
    );
  }

  Widget _buildLocalStorageBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '当前使用本地存储。笔记保存在本机，可在设置中配置 Git 仓库进行同步。',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _openSettings(context),
            child: const Text('配置'),
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
    ).then((_) {
      // 返回设置页面后重新初始化服务
      _initServices();
    });
  }

  /// 导出笔记为 Markdown 文件
  void _exportNote(Note? note) {
    if (note == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择一个笔记')),
      );
      return;
    }
    // TODO: 实现导出功能
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('导出功能即将推出')),
    );
  }

  /// 分享笔记
  void _shareNote(Note? note) {
    if (note == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择一个笔记')),
      );
      return;
    }
    // TODO: 实现分享功能
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('分享功能即将推出')),
    );
  }

  /// 删除当前笔记
  void _deleteCurrentNote(Note? note) {
    if (note == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择一个笔记')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除笔记'),
        content: Text('确定要删除 "${note.title}" 吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _notesBloc.add(DeleteNote(note));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('"${note.title}" 已删除')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
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
