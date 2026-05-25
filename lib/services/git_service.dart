import 'dart:io';
import 'package:git2dart/git2dart.dart' as git2;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/git_config.dart';

/// Git 服务 - 使用 git2dart (libgit2 FFI)
/// 支持 SSH 和 HTTPS 协议，DNS 走系统原生 API
class GitService {
  static final GitService _instance = GitService._internal();
  factory GitService() => _instance;
  GitService._internal();

  bool _isInitialized = false;

  /// 初始化 Git 服务（Android 上需要调用 androidInitialize）
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Android 上初始化 libgit2 SSL 证书
      if (Platform.isAndroid) {
        await git2.PlatformSpecific.androidInitialize();
      }
      _isInitialized = true;
    } catch (e) {
      print('GitService 初始化失败: $e');
      rethrow;
    }
  }

  /// 构建 SSH 认证回调
  git2.Callbacks _buildCallbacks({
    required String? publicKey,
    required String? privateKey,
    String? passphrase,
  }) {
    if (privateKey != null && privateKey.isNotEmpty) {
      return git2.Callbacks(
        credentials: git2.KeypairFromMemory(
          username: 'git',
          pubKey: publicKey ?? '',
          privateKey: privateKey,
          passPhrase: passphrase ?? '',
        ),
      );
    }
    return const git2.Callbacks();
  }

  /// 克隆仓库
  Future<void> clone({
    required String url,
    required String localPath,
    String? publicKey,
    String? privateKey,
    String? privateKeyPassword,
  }) async {
    if (!_isInitialized) await initialize();

    try {
      // 确保目标目录的父目录存在
      final parentDir = Directory(localPath).parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      git2.Repository.clone(
        url: url,
        localPath: localPath,
        callbacks: _buildCallbacks(
          publicKey: publicKey,
          privateKey: privateKey,
          passphrase: privateKeyPassword,
        ),
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
    String? publicKey,
    String? privateKey,
    String? privateKeyPassword,
  }) async {
    if (!_isInitialized) await initialize();

    try {
      final repo = git2.Repository.open(localPath);
      final remote = git2.Remote.lookup(repo: repo, name: remoteName);
      remote.fetch(
        callbacks: _buildCallbacks(
          publicKey: publicKey,
          privateKey: privateKey,
          passphrase: privateKeyPassword,
        ),
      );
      remote.free();
      repo.free();
    } catch (e) {
      print('获取更新失败: $e');
      rethrow;
    }
  }

  /// 推送到远程
  Future<void> push({
    required String localPath,
    String remoteName = 'origin',
    String? publicKey,
    String? privateKey,
    String? privateKeyPassword,
  }) async {
    if (!_isInitialized) await initialize();

    try {
      final repo = git2.Repository.open(localPath);
      final remote = git2.Remote.lookup(repo: repo, name: remoteName);
      remote.push(
        callbacks: _buildCallbacks(
          publicKey: publicKey,
          privateKey: privateKey,
          passphrase: privateKeyPassword,
        ),
      );
      remote.free();
      repo.free();
    } catch (e) {
      print('推送失败: $e');
      rethrow;
    }
  }

  /// 使用 git2dart 初始化本地仓库
  void initLocalRepo(String path) {
    git2.Repository.init(path: path);
  }

  /// 添加文件到暂存区
  void add(String repoPath, String filePattern) {
    final repo = git2.Repository.open(repoPath);
    final index = repo.index;
    if (filePattern == '.') {
      // 添加所有文件
      index.addAll(repo.status.keys.toList());
    } else {
      index.add(filePattern);
    }
    index.write();
    repo.free();
  }

  /// 提交更改
  void commit({
    required String repoPath,
    required String message,
    required String authorName,
    required String authorEmail,
  }) {
    final repo = git2.Repository.open(repoPath);
    repo.index.write();

    final signature = git2.Signature.create(
      name: authorName,
      email: authorEmail,
      time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      offset: 0,
    );

    // 获取所有暂存的文件
    final stagedFiles = <String>[];
    for (final entry in repo.status.entries) {
      if (entry.value.contains(git2.GitStatus.indexNew) ||
          entry.value.contains(git2.GitStatus.indexModified) ||
          entry.value.contains(git2.GitStatus.indexDeleted) ||
          entry.value.contains(git2.GitStatus.indexRenamed) ||
          entry.value.contains(git2.GitStatus.indexTypeChange)) {
        stagedFiles.add(entry.key);
      }
    }

    if (stagedFiles.isNotEmpty) {
      repo.createCommitOnHead(stagedFiles, signature, signature, message);
    }
    repo.free();
  }

  /// 检查是否有未提交的更改
  bool hasChanges(String repoPath) {
    final repo = git2.Repository.open(repoPath);
    final status = repo.status;
    repo.free();

    for (final entry in status.entries) {
      if (entry.value.contains(git2.GitStatus.indexNew) ||
          entry.value.contains(git2.GitStatus.indexModified) ||
          entry.value.contains(git2.GitStatus.indexDeleted) ||
          entry.value.contains(git2.GitStatus.indexRenamed) ||
          entry.value.contains(git2.GitStatus.indexTypeChange) ||
          entry.value.contains(git2.GitStatus.wtNew) ||
          entry.value.contains(git2.GitStatus.wtModified) ||
          entry.value.contains(git2.GitStatus.wtDeleted) ||
          entry.value.contains(git2.GitStatus.wtRenamed) ||
          entry.value.contains(git2.GitStatus.wtTypeChange)) {
        return true;
      }
    }
    return false;
  }

  /// 完整的同步流程：fetch -> merge -> add -> commit -> push
  Future<SyncResult> sync({
    required String localPath,
    required String authorName,
    required String authorEmail,
    String? publicKey,
    String? privateKey,
    String? privateKeyPassword,
  }) async {
    // 1. 获取远程更新
    await fetch(
      localPath: localPath,
      publicKey: publicKey,
      privateKey: privateKey,
      privateKeyPassword: privateKeyPassword,
    );

    // 2. 合并远程分支
    try {
      final repo = git2.Repository.open(localPath);
      final remote = git2.Remote.lookup(repo: repo, name: 'origin');

      // 获取远程 HEAD
      final remoteHead = git2.Reference.lookup(
        repo: repo,
        name: 'refs/remotes/origin/${repo.head.shorthand}',
      );

      if (remoteHead != null) {
        final analysis = git2.Merge.analysis(
          repo: repo,
          theirHead: remoteHead.target,
        );

        if (analysis.result.contains(git2.GitMergeAnalysis.normal) ||
            analysis.result.contains(git2.GitMergeAnalysis.upToDate)) {
          // 执行合并
          final commit = git2.AnnotatedCommit.lookup(
            repo: repo,
            oid: remoteHead.target,
          );
          git2.Merge.commit(repo: repo, commit: commit);
          repo.stateCleanup();
        }
      }

      remote.free();
      repo.free();
    } catch (e) {
      print('合并失败（可能没有远程分支）: $e');
    }

    // 3. 添加所有更改
    try {
      add(localPath, '.');
    } catch (e) {
      print('添加文件失败: $e');
    }

    // 4. 检查是否有更改需要提交
    try {
      if (hasChanges(localPath)) {
        // 5. 提交
        commit(
          repoPath: localPath,
          message: 'Sync ${DateTime.now().toIso8601String()}',
          authorName: authorName,
          authorEmail: authorEmail,
        );

        // 6. 推送
        await push(
          localPath: localPath,
          publicKey: publicKey,
          privateKey: privateKey,
          privateKeyPassword: privateKeyPassword,
        );
      }
    } catch (e) {
      print('同步过程出错: $e');
      return SyncResult(success: false, error: e.toString());
    }

    return SyncResult(success: true);
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
  bool isGitRepo(String path) {
    try {
      git2.Repository.open(path);
      return true;
    } catch (e) {
      return false;
    }
  }
}

/// 同步结果
class SyncResult {
  final bool success;
  final String? error;

  const SyncResult({required this.success, this.error});
}

/// Git SSH 认证异常
class GitSshRequiredException implements Exception {
  final String message;
  GitSshRequiredException(this.message);
  @override
  String toString() => message;
}

/// Git 认证异常
class GitAuthException implements Exception {
  final String message;
  GitAuthException(this.message);
  @override
  String toString() => message;
}
