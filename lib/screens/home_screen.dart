import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _isSourceMode = false; // 源码模式状态
  bool _hasRestoredNote = false; // 是否已恢复过笔记（防止重复）

  // 调试日志（显示在界面上，不需要 adb）
  final List<String> _debugLogs = [];
  bool _showDebugPanel = false;

  void _log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final line = '[$timestamp] $message';
    print(line);
    _debugLogs.add(line);
    if (_debugLogs.length > 100) _debugLogs.removeAt(0);
  }

  /// 恢复上次打开的文件夹
  void _restoreLastOpenedState() {
    final folderPath = _settingsService.lastOpenedFolderPath;
    if (folderPath != null && folderPath.isNotEmpty) {
      _notesBloc.add(LoadNotes(folderPath: folderPath));
      _log('恢复上次打开的文件夹: $folderPath');
    }
  }

  /// 在笔记列表加载完成后恢复上次打开的笔记
  void _restoreLastOpenedNote(NotesLoaded state) {
    if (_hasRestoredNote) return;
    final notePath = _settingsService.lastOpenedNotePath;
    if (notePath != null && notePath.isNotEmpty) {
      final note = state.notes.where((n) => n.filePath == notePath).firstOrNull;
      if (note != null) {
        _notesBloc.add(SelectNote(note));
        _log('恢复上次打开的笔记: ${note.title}');
      } else {
        _log('上次打开的笔记已不存在: $notePath');
      }
    }
    _hasRestoredNote = true;
  }

  /// 保存当前 UI 状态到配置文件
  Future<void> _saveCurrentUiState() async {
    final state = _notesBloc.state;
    if (state is NotesLoaded) {
      await _settingsService.saveUiState(
        notePath: state.selectedNote?.filePath,
        folderPath: state.currentFolderPath,
        sourceMode: _isSourceMode,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _notesBloc = NotesBloc(
      storageService: _storageService,
      gitService: _gitService,
      settingsService: _settingsService,
    );
    _initServices();
  }

  Future<void> _initServices() async {
    try {
      _log('开始初始化...');

      // Android: 检查并请求存储权限
      if (Platform.isAndroid) {
        await _requestStoragePermissionIfNeeded();
      }

      // 加载设置
      await _settingsService.loadSettings();

      final config = _settingsService.gitConfig;
      _log('配置加载结果: ${config != null ? "有配置" : "无配置"}');
      if (config != null) {
        _log('  repoUrl: ${config.repoUrl}');
        _log('  localPath: "${config.localPath}"');
        _log('  branch: ${config.branch}');
        _log('  email: ${config.email}');
      }

      // 确定存储路径
      String? storagePath;

      // 如果配置了 Git 仓库，使用 Git 仓库路径
      if (config != null && config.localPath.isNotEmpty) {
        storagePath = config.localPath;
        _log('使用配置中的 localPath: $storagePath');
      } else if (config != null && config.repoUrl.isNotEmpty) {
        // 配置存在但 localPath 为空（可能保存失败），重新获取路径
        storagePath = await _gitService.getRepoPath();
        _log('localPath 为空，重新获取: $storagePath');
      } else {
        _log('无 Git 配置，使用默认路径');
      }

      // 如果有 Git 配置，初始化 Git 服务
      if (config != null && config.repoUrl.isNotEmpty) {
        try {
          await _gitService.initialize();
          _log('Git 服务初始化成功');
        } catch (e) {
          _log('Git 服务初始化失败: $e');
        }
      }

      // 初始化存储服务
      await _storageService.init(storagePath);
      _log('存储路径: ${_storageService.basePath}');

      // 检查目录下是否有 .md 文件
      if (_storageService.basePath != null) {
        final dir = Directory(_storageService.basePath!);
        if (await dir.exists()) {
          final mdFiles = await dir.list(recursive: true)
              .where((e) => e is File && e.path.endsWith('.md'))
              .toList();
          _log('目录 ${_storageService.basePath} 下有 ${mdFiles.length} 个 .md 文件');
          for (final f in mdFiles.take(10)) {
            _log('  📄 ${f.path}');
          }
          if (mdFiles.length > 10) {
            _log('  ... 还有 ${mdFiles.length - 10} 个文件');
          }
        } else {
          _log('⚠️ 目录 ${_storageService.basePath} 不存在！');
        }
      } else {
        _log('⚠️ basePath 为 null！');
      }

      setState(() {
        _isInitialized = true;
        // 恢复上次的状态
        _isSourceMode = _settingsService.lastSourceMode;
      });

      _notesBloc.add(const LoadNotes());
      _log('初始化完成，已发送 LoadNotes 事件');

      // 恢复上次打开的文件夹和笔记
      _restoreLastOpenedState();
    } catch (e, stack) {
      _log('❌ _initServices 异常: $e');
      _log('堆栈: $stack');
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
          child: BlocConsumer<NotesBloc, NotesState>(
          listenWhen: (previous, current) {
            // 只在 NotesLoaded 且笔记列表变化时触发
            if (current is! NotesLoaded) return false;
            if (previous is! NotesLoaded) return true;
            return previous.selectedNote?.filePath != current.selectedNote?.filePath ||
                   previous.currentFolderPath != current.currentFolderPath;
          },
          listener: (context, state) {
            if (state is NotesLoaded) {
              if (!_hasRestoredNote) {
                _restoreLastOpenedNote(state);
              } else {
                _saveCurrentUiState();
              }
            }
          },
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
                          _saveCurrentUiState();
                        },
                        onNoteSelected: (note) {
                          _notesBloc.add(SelectNote(note));
                          // 保存由 BlocConsumer listener 自动处理
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
        ), // BlocConsumer
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
            child: MarkdownEditor(
              note: state.selectedNote!,
              isSourceMode: _isSourceMode,
              onSourceModeChanged: (value) {
                setState(() {
                  _isSourceMode = value;
                });
                _saveCurrentUiState();
              },
            ),
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
          // 源码模式切换按钮
          TextButton.icon(
            onPressed: () {
              setState(() {
                _isSourceMode = !_isSourceMode;
              });
              _saveCurrentUiState();
            },
            icon: Icon(
              _isSourceMode ? Icons.visibility : Icons.code,
              size: 18,
            ),
            label: Text(_isSourceMode ? '预览' : '源码'),
            style: TextButton.styleFrom(
              foregroundColor: _isSourceMode
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              backgroundColor: _isSourceMode
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
          // 同步按钮
          _buildSyncButton(context, state),
          // 更多菜单
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
                case 'debug':
                  _showDebugLog();
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
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'debug',
                child: Row(
                  children: [
                    Icon(Icons.bug_report, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('调试日志', style: TextStyle(color: Colors.orange)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建同步按钮（根据状态显示不同图标）
  Widget _buildSyncButton(BuildContext context, NotesLoaded state) {
    final colorScheme = Theme.of(context).colorScheme;

    IconData icon;
    Color? iconColor;
    String tooltip;
    VoidCallback? onPressed;

    if (state.isSyncing) {
      icon = Icons.sync;
      iconColor = colorScheme.primary;
      tooltip = '同步中...';
      onPressed = null;
    } else if (state.syncError != null && state.syncError!.isNotEmpty) {
      icon = Icons.error_outline;
      iconColor = colorScheme.error;
      tooltip = '同步失败，点击重试';
      onPressed = () => _notesBloc.add(const SyncWithGit());
    } else if (state.hasUnsyncedChanges) {
      icon = Icons.cloud_upload;
      iconColor = colorScheme.primary;
      tooltip = '有未同步的修改，点击上传';
      onPressed = () => _notesBloc.add(const SyncWithGit());
    } else {
      icon = Icons.cloud_done;
      iconColor = colorScheme.outline;
      tooltip = '已同步';
      onPressed = () => _notesBloc.add(const SyncWithGit());
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: IconButton(
        key: ValueKey<String>('${icon}_${state.isSyncing}'),
        icon: state.isSyncing
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: iconColor,
                ),
              )
            : Icon(icon, color: iconColor),
        onPressed: onPressed,
        tooltip: tooltip,
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

  /// 显示调试日志弹窗
  /// Android: 检查并请求存储权限
  ///
  /// Android 11+ 的 MANAGE_EXTERNAL_STORAGE 权限需要跳转到系统设置页面。
  /// 如果没有权限，弹出对话框引导用户去设置页面开启。
  Future<void> _requestStoragePermissionIfNeeded() async {
    final hasAccess = await _settingsService.hasPublicDocumentsAccess();
    _log('存储权限检查: ${hasAccess ? "已授权" : "未授权"}');

    if (!hasAccess) {
      _log('需要请求存储权限，弹出权限请求对话框');
      _showStoragePermissionDialog();
    }
  }

  /// 显示存储权限请求对话框
  void _showStoragePermissionDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.folder, color: Colors.blue),
              SizedBox(width: 8),
              Text('需要存储权限'),
            ],
          ),
          content: const Text(
            '为了在重新安装 App 后保留配置，\n'
            '需要访问公共 Documents 目录。\n\n'
            '点击"前往设置"后，请在权限页面\n'
            '开启"所有文件访问权限"。',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _log('用户拒绝了存储权限');
              },
              child: const Text('稍后再说'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                _log('用户同意前往设置页面');
                await _openStoragePermissionSettings();
              },
              child: const Text('前往设置'),
            ),
          ],
        ),
      );
    });
  }

  /// 打开 Android 存储权限设置页面
  Future<void> _openStoragePermissionSettings() async {
    try {
      // 使用 MethodChannel 调用原生 Android 代码打开设置页面
      const platform = MethodChannel('com.obsidiangit.obsidian_git/permissions');
      await platform.invokeMethod('openStoragePermissionSettings');
      _log('已请求打开存储权限设置页面');
    } catch (e) {
      _log('打开设置页面失败: $e');
      // 降级：打开应用详情页
      try {
        const platform = MethodChannel('com.obsidiangit.obsidian_git/permissions');
        await platform.invokeMethod('openAppSettings');
        _log('已请求打开应用设置页面');
      } catch (e2) {
        _log('打开应用详情页也失败: $e2');
      }
    }
  }

  void _showDebugLog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🔍 调试日志'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: _debugLogs.isEmpty
              ? const Center(child: Text('暂无日志'))
              : ListView.builder(
                  itemCount: _debugLogs.length,
                  itemBuilder: (context, index) {
                    final log = _debugLogs[index];
                    final isError = log.contains('❌') || log.contains('⚠️');
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Text(
                        log,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: isError ? Colors.red : Colors.black87,
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // 复制日志到剪贴板
              Clipboard.setData(ClipboardData(text: _debugLogs.join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('日志已复制到剪贴板')),
              );
            },
            child: const Text('复制全部'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
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
    ).then((result) {
      // 返回设置页面后重新初始化服务
      // result 为 true 表示需要强制刷新（如 clone/fetch 成功）
      if (result == true) {
        // 重置初始化状态，强制重新加载
        setState(() {
          _isInitialized = false;
        });
      }
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
              _notesBloc.add(DeleteNote(note.filePath));
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
    super.dispose();
  }
}

