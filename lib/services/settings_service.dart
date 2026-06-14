import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:docman/docman.dart';
import '../models/git_config.dart';

/// 设置服务 - 支持 SAF 公共目录和 shared_preferences 双重存储
///
/// 优先级：
/// 1. SAF 公共目录（Documents/ObsidianGit/）- 卸载后保留
/// 2. shared_preferences - 降级方案
class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const _keyGitConfig = 'git_config';
  static const _keyLastNotePath = 'last_note_path';
  static const _keyLastFolderPath = 'last_folder_path';
  static const _keyLastSourceMode = 'last_source_mode';
  static const _keyDirUri = 'saf_dir_uri';
  static const _settingsFileName = 'obsidian_git_settings.json';

  SharedPreferences? _prefs;
  GitConfig? _gitConfig;
  DocumentFile? _safDir;

  // UI 状态
  String? _lastOpenedNotePath;
  String? _lastOpenedFolderPath;
  bool _lastSourceMode = false;
  bool _showArchived = true; // 显示归档文件（默认显示）

  // 日志回调
  void Function(String)? onLog;

  GitConfig? get gitConfig => _gitConfig;
  String? get lastOpenedNotePath => _lastOpenedNotePath;
  String? get lastOpenedFolderPath => _lastOpenedFolderPath;
  bool get lastSourceMode => _lastSourceMode;
  bool get showArchived => _showArchived;
  bool get hasSafDirectory => _safDir != null;
  String? get safDirectoryUri => _safDir?.uri;

  void _log(String message) {
    final line = '[Settings] $message';
    print(line);
    onLog?.call(line);
  }

  /// 初始化并加载设置
  Future<void> loadSettings() async {
    _log('初始化...');
    _prefs = await SharedPreferences.getInstance();

    // 1. 尝试从 SAF 公共目录加载
    final safUri = _prefs!.getString(_keyDirUri);
    if (safUri != null && safUri.isNotEmpty && Platform.isAndroid) {
      _log('尝试从 SAF 目录加载: $safUri');
      try {
        _safDir = await DocumentFile.fromUri(safUri);
        if (_safDir != null) {
          final safContent = await _readFromSaf();
          if (safContent != null) {
            _log('从 SAF 加载成功');
            _parseConfig(safContent);
            return;
          }
        }
      } catch (e) {
        _log('SAF 加载失败: $e');
        _safDir = null;
      }
    }

    // 2. 从 shared_preferences 加载（降级）
    _log('从 shared_preferences 加载');
    _loadFromSharedPreferences();
  }

  /// 从 SAF 读取配置文件内容
  Future<String?> _readFromSaf() async {
    if (_safDir == null) return null;

    try {
      final documents = await _safDir!.listDocuments();
      final settingsFile = documents.firstWhere(
        (doc) => doc.name == _settingsFileName,
        orElse: () => throw Exception('配置文件不存在'),
      );
      final bytes = await settingsFile.read();
      if (bytes == null) return null;
      return utf8.decode(bytes);
    } catch (e) {
      _log('读取 SAF 配置失败: $e');
      return null;
    }
  }

  /// 从 shared_preferences 加载
  void _loadFromSharedPreferences() {
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

    _lastOpenedNotePath = _prefs!.getString(_keyLastNotePath);
    _lastOpenedFolderPath = _prefs!.getString(_keyLastFolderPath);
    _lastSourceMode = _prefs!.getBool(_keyLastSourceMode) ?? false;
    _showArchived = _prefs!.getBool('show_archived') ?? true;

    _log('UI 状态: notePath=$_lastOpenedNotePath, folderPath=$_lastOpenedFolderPath, sourceMode=$_lastSourceMode, showArchived=$_showArchived');
  }

  /// 解析配置内容
  void _parseConfig(String content) {
    try {
      final json = jsonDecode(content) as Map<String, dynamic>;
      if (json['gitConfig'] != null) {
        _gitConfig = _gitConfigFromJson(json['gitConfig']);
      }
      _lastOpenedNotePath = json['lastOpenedNotePath'];
      _lastOpenedFolderPath = json['lastOpenedFolderPath'];
      _lastSourceMode = json['lastSourceMode'] ?? false;
      _showArchived = json['showArchived'] ?? true;
      // 加载 SAF 目录 URI（稍后异步恢复）
      _pendingSafUri = json['safDirectoryUri'];
      _log('UI 状态: showArchived=$_showArchived, safUri=$_pendingSafUri');
    } catch (e) {
      _log('解析配置失败: $e');
    }
  }
  
  /// 待恢复的 SAF 目录 URI
  String? _pendingSafUri;
  
  /// 恢复 SAF 目录（从保存的 URI）
  Future<void> restoreSafDirectory() async {
    if (_pendingSafUri == null || _pendingSafUri!.isEmpty) {
      _log('无保存的 SAF 目录 URI');
      return;
    }
    
    try {
      _log('恢复 SAF 目录: $_pendingSafUri');
      final dir = await DocumentFile.fromUri(_pendingSafUri!);
      if (dir != null && dir.exists) {
        _safDir = dir;
        _log('SAF 目录已恢复: ${dir.uri}');
      } else {
        _log('SAF 目录不存在或无权限');
      }
    } catch (e) {
      _log('恢复 SAF 目录失败: $e');
    }
  }

  /// 请求用户选择 SAF 目录
  Future<bool> requestSafDirectory() async {
    if (!Platform.isAndroid) {
      _log('非 Android 平台，跳过 SAF');
      return false;
    }

    try {
      _log('打开 SAF 目录选择器...');
      final dir = await DocMan.pick.directory();
      if (dir != null) {
        _safDir = dir;
        await _prefs?.setString(_keyDirUri, dir.uri);
        _log('SAF 目录已选择: ${dir.uri}');
        return true;
      }
      return false;
    } catch (e) {
      _log('SAF 目录选择失败: $e');
      return false;
    }
  }

  /// 保存 Git 配置
  Future<void> setGitConfig(GitConfig config) async {
    _gitConfig = config;
    await _saveAll();
    _log('Git 配置已保存');
  }

  /// 清除 Git 配置
  Future<void> clearGitConfig() async {
    _gitConfig = null;
    await _saveAll();
    _log('Git 配置已清除');
  }

  /// 保存 UI 状态
  Future<void> saveUiState({
    String? notePath,
    String? folderPath,
    bool? sourceMode,
    bool? showArchived,
  }) async {
    if (notePath != null) _lastOpenedNotePath = notePath;
    if (folderPath != null) _lastOpenedFolderPath = folderPath;
    if (sourceMode != null) _lastSourceMode = sourceMode;
    if (showArchived != null) _showArchived = showArchived;
    await _saveAll();
    _log('UI 状态已保存');
  }

  /// 保存所有配置
  Future<void> _saveAll() async {
    final json = <String, dynamic>{};
    if (_gitConfig != null) {
      json['gitConfig'] = _gitConfigToJson(_gitConfig!);
    }
    json['lastOpenedNotePath'] = _lastOpenedNotePath;
    json['lastOpenedFolderPath'] = _lastOpenedFolderPath;
    json['lastSourceMode'] = _lastSourceMode;
    json['showArchived'] = _showArchived;
    // 保存 SAF 目录 URI
    if (_safDir != null) {
      json['safDirectoryUri'] = _safDir!.uri;
    }
    final content = jsonEncode(json);

    // 1. 尝试保存到 SAF
    if (_safDir != null) {
      try {
        await _writeToSaf(content);
        _log('已保存到 SAF');
      } catch (e) {
        _log('保存到 SAF 失败: $e');
      }
    }

    // 2. 同时保存到 shared_preferences（备份）
    await _prefs?.setString(_keyGitConfig, _gitConfig != null ? jsonEncode(_gitConfigToJson(_gitConfig!)) : '');
    await _prefs?.setString(_keyLastNotePath, _lastOpenedNotePath ?? '');
    await _prefs?.setString(_keyLastFolderPath, _lastOpenedFolderPath ?? '');
    await _prefs?.setBool(_keyLastSourceMode, _lastSourceMode);
    await _prefs?.setBool('show_archived', _showArchived);
    // 保存 SAF 目录 URI 到 shared_preferences
    if (_safDir != null) {
      await _prefs?.setString(_keyDirUri, _safDir!.uri);
    }
  }

  /// 写入到 SAF
  Future<void> _writeToSaf(String content) async {
    if (_safDir == null) return;

    final bytes = utf8.encode(content);
    // 先查找是否存在配置文件
    final existingFile = await _safDir!.find(_settingsFileName);
    if (existingFile != null) {
      // 存在则删除后重新创建
      await existingFile.delete();
    }
    // 创建新文件
    await _safDir!.createFile(
      name: _settingsFileName,
      bytes: bytes,
    );
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