import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/git_config.dart';

/// 设置服务
///
/// Android 上配置文件保存到公共 Documents/ObsidianGit/ 目录，
/// 卸载 App 后配置不会丢失。其他平台使用应用文档目录。
class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const _settingsFileName = 'obsidian_git_settings.json';

  GitConfig? _gitConfig;
  String? _settingsPath;

  // UI 状态
  String? _lastOpenedNotePath;
  String? _lastOpenedFolderPath;
  bool _lastSourceMode = false;

  // 日志回调，用于向外部传递日志
  void Function(String)? onLog;

  GitConfig? get gitConfig => _gitConfig;
  String? get lastOpenedNotePath => _lastOpenedNotePath;
  String? get lastOpenedFolderPath => _lastOpenedFolderPath;
  bool get lastSourceMode => _lastSourceMode;
  String? get settingsPath => _settingsPath;

  void _log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final line = '[$timestamp] [Settings] $message';
    print(line);
    onLog?.call(line);
  }

  /// 检查是否有公共 Documents 目录的访问权限
  Future<bool> hasPublicDocumentsAccess() async {
    if (!Platform.isAndroid) return false;

    try {
      final publicDir = Directory('/storage/emulated/0/Documents/ObsidianGit');
      if (!await publicDir.exists()) {
        await publicDir.create(recursive: true);
      }
      final testFile = File(p.join(publicDir.path, '.write_test'));
      await testFile.writeAsString('test');
      await testFile.delete();
      return true;
    } catch (e) {
      _log('公共 Documents 目录无访问权限: $e');
      return false;
    }
  }

  /// 获取公共目录路径
  String get _publicDirPath => '/storage/emulated/0/Documents/ObsidianGit';

  /// 获取公共目录配置文件路径
  String get _publicFilePath => p.join(_publicDirPath, _settingsFileName);

  /// 加载设置
  Future<void> loadSettings() async {
    try {
      _log('开始加载设置...');

      if (Platform.isAndroid) {
        // 1. 尝试公共目录
        _log('检查公共目录: $_publicFilePath');
        try {
          final publicFile = File(_publicFilePath);
          final fileExists = await publicFile.exists();
          _log('  文件是否存在: $fileExists');

          if (fileExists) {
            final content = await publicFile.readAsString();
            _log('  文件内容长度: ${content.length} 字节');
            _log('  文件内容预览: ${content.length > 200 ? content.substring(0, 200) : content}');
            final json = jsonDecode(content) as Map<String, dynamic>;
            _gitConfig = _gitConfigFromJson(json['gitConfig']);
            _lastOpenedNotePath = json['lastOpenedNotePath'];
            _lastOpenedFolderPath = json['lastOpenedFolderPath'];
            _lastSourceMode = json['lastSourceMode'] ?? false;
            _settingsPath = _publicFilePath;
            _log('从公共目录加载成功');
            _log('  gitConfig: ${_gitConfig != null ? "有" : "无"}');
            _log('  lastOpenedNotePath: $_lastOpenedNotePath');
            _log('  lastOpenedFolderPath: $_lastOpenedFolderPath');
            _log('  lastSourceMode: $_lastSourceMode');
            return;
          } else {
            _log('  公共目录配置文件不存在');
          }
        } catch (e, stack) {
          _log('读取公共目录失败: $e');
          _log('  堆栈: $stack');
        }
      }

      // 2. 尝试应用私有目录
      final appDir = await getApplicationDocumentsDirectory();
      final privatePath = p.join(appDir.path, _settingsFileName);
      _log('检查应用私有目录: $privatePath');

      try {
        final privateFile = File(privatePath);
        final fileExists = await privateFile.exists();
        _log('  文件是否存在: $fileExists');

        if (fileExists) {
          final content = await privateFile.readAsString();
          _log('  文件内容长度: ${content.length} 字节');
          final json = jsonDecode(content) as Map<String, dynamic>;
          _gitConfig = _gitConfigFromJson(json['gitConfig']);
          _lastOpenedNotePath = json['lastOpenedNotePath'];
          _lastOpenedFolderPath = json['lastOpenedFolderPath'];
          _lastSourceMode = json['lastSourceMode'] ?? false;
          _settingsPath = privatePath;
          _log('从应用私有目录加载成功');
          _log('  gitConfig: ${_gitConfig != null ? "有" : "无"}');
          _log('  lastOpenedNotePath: $_lastOpenedNotePath');
          _log('  lastOpenedFolderPath: $_lastOpenedFolderPath');
          _log('  lastSourceMode: $_lastSourceMode');
          return;
        } else {
          _log('  应用私有目录配置文件不存在');
        }
      } catch (e, stack) {
        _log('读取应用私有目录失败: $e');
        _log('  堆栈: $stack');
      }

      // 3. 都没有找到
      _log('未找到任何配置文件（首次启动）');
      _gitConfig = null;
      _lastOpenedNotePath = null;
      _lastOpenedFolderPath = null;
      _lastSourceMode = false;
      _settingsPath = null;
    } catch (e, stack) {
      _log('loadSettings 异常: $e');
      _log('  堆栈: $stack');
      _gitConfig = null;
      _settingsPath = null;
    }
  }

  /// 保存设置
  Future<void> saveSettings() async {
    try {
      final json = <String, dynamic>{};
      if (_gitConfig != null) {
        json['gitConfig'] = _gitConfigToJson(_gitConfig!);
      }
      // 保存 UI 状态
      json['lastOpenedNotePath'] = _lastOpenedNotePath;
      json['lastOpenedFolderPath'] = _lastOpenedFolderPath;
      json['lastSourceMode'] = _lastSourceMode;
      final jsonStr = jsonEncode(json);
      _log('准备保存设置 (${jsonStr.length} 字节)');

      if (Platform.isAndroid) {
        try {
          final publicDir = Directory(_publicDirPath);
          if (!await publicDir.exists()) {
            await publicDir.create(recursive: true);
            _log('创建公共目录: ${publicDir.path}');
          }
          final publicFile = File(_publicFilePath);
          await publicFile.writeAsString(jsonStr);
          _settingsPath = _publicFilePath;
          _log('已保存到公共目录: $_publicFilePath');

          // 验证写入
          final verifyContent = await publicFile.readAsString();
          if (verifyContent == jsonStr) {
            _log('写入验证通过');
          } else {
            _log('写入验证失败！写入内容不匹配');
          }
          return;
        } catch (e) {
          _log('保存到公共目录失败: $e');
        }
      }

      // 回退到应用私有目录
      final appDir = await getApplicationDocumentsDirectory();
      final privatePath = p.join(appDir.path, _settingsFileName);
      final privateFile = File(privatePath);
      await privateFile.writeAsString(jsonStr);
      _settingsPath = privatePath;
      _log('已保存到应用私有目录: $privatePath');
    } catch (e) {
      _log('saveSettings 失败: $e');
    }
  }

  /// 设置 Git 配置
  Future<void> setGitConfig(GitConfig config) async {
    _gitConfig = config;
    await saveSettings();
  }

  /// 清除 Git 配置
  Future<void> clearGitConfig() async {
    _gitConfig = null;
    await saveSettings();
  }

  /// 保存 UI 状态（当前打开的笔记、文件夹、源码模式）
  Future<void> saveUiState({
    String? notePath,
    String? folderPath,
    bool? sourceMode,
  }) async {
    if (notePath != null) _lastOpenedNotePath = notePath;
    if (folderPath != null) _lastOpenedFolderPath = folderPath;
    if (sourceMode != null) _lastSourceMode = sourceMode;
    await saveSettings();
  }

  /// 从 JSON 解析 GitConfig
  GitConfig? _gitConfigFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;

    return GitConfig(
      repoUrl: json['repoUrl'] ?? '',
      branch: json['branch'] ?? 'main',
      localPath: json['localPath'] ?? '',
      username: json['username'],
      email: json['email'],
      sshKeyPath: json['sshKeyPath'],
      sshPublicKey: json['sshPublicKey'],
      sshPrivateKey: json['sshPrivateKey'],
      sshKeyPassword: json['sshKeyPassword'],
      httpsToken: json['httpsToken'],
      authMethod: AuthMethod.values.firstWhere(
        (e) => e.name == json['authMethod'],
        orElse: () => AuthMethod.https,
      ),
      syncFrequency: SyncFrequency.values.firstWhere(
        (e) => e.name == json['syncFrequency'],
        orElse: () => SyncFrequency.manual,
      ),
      autoSync: json['autoSync'] ?? false,
      lastSyncTime: json['lastSyncTime'] != null
          ? DateTime.parse(json['lastSyncTime'])
          : null,
      lastSyncStatus: SyncStatus.values.firstWhere(
        (e) => e.name == json['lastSyncStatus'],
        orElse: () => SyncStatus.notSynced,
      ),
    );
  }

  /// 将 GitConfig 转换为 JSON
  Map<String, dynamic> _gitConfigToJson(GitConfig config) {
    return {
      'repoUrl': config.repoUrl,
      'branch': config.branch,
      'localPath': config.localPath,
      'username': config.username,
      'email': config.email,
      'sshKeyPath': config.sshKeyPath,
      'sshPublicKey': config.sshPublicKey,
      'sshPrivateKey': config.sshPrivateKey,
      'sshKeyPassword': config.sshKeyPassword,
      'httpsToken': config.httpsToken,
      'authMethod': config.authMethod.name,
      'syncFrequency': config.syncFrequency.name,
      'autoSync': config.autoSync,
      'lastSyncTime': config.lastSyncTime?.toIso8601String(),
      'lastSyncStatus': config.lastSyncStatus.name,
    };
  }
}
