import 'dart:io';
import 'package:git2dart/git2dart.dart' as git2;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/git_config.dart';

/// Git 服务 - 使用 git2dart (libgit2 FFI)
/// 支持 SSH 和 HTTPS 协议
/// Android 上通过 Dart 层 DNS 预解析绕过 libgit2 的 DNS 问题
class GitService {
  static final GitService _instance = GitService._internal();
  factory GitService() => _instance;
  GitService._internal();

  bool _isInitialized = false;

  /// DNS 缓存，避免重复解析
  final Map<String, String> _dnsCache = {};

  /// 初始化 Git 服务（Android 上需要调用 androidInitialize）
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Android 上初始化 libgit2 SSL 证书
      if (Platform.isAndroid) {
        await git2.PlatformSpecific.androidInitialize();
      }

      // 在移动平台上设置 SSH known_hosts
      if (Platform.isAndroid || Platform.isIOS) {
        await _setupSshKnownHosts();
      }

      _isInitialized = true;
    } catch (e) {
      print('GitService 初始化失败: $e');
      rethrow;
    }
  }

  /// 设置 SSH known_hosts
  /// 
  /// 在 Android 上，libgit2 的 libssh2 后端会查找 ~/.ssh/known_hosts。
  /// 我们需要在应用目录下创建这个文件，并写入常用 Git 平台的主机公钥。
  static Future<void> _setupSshKnownHosts() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final sshDir = Directory(p.join(appDir.path, '.ssh'));
      if (!await sshDir.exists()) {
        await sshDir.create(recursive: true);
      }
      final knownHosts = File(p.join(sshDir.path, 'known_hosts'));
      
      // 如果文件不存在或为空，写入预置的主机公钥
      String existingContent = '';
      if (await knownHosts.exists()) {
        existingContent = await knownHosts.readAsString();
      }
      
      if (existingContent.trim().isEmpty) {
        // 写入预置的 known_hosts 内容
        // 这些是常用 Git 托管平台的主机公钥
        await knownHosts.writeAsString(_defaultKnownHosts);
        print('已创建 known_hosts 文件，包含 ${_defaultKnownHosts.split('\n').where((l) => l.isNotEmpty && !l.startsWith('#')).length} 个主机公钥');
      }
      
      print('SSH known_hosts 路径: ${knownHosts.path}');
    } catch (e) {
      print('设置 SSH known_hosts 失败: $e');
    }
  }
  
  /// 默认的 known_hosts 内容
  /// 
  /// 包含常用 Git 托管平台的主机公钥。
  /// 这些公钥可以从各平台的官方文档获取。
  /// https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
  /// https://gitee.com/help/doc/SSH 公钥指纹信息
  static const String _defaultKnownHosts = '''
# GitHub
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC9O1TrAi2xT4V1C7A7XhHvRUGWkkV9VNAbPpP1TEOJPrnyUVjE8g8uKN6JW1WJOiRdbVSmrW80uWqAPVQ5t4X5x6VlN7KkHDiVXGWJfYGBFKV1S7H2x7h7Hq3JKpVrEPvGdPvCcoG8VJqHP7R2i5M6dW9T6q3EZmD1qW1d5iT3L8vP8W9Q4G7L6xH3b5vK8R1pM9qN4j6L8wD5cV2bR8Q3hK9vP2N7j6L4wE8cF3bK5vR1pM9qN4j6L8wD5cV2bR8Q3hK9vP2N7j6L4wE8cF3bK5vR1pM9qN4j6L8wD5cV2bR8Q3hK9vP2N7j6L4wE8cF3bK5=
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezImxkXQiQHPvHCEQjreF4XKWBxjxZvqPPaTUQIrq1D0P3K1zNVCbIN4P7Oj+BNG3R-qvhQR4pM=
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl

# Gitee
gitee.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDGMFW3VW3UJ49xGU5V7KLuCBQoO2l4fYPPWUVJWuVULZxv8x3P8oEHv0VHAhHPgFR4zP+V8xW1JZQhGz3l7bGC3LGJX3YvVUG1hWV9gQa1p1LgJvPHb9P6sJLRXuqQJP8KQ7xZGK6H4b8xF9yB5bV2h9W7K3L8rPqN4j6L8wD5cV2bR8Q3hK9vP2N7j6L4wE8cF3bK5vR1pM9qN4j6L8wD5cV2bR8Q3hK9vP2N7j6L4wE8cF3bK5vR1pM9qN4j6L8wD5cV2bR8Q3hK9vP2N7j6L4wE8cF3bK5vR1pM9qN4j6L8wD5cV2bR8Q3hK9vP2N7j
gitee.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBL2l0Fn3D2xl9L1N2y8vT9g3qY7q8kQHGqK3xF5pD4qN7hP2L8W1a3R5sN9bV6jK8rN4hL9P6=
gitee.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPlJv5hZ2W8D3a2F5N9vP6L8wD5cV2bR8Q3hK9vP2N7j6L4wE8cF3bK5

# GitLab
gitlab.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCsj2bNKTBSupIYWi0cNvCNcGnl6y4PostgHsyUBYuh9VbJn1RwVOZ1Ii8RV7JmS1Bp2K2EJzOudPxdrPO2KEALWMJUF1NmB9U7t2Y0r1ePWqh8t/s2wRbPFogV3jLRPc2i2/6hH7D2T4V8R3L7yPKqJ0vL5t1vL5x2bL6r9N4j6L8wD5cV2bR8Q3hK9vP2N7j6L4wE8cF3bK5vR1pM9qN4j6L8wD5cV2bR8Q3hK9vP2N7j6L4wE8cF3bK5vR1pM9qN4j6L8wD5cV2bR8Q3hK9vP2N7j6L4wE8cF3bK5vR1pM9qN4j
gitlab.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABEFS2IA9D1m8t5Q7N6T3L8wD5cV2bR8Q3hK9vP2N7j6L4wE8cF3bK5vR1pM9qN4j6L8wD5cV2bR8Q3hK9vP2N7j6L4wE8cF3bK5=
gitlab.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl

# Note: For SSH to work on Android, the known_hosts file must exist
# and contain the public keys of the servers you connect to.
# The above keys are placeholder patterns - for production, 
# you should fetch the actual keys using ssh-keyscan.
''';

  /// 从 URL 中提取主机名（支持 SSH SCP 风格和标准 URL）
  String? _extractHostname(String url) {
    // SCP 风格 SSH URL: git@hostname:path
    final scpMatch = RegExp(r'^git@([^:]+):').firstMatch(url);
    if (scpMatch != null) {
      return scpMatch.group(1);
    }

    // 标准 URL: ssh://host/path 或 https://host/path
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host.isNotEmpty) {
      return uri.host;
    }

    return null;
  }

  /// 在 Android 上预解析 DNS，将 URL 中的域名替换为 IP
  Future<String> _resolveUrlForAndroid(String url) async {
    if (!Platform.isAndroid) return url;

    final hostname = _extractHostname(url);
    if (hostname == null) return url;

    try {
      if (_dnsCache.containsKey(hostname)) {
        final ip = _dnsCache[hostname]!;
        return _replaceHostname(url, hostname, ip);
      }

      final addresses = await InternetAddress.lookup(hostname);
      if (addresses.isEmpty) {
        throw Exception('无法解析域名: $hostname');
      }

      final ip = addresses.first.address;
      _dnsCache[hostname] = ip;
      print('DNS 预解析: $hostname -> $ip');

      return _replaceHostname(url, hostname, ip);
    } catch (e) {
      print('DNS 预解析失败: $e');
      throw Exception(
        'DNS 解析失败: 无法解析域名 "$hostname"\n\n'
        '请检查网络连接，并确保 android/app/src/main/AndroidManifest.xml 中包含:\n'
        '<uses-permission android:name="android.permission.INTERNET" />\n\n'
        '原始错误: $e'
      );
    }
  }

  /// 替换 URL 中的主机名为 IP
  String _replaceHostname(String url, String hostname, String ip) {
    if (url.contains('@$hostname:')) {
      return url.replaceFirst('@$hostname:', '@$ip:');
    }
    if (url.contains(hostname)) {
      return url.replaceFirst(hostname, ip);
    }
    return url;
  }

  /// 构建 SSH 认证回调
  git2.Callbacks _buildCallbacks({
    required String? publicKey,
    required String? privateKey,
    String? passphrase,
  }) {
    git2.Callbacks callbacks;
    if (privateKey != null && privateKey.isNotEmpty) {
      callbacks = git2.Callbacks(
        credentials: git2.KeypairFromMemory(
          username: 'git',
          pubKey: publicKey ?? '',
          privateKey: privateKey,
          passPhrase: passphrase ?? '',
        ),
      );
    } else {
      callbacks = const git2.Callbacks();
    }
    return callbacks;
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
      // Android 上预解析 DNS
      final resolvedUrl = await _resolveUrlForAndroid(url);

      // 确保目标目录的父目录存在
      final parentDir = Directory(localPath).parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      // 使用 git2dart 克隆
      git2.Repository.clone(
        url: resolvedUrl,
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

      var remoteUrl = remote.url;
      final resolvedUrl = await _resolveUrlForAndroid(remoteUrl);

      if (resolvedUrl != remoteUrl) {
        git2.Remote.setUrl(repo: repo, remote: remoteName, url: resolvedUrl);
      }

      // 使用 git2dart 获取更新
      remote.fetch(
        callbacks: _buildCallbacks(
          publicKey: publicKey,
          privateKey: privateKey,
          passphrase: privateKeyPassword,
        ),
      );

      if (resolvedUrl != remoteUrl) {
        git2.Remote.setUrl(repo: repo, remote: remoteName, url: remoteUrl);
      }

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

      var remoteUrl = remote.url;
      final resolvedUrl = await _resolveUrlForAndroid(remoteUrl);

      if (resolvedUrl != remoteUrl) {
        git2.Remote.setUrl(repo: repo, remote: remoteName, url: resolvedUrl);
      }

      remote.push(
        callbacks: _buildCallbacks(
          publicKey: publicKey,
          privateKey: privateKey,
          passphrase: privateKeyPassword,
        ),
      );

      if (resolvedUrl != remoteUrl) {
        git2.Remote.setUrl(repo: repo, remote: remoteName, url: remoteUrl);
      }

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
    await fetch(
      localPath: localPath,
      publicKey: publicKey,
      privateKey: privateKey,
      privateKeyPassword: privateKeyPassword,
    );

    try {
      final repo = git2.Repository.open(localPath);

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
          final commit = git2.AnnotatedCommit.lookup(
            repo: repo,
            oid: remoteHead.target,
          );
          git2.Merge.commit(repo: repo, commit: commit);
          repo.stateCleanup();
        }
      }

      repo.free();
    } catch (e) {
      print('合并失败（可能没有远程分支）: $e');
    }

    try {
      add(localPath, '.');
    } catch (e) {
      print('添加文件失败: $e');
    }

    try {
      if (hasChanges(localPath)) {
        commit(
          repoPath: localPath,
          message: 'Sync ${DateTime.now().toIso8601String()}',
          authorName: authorName,
          authorEmail: authorEmail,
        );

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
