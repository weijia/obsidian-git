import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/git_config.dart';

/// 设置服务
class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  GitConfig? _gitConfig;
  String? _settingsPath;

  GitConfig? get gitConfig => _gitConfig;

  /// 加载设置
  Future<void> loadSettings() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _settingsPath = p.join(appDir.path, 'obsidian_git_settings.json');

      final file = File(_settingsPath!);
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        _gitConfig = _gitConfigFromJson(json['gitConfig']);
      }
    } catch (e) {
      // 加载失败时忽略错误，使用默认设置
      _gitConfig = null;
    }
  }

  /// 保存设置
  Future<void> saveSettings() async {
    if (_settingsPath == null) return;

    try {
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
