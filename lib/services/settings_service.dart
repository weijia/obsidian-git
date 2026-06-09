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

  GitConfig? get gitConfig => _gitConfig;
  String? get lastOpenedNotePath => _lastOpenedNotePath;
  String? get lastOpenedFolderPath => _lastOpenedFolderPath;
  bool get lastSourceMode => _lastSourceMode;

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
      print('公共 Documents 目录无访问权限: $e');
      return false;
    }
  }

  /// 获取设置文件的保存路径
  Future<String> _getSettingsFilePath() async {
    if (Platform.isAndroid) {
      try {
        final publicDir = Directory('/storage/emulated/0/Documents/ObsidianGit');
        if (!await publicDir.exists()) {
          await publicDir.create(recursive: true);
        }
        final testFile = File(p.join(publicDir.path, '.write_test'));
        await testFile.writeAsString('test');
        await testFile.delete();
        return p.join(publicDir.path, _settingsFileName);
      } catch (e) {
        print('公共 Documents 目录访问失败: $e，使用应用私有目录');
        final appDir = await getApplicationDocumentsDirectory();
        return p.join(appDir.path, _settingsFileName);
      }
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      return p.join(appDir.path, _settingsFileName);
    }
  }

  /// 加载设置
  Future<void> loadSettings() async {
    try {
      if (Platform.isAndroid) {
        final publicDir = Directory('/storage/emulated/0/Documents/ObsidianGit');
        final publicPath = p.join(publicDir.path, _settingsFileName);
        
        print('SettingsService: 检查公共目录: $publicPath');
        print('SettingsService:   目录是否存在: ${await publicDir.exists()}');
        
        try {
          if (await publicDir.exists()) {
            final files = await publicDir.list().toList();
            print('SettingsService:   目录下文件: ${files.map((f) => p.basename(f.path)).join(', ')}');
          }
        } catch (e) {
          print('SettingsService:   列出目录失败: $e');
        }
        
        final publicFile = File(publicPath);
        final fileExists = await publicFile.exists();
        print('SettingsService:   配置文件是否存在: $fileExists');
        
        if (fileExists) {
          try {
            final content = await publicFile.readAsString();
            print('SettingsService:   文件内容长度: ${content.length}');
            final json = jsonDecode(content) as Map<String, dynamic>;
            _gitConfig = _gitConfigFromJson(json['gitConfig']);
            // 加载 UI 状态
            _lastOpenedNotePath = json['lastOpenedNotePath'];
            _lastOpenedFolderPath = json['lastOpenedFolderPath'];
            _lastSourceMode = json['lastSourceMode'] ?? false;
            _settingsPath = publicPath;
            print('SettingsService: 从公共目录加载配置成功');
            print('SettingsService:   上次打开的笔记: $_lastOpenedNotePath');
            print('SettingsService:   上次打开的文件夹: $_lastOpenedFolderPath');
            print('SettingsService:   源码模式: $_lastSourceMode');
            return;
          } catch (e, stack) {
            print('SettingsService: 公共目录读取失败: $e');
            print('SettingsService: 堆栈: $stack');
          }
        }
      }

      // 尝试应用私有目录
      final appDir = await getApplicationDocumentsDirectory();
      final privatePath = p.join(appDir.path, _settingsFileName);
      final privateFile = File(privatePath);
      
      print('SettingsService: 检查应用私有目录: $privatePath');
      print('SettingsService:   文件是否存在: ${await privateFile.exists()}');
      
      if (await privateFile.exists()) {
        try {
          final content = await privateFile.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;
          _gitConfig = _gitConfigFromJson(json['gitConfig']);
          _lastOpenedNotePath = json['lastOpenedNotePath'];
          _lastOpenedFolderPath = json['lastOpenedFolderPath'];
          _lastSourceMode = json['lastSourceMode'] ?? false;
          _settingsPath = privatePath;
          print('SettingsService: 从应用私有目录加载配置成功');
          return;
        } catch (e, stack) {
          print('SettingsService: 应用私有目录读取失败: $e');
          print('SettingsService: 堆栈: $stack');
        }
      }

      print('SettingsService: 未找到配置文件');
      _gitConfig = null;
      _settingsPath = null;
    } catch (e, stack) {
      print('SettingsService: loadSettings 异常: $e');
      print('SettingsService: 堆栈: $stack');
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

      if (Platform.isAndroid) {
        try {
          final publicDir = Directory('/storage/emulated/0/Documents/ObsidianGit');
          if (!await publicDir.exists()) {
            await publicDir.create(recursive: true);
          }
          final publicPath = p.join(publicDir.path, _settingsFileName);
          final publicFile = File(publicPath);
          await publicFile.writeAsString(jsonStr);
          _settingsPath = publicPath;
          print('SettingsService: 配置已保存到公共目录');
          return;
        } catch (e) {
          print('SettingsService: 公共目录保存失败: $e，尝试应用私有目录');
        }
      }

      final appDir = await getApplicationDocumentsDirectory();
      final privatePath = p.join(appDir.path, _settingsFileName);
      final privateFile = File(privatePath);
      await privateFile.writeAsString(jsonStr);
      _settingsPath = privatePath;
      print('SettingsService: 配置已保存到应用私有目录');
    } catch (e) {
      print('SettingsService: saveSettings 失败: $e');
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
