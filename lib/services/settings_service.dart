import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/git_config.dart';

/// 设置服务 - 使用 shared_preferences 持久化配置
///
/// 不需要任何文件权限，底层使用 Android SharedPreferences / iOS NSUserDefaults
class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const _keyGitConfig = 'git_config';
  static const _keyLastNotePath = 'last_note_path';
  static const _keyLastFolderPath = 'last_folder_path';
  static const _keyLastSourceMode = 'last_source_mode';

  SharedPreferences? _prefs;
  GitConfig? _gitConfig;

  // 日志回调
  void Function(String)? onLog;

  GitConfig? get gitConfig => _gitConfig;
  String? get lastOpenedNotePath => _prefs?.getString(_keyLastNotePath);
  String? get lastOpenedFolderPath => _prefs?.getString(_keyLastFolderPath);
  bool get lastSourceMode => _prefs?.getBool(_keyLastSourceMode) ?? false;

  void _log(String message) {
    final line = '[Settings] $message';
    print(line);
    onLog?.call(line);
  }

  /// 初始化并加载设置
  Future<void> loadSettings() async {
    _log('初始化 SharedPreferences...');
    _prefs = await SharedPreferences.getInstance();
    _log('SharedPreferences 初始化完成');

    // 加载 Git 配置
    final gitConfigJson = _prefs!.getString(_keyGitConfig);
    if (gitConfigJson != null && gitConfigJson.isNotEmpty) {
      try {
        _gitConfig = _gitConfigFromJson(jsonDecode(gitConfigJson));
        _log('Git 配置已加载');
      } catch (e) {
        _log('Git 配置解析失败: $e');
        _gitConfig = null;
      }
    } else {
      _log('无 Git 配置');
      _gitConfig = null;
    }

    _log('UI 状态: notePath=$lastOpenedNotePath, folderPath=$lastOpenedFolderPath, sourceMode=$lastSourceMode');
  }

  /// 保存 Git 配置
  Future<void> setGitConfig(GitConfig config) async {
    _gitConfig = config;
    await _prefs?.setString(_keyGitConfig, jsonEncode(_gitConfigToJson(config)));
    _log('Git 配置已保存');
  }

  /// 清除 Git 配置
  Future<void> clearGitConfig() async {
    _gitConfig = null;
    await _prefs?.remove(_keyGitConfig);
    _log('Git 配置已清除');
  }

  /// 保存 UI 状态
  Future<void> saveUiState({
    String? notePath,
    String? folderPath,
    bool? sourceMode,
  }) async {
    if (notePath != null) {
      await _prefs?.setString(_keyLastNotePath, notePath);
    }
    if (folderPath != null) {
      await _prefs?.setString(_keyLastFolderPath, folderPath);
    }
    if (sourceMode != null) {
      await _prefs?.setBool(_keyLastSourceMode, sourceMode);
    }
    _log('UI 状态已保存: notePath=$notePath, folderPath=$folderPath, sourceMode=$sourceMode');
  }

  GitConfig? _gitConfigFromJson(Map<String, dynamic> json) {
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
