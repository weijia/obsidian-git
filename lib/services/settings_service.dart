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

  GitConfig? get gitConfig => _gitConfig;

  /// 获取设置文件的保存路径
  ///
  /// - Android: /storage/emulated/0/Documents/ObsidianGit/obsidian_git_settings.json
  ///   （公共目录，卸载 App 后保留）
  /// - 其他平台: 应用文档目录/obsidian_git_settings.json
  Future<String> _getSettingsFilePath() async {
    if (Platform.isAndroid) {
      // Android: 尝试保存到公共 Documents 目录
      // /storage/emulated/0/Documents/ObsidianGit/
      try {
        final publicDir = Directory('/storage/emulated/0/Documents/ObsidianGit');
        if (!await publicDir.exists()) {
          await publicDir.create(recursive: true);
        }
        // 测试是否有写入权限
        final testFile = File(p.join(publicDir.path, '.write_test'));
        await testFile.writeAsString('test');
        await testFile.delete();
        return p.join(publicDir.path, _settingsFileName);
      } catch (e) {
        // 公共目录访问失败，降级到应用私有目录
        print('公共 Documents 目录访问失败: $e，使用应用私有目录');
        final appDir = await getApplicationDocumentsDirectory();
        return p.join(appDir.path, _settingsFileName);
      }
    } else {
      // 其他平台：使用应用文档目录
      final appDir = await getApplicationDocumentsDirectory();
      return p.join(appDir.path, _settingsFileName);
    }
  }

  /// 加载设置
  ///
  /// Android 上同时尝试从公共目录和旧的应用私有目录加载
  Future<void> loadSettings() async {
    try {
      // 优先从新位置（公共目录）加载
      _settingsPath = await _getSettingsFilePath();
      var file = File(_settingsPath!);

      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        _gitConfig = _gitConfigFromJson(json['gitConfig']);
        return;
      }

      // Android: 尝试从旧位置（应用私有目录）迁移
      if (Platform.isAndroid) {
        final appDir = await getApplicationDocumentsDirectory();
        final oldPath = p.join(appDir.path, _settingsFileName);
        final oldFile = File(oldPath);
        if (await oldFile.exists()) {
          final content = await oldFile.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;
          _gitConfig = _gitConfigFromJson(json['gitConfig']);
          // 迁移到新位置
          await saveSettings();
          // 删除旧文件
          try {
            await oldFile.delete();
          } catch (_) {}
          return;
        }
      }

      // 没有找到设置文件，使用默认值
      _gitConfig = null;
    } catch (e) {
      // 加载失败时忽略错误，使用默认设置
      _gitConfig = null;
    }
  }

  /// 保存设置
  Future<void> saveSettings() async {
    try {
      _settingsPath ??= await _getSettingsFilePath();
      final file = File(_settingsPath!);
      final json = <String, dynamic>{};
      if (_gitConfig != null) {
        json['gitConfig'] = _gitConfigToJson(_gitConfig!);
      }
      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      // 保存失败时忽略错误
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
