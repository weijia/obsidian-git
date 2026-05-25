import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:git2dart/git2dart.dart' as git2;
import 'package:git2dart_binaries/git2dart_binaries.dart';
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

  /// SSH certificate check 原生回调指针
  /// 
  /// 使用 Int (平台相关) 而不是 Int32，以匹配 git2dart_binaries 的定义
  static late Pointer<NativeFunction<
      Int Function(Pointer<git_cert>, Int, Pointer<Char>, Pointer<Void>)>>
      _certCheckFnPtr;

  /// 初始化 Git 服务（Android 上需要调用 androidInitialize）
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Android 上初始化 libgit2 SSL 证书
      if (Platform.isAndroid) {
        await git2.PlatformSpecific.androidInitialize();
      }

      // 初始化 certificate_check 回调指针
      _initializeCertCheckCallback();

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

  /// 初始化 certificate_check 回调
  /// 
  /// 将 Dart 函数转换为原生函数指针，以便在 libgit2 中使用。
  /// 返回 0 表示信任所有主机密钥。
  static void _initializeCertCheckCallback() {
    _certCheckFnPtr = Pointer.fromFunction<
        Int Function(Pointer<git_cert>, Int, Pointer<Char>,
            Pointer<Void>)>(_certCheckCallback, 0);
  }

  /// Certificate check 回调实现
  static int _certCheckCallback(
    Pointer<git_cert> cert,
    int valid,
    Pointer<Char> host,
    Pointer<Void> payload,
  ) {
    final hostStr = host.cast<Utf8>().toDartString();
    print('SSH 证书检查: host=$hostStr, valid=$valid -> 信任');
    return 0;  // 返回 0 表示信任此主机
  }

  /// 设置 SSH known_hosts
  static Future<void> _setupSshKnownHosts() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final sshDir = Directory(p.join(appDir.path, '.ssh'));
      if (!await sshDir.exists()) {
        await sshDir.create(recursive: true);
      }
      final knownHosts = File(p.join(sshDir.path, 'known_hosts'));
      if (!await knownHosts.exists()) {
        await knownHosts.create();
      }
      print('SSH known_hosts 目录: ${sshDir.path}');
    } catch (e) {
      print('设置 SSH known_hosts 失败: $e');
    }
  }

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
    String? originalHost,
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

  /// 在 Android 上执行 clone，自动注入 certificate_check
  Future<void> _androidClone({
    required String resolvedUrl,
    required String localPath,
    required String? publicKey,
    required String? privateKey,
    String? passphrase,
    required String originalUrl,
  }) async {
    // 分配 git_clone_options
    final cloneOpts = calloc<git_clone_options>();
    libgit2.git_clone_options_init(cloneOpts, GIT_CLONE_OPTIONS_VERSION);

    // 分配 git_fetch_options
    final fetchOpts = calloc<git_fetch_options>();
    libgit2.git_fetch_options_init(fetchOpts, GIT_FETCH_OPTIONS_VERSION);

    // 设置 certificate_check 回调 - 关键！
    fetchOpts.ref.callbacks.certificate_check = _certCheckFnPtr;

    // 设置 credentials 回调
    if (privateKey != null && privateKey.isNotEmpty) {
      // 使用 SSH 密钥，需要设置 credentials 回调
      // 由于 git2dart 的 credentials 处理比较复杂，
      // 我们暂时依赖 git2dart 的默认行为
    }

    // 分配输出指针
    final outRepo = calloc<Pointer<git_repository>>();

    try {
      // 执行 clone
      final error = libgit2.git_clone(
        outRepo,
        resolvedUrl.toNativeUtf8(),
        localPath.toNativeUtf8(),
        cloneOpts,
      );

      if (error != 0) {
        final err = libgit2.git_error_last();
        final msg = err.ref.message.cast<Utf8>().toDartString();
        throw Exception('Clone 失败 (错误码: $error): $msg');
      }

      // 克隆成功后，如果 URL 被解析了，更新 remote URL 回原始域名
      if (resolvedUrl != originalUrl) {
        try {
          final repo = outRepo.value;
          git2.Remote.setUrl(repo: repo, remote: 'origin', url: originalUrl);
        } catch (e) {
          print('更新 remote URL 失败: $e');
        }
      }

      // 释放 repo
      if (outRepo.value != nullptr) {
        libgit2.git_repository_free(outRepo.value);
      }
    } finally {
      calloc.free(cloneOpts);
      calloc.free(fetchOpts);
      calloc.free(outRepo);
    }
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

      // Android 上使用自定义 clone 实现
      if (Platform.isAndroid) {
        await _androidClone(
          resolvedUrl: resolvedUrl,
          localPath: localPath,
          publicKey: publicKey,
          privateKey: privateKey,
          passphrase: privateKeyPassword,
          originalUrl: url,
        );
      } else {
        // 其他平台使用 git2dart 默认实现
        git2.Repository.clone(
          url: resolvedUrl,
          localPath: localPath,
          callbacks: _buildCallbacks(
            publicKey: publicKey,
            privateKey: privateKey,
            passphrase: privateKeyPassword,
            originalHost: url,
          ),
        );
      }
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

      if (Platform.isAndroid) {
        // Android 上需要设置 certificate_check
        final fetchOpts = calloc<git_fetch_options>();
        libgit2.git_fetch_options_init(fetchOpts, GIT_FETCH_OPTIONS_VERSION);
        fetchOpts.ref.callbacks.certificate_check = _certCheckFnPtr;

        // 使用底层 FFI 执行 fetch
        final error = libgit2.git_remote_fetch(
          remote.ref,
          nullptr,  // refspecs
          fetchOpts,  // 传入自定义 options
          nullptr,  // reflog message
        );

        calloc.free(fetchOpts);

        if (error != 0) {
          final err = libgit2.git_error_last();
          final msg = err.ref.message.cast<Utf8>().toDartString();
          throw Exception('Fetch 失败 (错误码: $error): $msg');
        }
      } else {
        remote.fetch(
          callbacks: _buildCallbacks(
            publicKey: publicKey,
            privateKey: privateKey,
            passphrase: privateKeyPassword,
            originalHost: remoteUrl,
          ),
        );
      }

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
          originalHost: remoteUrl,
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
