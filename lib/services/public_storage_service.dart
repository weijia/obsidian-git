import 'dart:convert';
import 'dart:io';
import 'package:docman/docman.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 公共目录存储服务 - 使用 Android SAF (Storage Access Framework) 访问公共 Documents 目录
///
/// 通过 docman 插件，用户首次使用时选择 ObsidianGit 目录，
/// 权限持久化，后续无需再次选择。
class PublicStorageService {
  static final PublicStorageService _instance = PublicStorageService._internal();
  factory PublicStorageService() => _instance;
  PublicStorageService._internal();

  static const _keyDirUri = 'public_dir_uri';
  static const _settingsFileName = 'obsidian_git_settings.json';

  SharedPreferences? _prefs;
  DocumentFile? _rootDir;

  // 日志回调
  void Function(String)? onLog;

  void _log(String message) {
    final line = '[PublicStorage] $message';
    print(line);
    onLog?.call(line);
  }

  /// 初始化服务
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    final uri = _prefs!.getString(_keyDirUri);
    if (uri != null && uri.isNotEmpty) {
      try {
        _rootDir = await DocumentFile.fromUri(uri);
        _log('已加载持久化目录: $uri');
      } catch (e) {
        _log('加载持久化目录失败: $e');
        _rootDir = null;
      }
    }
  }

  /// 是否已配置公共目录
  bool get isConfigured => _rootDir != null;

  /// 获取当前目录 URI
  String? get currentDirUri => _rootDir?.uri;

  /// 请求用户选择公共目录
  ///
  /// 返回是否成功选择目录
  Future<bool> requestDirectory() async {
    if (!Platform.isAndroid) {
      _log('非 Android 平台，跳过 SAF 目录选择');
      return false;
    }

    try {
      _log('打开目录选择器...');
      final dir = await DocMan.pick.directory();
      if (dir != null) {
        _rootDir = dir;
        await _prefs?.setString(_keyDirUri, dir.uri);
        _log('已选择目录: ${dir.uri}');
        return true;
      } else {
        _log('用户取消了目录选择');
        return false;
      }
    } catch (e) {
      _log('选择目录失败: $e');
      return false;
    }
  }

  /// 读取配置文件
  Future<String?> readSettings() async {
    if (_rootDir == null) {
      _log('目录未配置，无法读取设置');
      return null;
    }

    try {
      _log('查找配置文件...');
      final documents = await _rootDir!.listDocuments();
      final settingsFile = documents.firstWhere(
        (doc) => doc.name == _settingsFileName,
        orElse: () => throw Exception('配置文件不存在'),
      );

      _log('读取配置文件内容...');
      final bytes = await settingsFile.readBytes();
      final content = utf8.decode(bytes);
      _log('配置文件读取成功 (${content.length} 字节)');
      return content;
    } catch (e) {
      _log('读取配置文件失败: $e');
      return null;
    }
  }

  /// 写入配置文件
  Future<bool> writeSettings(String content) async {
    if (_rootDir == null) {
      _log('目录未配置，无法写入设置');
      return false;
    }

    try {
      _log('写入配置文件...');
      final bytes = utf8.encode(content);
      await _rootDir!.saveBytes(
        bytes: bytes,
        mimeType: 'application/json',
        name: _settingsFileName,
      );
      _log('配置文件写入成功');
      return true;
    } catch (e) {
      _log('写入配置文件失败: $e');
      return false;
    }
  }

  /// 获取笔记目录的 DocumentFile
  Future<DocumentFile?> getNotesDirectory() async {
    if (_rootDir == null) return null;

    try {
      final documents = await _rootDir!.listDocuments();
      final notesDir = documents.firstWhere(
        (doc) => doc.name == 'notes' && doc.isDirectory,
        orElse: () => throw Exception('笔记目录不存在'),
      );
      return notesDir;
    } catch (e) {
      // 目录不存在，尝试创建
      try {
        _log('创建 notes 目录...');
        return await _rootDir!.createDirectory('notes');
      } catch (e2) {
        _log('创建 notes 目录失败: $e2');
        return null;
      }
    }
  }

  /// 列出笔记目录下的所有文件
  Future<List<DocumentFile>> listNoteFiles() async {
    final notesDir = await getNotesDirectory();
    if (notesDir == null) return [];

    try {
      final documents = await notesDir.listDocuments();
      return documents.where((doc) => !doc.isDirectory).toList();
    } catch (e) {
      _log('列出笔记文件失败: $e');
      return [];
    }
  }

  /// 读取笔记文件
  Future<String?> readNote(String fileName) async {
    final notesDir = await getNotesDirectory();
    if (notesDir == null) return null;

    try {
      final documents = await notesDir.listDocuments();
      final file = documents.firstWhere(
        (doc) => doc.name == fileName,
        orElse: () => throw Exception('文件不存在'),
      );
      final bytes = await file.readBytes();
      return utf8.decode(bytes);
    } catch (e) {
      _log('读取笔记失败: $e');
      return null;
    }
  }

  /// 写入笔记文件
  Future<bool> writeNote(String fileName, String content) async {
    final notesDir = await getNotesDirectory();
    if (notesDir == null) return false;

    try {
      final bytes = utf8.encode(content);
      await notesDir.saveBytes(
        bytes: bytes,
        mimeType: 'text/markdown',
        name: fileName,
      );
      return true;
    } catch (e) {
      _log('写入笔记失败: $e');
      return false;
    }
  }

  /// 删除笔记文件
  Future<bool> deleteNote(String fileName) async {
    final notesDir = await getNotesDirectory();
    if (notesDir == null) return false;

    try {
      final documents = await notesDir.listDocuments();
      final file = documents.firstWhere(
        (doc) => doc.name == fileName,
        orElse: () => throw Exception('文件不存在'),
      );
      await file.delete();
      return true;
    } catch (e) {
      _log('删除笔记失败: $e');
      return false;
    }
  }
}
