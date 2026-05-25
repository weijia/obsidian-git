import 'dart:io';
import 'package:git2dart/git2dart.dart' as git2;
import 'package:git2dart_binaries/git2dart_binaries.dart' as binaries;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/git_config.dart';

/// Git 服务 - 使用 git2dart (libgit2 FFI)
/// 支持 SSH 和 HTTPS 协议
/// 
/// 重要提示：
/// - Android 上推荐使用 HTTPS + Personal Access Token
/// - SSH 在 Android 上需要复杂的 known_hosts 配置
class GitService {
  static final GitService _instance = GitService._internal();
  factory GitService() => _instance;
  GitService._internal();

  bool _isInitialized = false;

  /// 初始化 Git 服务
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Android 上初始化 libgit2 SSL
      // 这是 git2dart 0.4.0+ 的要求，用于正确处理 HTTPS 证书
      if (Platform.isAndroid) {
        print('正在初始化 Android 平台 SSL...');
        // 先访问 Libgit2 触发初始化
        print('libgit2 version: ${git2.Libgit2.version}');
        // 然后初始化 SSL 证书
        final certPath = await binaries.AndroidSSLHelper.initialize();
        git2.Libgit2.setSSLCertLocations(file: certPath);
        print('Android SSL 初始化完成');
      }

      _isInitialized = true;
      print('GitService 初始化成功');
    } catch (e) {
      print('GitService 初始化失败: $e');
      rethrow;
    }
  }

  /// 构建认证回调
  /// 
  /// 根据认证方式返回相应的 Credentials
  git2.Callbacks _buildCallbacks(GitConfig config) {
    // HTTPS 认证 - 使用 Personal Access Token
    if (config.useHTTPS && config.httpsToken != null && config.httpsToken!.isNotEmpty) {
      print('使用 HTTPS + Personal Access Token 认证');
      return git2.Callbacks(
        credentials: git2.UserPass(
          username: config.username ?? 'git',
          password: config.httpsToken!,
        ),
      );
    }

    // SSH 认证 - 使用内存中的密钥
    if (config.useSSH && config.sshPrivateKey != null && config.sshPrivateKey!.isNotEmpty) {
      print('使用 SSH 密钥认证');
      return git2.Callbacks(
        credentials: git2.KeypairFromMemory(
          username: 'git',
          pubKey: config.sshPublicKey ?? '',
          privateKey: config.sshPrivateKey!,
          passPhrase: config.sshKeyPassword ?? '',
        ),
      );
    }

    // 无认证（公开仓库）
    print('使用无认证方式（公开仓库）');
    return const git2.Callbacks();
  }

  /// 转换 SSH URL 为 HTTPS URL
  /// 
  /// 例如：git@gitee.com:user/repo.git -> https://gitee.com/user/repo.git
  String _convertSshToHttps(String url) {
    // SCP 风格 SSH URL: git@hostname:path
    final scpMatch = RegExp(r'^git@([^:]+):(.+)$').firstMatch(url);
    if (scpMatch != null) {
      final host = scpMatch.group(1)!;
      final path = scpMatch.group(2)!;
      return 'https://$host/$path';
    }
    
    // 已经是 HTTPS 或 HTTP URL
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    
    // ssh:// 协议
    if (url.startsWith('ssh://')) {
      final uri = Uri.parse(url);
      return 'https://${uri.host}${uri.path}';
    }
    
    return url;
  }

  /// 获取处理后的 URL
  /// 
  /// 如果使用 HTTPS 认证，自动将 SSH URL 转换为 HTTPS URL
  String _getProcessedUrl(GitConfig config) {
    if (config.useHTTPS) {
      return _convertSshToHttps(config.repoUrl);
    }
    return config.repoUrl;
  }

  /// 克隆仓库
  Future<void> clone({
    required GitConfig config,
    required String localPath,
  }) async {
    if (!_isInitialized) await initialize();

    final url = _getProcessedUrl(config);
    print('克隆仓库: $url -> $localPath');

    final parentDir = Directory(localPath).parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    try {
      git2.Repository.clone(
        url: url,
        localPath: localPath,
        callbacks: _buildCallbacks(config),
      );
      print('克隆成功');
    } catch (e) {
      print('克隆失败: $e');
      rethrow;
    }
  }

  /// 获取远程更新
  Future<void> fetch({
    required GitConfig config,
    required String localPath,
    String remoteName = 'origin',
  }) async {
    if (!_isInitialized) await initialize();

    final repo = git2.Repository.open(localPath);
    
    // 如果需要，更新远程 URL
    final url = _getProcessedUrl(config);
    final currentUrl = repo.config.getString('remote.$remoteName.url');
    if (currentUrl != url) {
      print('更新远程 URL: $currentUrl -> $url');
      git2.Remote.setUrl(repo: repo, remote: remoteName, url: url);
    }

    final remote = git2.Remote.lookup(repo: repo, name: remoteName);

    print('获取远程更新...');
    try {
      remote.fetch(
        callbacks: _buildCallbacks(config),
      );
      print('获取成功');
    } catch (e) {
      print('获取失败: $e');
      rethrow;
    } finally {
      remote.free();
      repo.free();
    }
  }

  /// 推送
  Future<void> push({
    required GitConfig config,
    required String localPath,
    String remoteName = 'origin',
  }) async {
    if (!_isInitialized) await initialize();

    final repo = git2.Repository.open(localPath);
    
    // 如果需要，更新远程 URL
    final url = _getProcessedUrl(config);
    final currentUrl = repo.config.getString('remote.$remoteName.url');
    if (currentUrl != url) {
      print('更新远程 URL: $currentUrl -> $url');
      git2.Remote.setUrl(repo: repo, remote: remoteName, url: url);
    }

    final remote = git2.Remote.lookup(repo: repo, name: remoteName);

    print('推送到远程...');
    try {
      remote.push(
        callbacks: _buildCallbacks(config),
      );
      print('推送成功');
    } catch (e) {
      print('推送失败: $e');
      rethrow;
    } finally {
      remote.free();
      repo.free();
    }
  }

  /// 初始化本地仓库
  void initLocalRepo(String path) {
    git2.Repository.init(path: path);
  }

  /// 添加文件
  void add(String repoPath, String filePattern) {
    final repo = git2.Repository.open(repoPath);
    final index = repo.index;
    if (filePattern == '.') {
      // 遍历添加所有变更的文件
      for (final file in repo.status.keys) {
        index.add(file);
      }
    } else {
      index.add(filePattern);
    }
    index.write();
    repo.free();
  }

  /// 提交
  void commit({
    required String repoPath,
    required String message,
    required String authorName,
    required String authorEmail,
  }) {
    final repo = git2.Repository.open(repoPath);

    // 创建签名
    final signature = git2.Signature.create(
      name: authorName,
      email: authorEmail,
      time: DateTime.now(),
    );

    // 获取所有有变更的文件
    final changedFiles = repo.status.keys.toList();
    if (changedFiles.isEmpty) {
      repo.free();
      return;
    }

    // 使用 createCommitOnHead 扩展方法
    repo.createCommitOnHead(
      changedFiles,
      signature,
      signature,
      message,
    );

    repo.free();
  }

  /// 获取仓库状态
  Map<String, Set<git2.GitStatus>> status(String repoPath) {
    final repo = git2.Repository.open(repoPath);
    final status = repo.status;
    repo.free();
    return status;
  }

  /// 获取提交历史
  List<git2.Commit> log(String repoPath, {int limit = 50}) {
    final repo = git2.Repository.open(repoPath);
    List<git2.Commit> commits;

    if (!repo.isEmpty) {
      final walker = git2.RevWalk(repo);
      walker.pushHead();
      commits = walker.walk(limit: limit);
    } else {
      commits = [];
    }

    repo.free();
    return commits;
  }

  /// 拉取并合并
  Future<void> pull({
    required GitConfig config,
    required String localPath,
    String remoteName = 'origin',
  }) async {
    if (!_isInitialized) await initialize();

    final repo = git2.Repository.open(localPath);
    
    // 获取远程更新
    await fetch(config: config, localPath: localPath, remoteName: remoteName);

    // 合并远程分支到 HEAD
    if (!repo.isEmpty) {
      final remoteRef = 'refs/remotes/$remoteName/${config.branch}';
      
      // 使用 RevParse 将引用名解析为 Commit
      final revParse = git2.RevParse.single(
        repo: repo, 
        spec: remoteRef,
      );
      
      if (revParse is git2.Commit) {
        // 使用 AnnotatedCommit 进行合并
        final annotatedCommit = git2.AnnotatedCommit.lookup(repo: repo, oid: revParse.oid);
        git2.Merge.commit(
          repo: repo,
          commit: annotatedCommit,
        );
        annotatedCommit.free();
      }
    }

    repo.free();
  }

  /// 同步结果
  static SyncResult success() => SyncResult(success: true);
  static SyncResult failure(String error) => SyncResult(success: false, error: error);

  /// 同步仓库（添加、提交、拉取、推送）
  /// 
  /// 这是旧版 API 的兼容方法，建议使用新的独立方法
  Future<SyncResult> sync({
    required String localPath,
    required String authorName,
    required String authorEmail,
    String? publicKey,
    String? privateKey,
    String? privateKeyPassword,
  }) async {
    try {
      // 创建临时配置
      final config = GitConfig(
        repoUrl: '',
        localPath: localPath,
        username: authorName,
        email: authorEmail,
        sshPublicKey: publicKey,
        sshPrivateKey: privateKey,
        sshKeyPassword: privateKeyPassword,
        authMethod: privateKey != null ? AuthMethod.ssh : AuthMethod.https,
      );

      // 添加所有更改
      add(localPath, '.');

      // 提交
      commit(
        repoPath: localPath,
        message: 'Sync from Obsidian Git',
        authorName: authorName,
        authorEmail: authorEmail,
      );

      // 拉取
      await pull(config: config, localPath: localPath);

      // 推送
      await push(config: config, localPath: localPath);

      return SyncResult(success: true);
    } catch (e) {
      return SyncResult(success: false, error: e.toString());
    }
  }

  /// 获取仓库路径
  Future<String> getRepoPath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return p.join(appDir.path, 'notes-repo');
  }

  /// 设置仓库路径（现在只是保存到配置，实际路径由 getRepoPath 决定）
  Future<void> setRepoPath(String path) async {
    // 路径现在由 getRepoPath 统一管理
    // 这个方法保留用于兼容性
  }

  /// 检查路径是否是 Git 仓库
  bool isGitRepo(String path) {
    try {
      final repo = git2.Repository.open(path);
      repo.free();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 释放资源
  void dispose() {
    // git2dart 会自动管理资源
  }
}

/// 同步结果
class SyncResult {
  final bool success;
  final String? error;

  const SyncResult({
    required this.success,
    this.error,
  });
}
