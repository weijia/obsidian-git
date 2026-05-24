import 'dart:convert';
import 'dart:io';
import 'package:go_git_dart/go_git_dart.dart' as go_git_dart;
import 'package:dart_git/dart_git.dart' as dart_git;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/git_config.dart';

/// Git 服务 - 使用 GitJournal 方案
/// 移动端：go_git_dart (Go FFI) 处理网络操作
/// 所有平台：dart_git 处理本地操作
class GitService {
  static final GitService _instance = GitService._internal();
  factory GitService() => _instance;
  GitService._internal();

  go_git_dart.GitBindings? _gitBindings;
  bool _isInitialized = false;

  /// 初始化 Git 服务
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      _gitBindings = go_git_dart.GitBindings();
      _isInitialized = true;
    } catch (e) {
      print('GitService 初始化失败: $e');
      rethrow;
    }
  }

  /// 克隆仓库
  Future<void> clone({
    required String url,
    required String localPath,
    String? privateKey,
    String? privateKeyPassword,
  }) async {
    if (!_isInitialized) await initialize();
    
    try {
      _gitBindings!.clone(
        url,
        localPath,
        privateKey != null ? utf8.encode(privateKey) : utf8.encode(''),
        privateKeyPassword ?? '',
      );
    } catch (e) {
      print('克隆失败: $e');
      rethrow;
    }
  }

  /// 获取远程更新
  Future<void> fetch({
    required String localPath,
    String remoteName = 'origin',
    String? privateKey,
    String? privateKeyPassword,
  }) async {
    if (!_isInitialized) await initialize();
    
    try {
      _gitBindings!.fetch(
        remoteName,
        localPath,
        privateKey != null ? utf8.encode(privateKey) : utf8.encode(''),
        privateKeyPassword ?? '',
      );
    } catch (e) {
      print('获取更新失败: $e');
      rethrow;
    }
  }

  /// 推送到远程
  Future<void> push({
    required String localPath,
    String remoteName = 'origin',
    String? privateKey,
    String? privateKeyPassword,
  }) async {
    if (!_isInitialized) await initialize();
    
    try {
      _gitBindings!.push(
        remoteName,
        localPath,
        privateKey != null ? utf8.encode(privateKey) : utf8.encode(''),
        privateKeyPassword ?? '',
      );
    } catch (e) {
      print('推送失败: $e');
      rethrow;
    }
  }

  /// 获取默认分支名称
  Future<String> getDefaultBranch({
    required String url,
    String? privateKey,
    String? privateKeyPassword,
  }) async {
    if (!_isInitialized) await initialize();
    
    try {
      return _gitBindings!.defaultBranch(
        url,
        privateKey != null ? utf8.encode(privateKey) : utf8.encode(''),
        privateKeyPassword ?? '',
      );
    } catch (e) {
      print('获取默认分支失败: $e');
      rethrow;
    }
  }

  /// 生成 RSA 密钥对
  Future<Map<String, String>> generateRsaKeys() async {
    if (!_isInitialized) await initialize();
    
    try {
      final (publicKey, privateKey) = _gitBindings!.generateRsaKeys();
      return {
        'publicKey': publicKey,
        'privateKey': privateKey,
      };
    } catch (e) {
      print('生成密钥失败: $e');
      rethrow;
    }
  }

  /// 使用 dart_git 初始化本地仓库
  Future<void> initLocalRepo(String path) async {
    try {
      await dart_git.GitRepository.init(path);
    } catch (e) {
      print('初始化本地仓库失败: $e');
      rethrow;
    }
  }

  /// 使用 dart_git 添加文件到暂存区
  Future<void> add(String repoPath, String filePattern) async {
    try {
      final repo = await dart_git.GitRepository.load(repoPath);
      await repo.add(filePattern);
      repo.dispose();
    } catch (e) {
      print('添加文件失败: $e');
      rethrow;
    }
  }

  /// 使用 dart_git 提交更改
  Future<void> commit({
    required String repoPath,
    required String message,
    required String authorName,
    required String authorEmail,
  }) async {
    try {
      final repo = await dart_git.GitRepository.load(repoPath);
      final author = dart_git.GitAuthor(authorName, authorEmail);
      await repo.commit(message: message, author: author);
      repo.dispose();
    } catch (e) {
      print('提交失败: $e');
      rethrow;
    }
  }

  /// 完整的同步流程：fetch -> merge -> commit -> push
  Future<void> sync({
    required String localPath,
    required String authorName,
    required String authorEmail,
    String? privateKey,
    String? privateKeyPassword,
  }) async {
    // 1. 获取远程更新
    await fetch(
      localPath: localPath,
      privateKey: privateKey,
      privateKeyPassword: privateKeyPassword,
    );

    // 2. 合并远程分支（使用 dart_git）
    try {
      final repo = await dart_git.GitRepository.load(localPath);
      final author = dart_git.GitAuthor(authorName, authorEmail);
      await repo.mergeCurrentTrackingBranch(author: author);
      repo.dispose();
    } catch (e) {
      print('合并失败（可能没有远程分支）: $e');
      // 继续执行，可能本地没有提交需要合并
    }

    // 3. 添加所有更改
    await add(localPath, '.');

    // 4. 检查是否有更改需要提交
    try {
      final repo = await dart_git.GitRepository.load(localPath);
      final status = await repo.status();
      final hasChanges = status.any((s) => 
        s.status != dart_git.GitFileStatus.unmodified &&
        s.status != dart_git.GitFileStatus.ignored
      );
      repo.dispose();

      if (hasChanges) {
        // 5. 提交
        await commit(
          repoPath: localPath,
          message: 'Sync ${DateTime.now().toIso8601String()}',
          authorName: authorName,
          authorEmail: authorEmail,
        );

        // 6. 推送
        await push(
          localPath: localPath,
          privateKey: privateKey,
          privateKeyPassword: privateKeyPassword,
        );
      }
    } catch (e) {
      print('同步过程出错: $e');
      rethrow;
    }
  }

  /// 获取仓库路径
  Future<String> getRepoPath() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('git_local_path');
    if (path != null && path.isNotEmpty) {
      return path;
    }
    
    final appDir = await getApplicationDocumentsDirectory();
    return p.join(appDir.path, 'notes');
  }

  /// 保存仓库路径
  Future<void> setRepoPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('git_local_path', path);
  }

  /// 检查目录是否是 Git 仓库
  Future<bool> isGitRepo(String path) async {
    try {
      final gitDir = Directory(p.join(path, '.git'));
      return await gitDir.exists();
    } catch (e) {
      return false;
    }
  }
}
