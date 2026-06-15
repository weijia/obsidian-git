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
  
  /// 日志回调
  void Function(String)? onLog;
  
  void _log(String message) {
    final line = '[Git] $message';
    print(line);
    onLog?.call(line);
  }

  /// 初始化 Git 服务
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _log('开始初始化 Git 服务...');
      // Android 上初始化 libgit2 SSL
      // 这是 git2dart 0.4.0+ 的要求，用于正确处理 HTTPS 证书
      if (Platform.isAndroid) {
        _log('Android 平台，初始化 SSL...');
        // 先访问 Libgit2 触发初始化
        _log('libgit2 version: ${git2.Libgit2.version}');
        // 然后初始化 SSL 证书
        final certPath = await binaries.AndroidSSLHelper.initialize();
        git2.Libgit2.setSSLCertLocations(file: certPath);
        _log('SSL 证书路径: $certPath');
      }

      _isInitialized = true;
      _log('Git 服务初始化成功');
    } catch (e) {
      _log('Git 服务初始化失败: $e');
      rethrow;
    }
  }

  /// 构建认证回调
  ///
  /// 根据认证方式返回相应的 Credentials
  /// 支持从 GitConfig 或 GitRemote 获取认证信息
  git2.Callbacks _buildCallbacks(GitConfig config, {GitRemote? remote}) {
    // 优先使用 remote 的配置
    final useHTTPS = remote?.useHTTPS ?? config.useHTTPS;
    final httpsToken = remote?.httpsToken ?? config.httpsToken;
    final sshPrivateKey = remote?.sshPrivateKey ?? config.sshPrivateKey;
    final sshPublicKey = remote?.sshPublicKey ?? config.sshPublicKey;
    final sshKeyPassword = remote?.sshKeyPassword ?? config.sshKeyPassword;
    final username = config.username ?? 'git';
    
    // HTTPS 认证 - 使用 Personal Access Token
    if (useHTTPS && httpsToken != null && httpsToken.isNotEmpty) {
      _log('认证方式: HTTPS + Personal Access Token');
      _log('  用户名: $username');
      _log('  Token: ${httpsToken.substring(0, 4)}...${httpsToken.length > 8 ? httpsToken.substring(httpsToken.length - 4) : ""}');
      return git2.Callbacks(
        credentials: git2.UserPass(
          username: username,
          password: httpsToken,
        ),
      );
    }

    // SSH 认证 - 使用内存中的密钥
    if (!useHTTPS && sshPrivateKey != null && sshPrivateKey.isNotEmpty) {
      _log('认证方式: SSH 密钥');
      return git2.Callbacks(
        credentials: git2.KeypairFromMemory(
          username: 'git',
          pubKey: sshPublicKey ?? '',
          privateKey: sshPrivateKey,
          passPhrase: sshKeyPassword ?? '',
        ),
      );
    }

    // 无认证（公开仓库）
    _log('认证方式: 无认证（公开仓库）');
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
  String _getProcessedUrl(GitConfig config, {GitRemote? remote}) {
    final url = remote?.url ?? config.repoUrl;
    final useHTTPS = remote?.useHTTPS ?? config.useHTTPS;
    if (useHTTPS) {
      return _convertSshToHttps(url);
    }
    return url;
  }

  /// 克隆仓库
  Future<void> clone({
    required GitConfig config,
    required String localPath,
  }) async {
    if (!_isInitialized) await initialize();

    final remote = config.primaryRemote;
    final url = _getProcessedUrl(config, remote: remote);
    _log('========== 克隆仓库 ==========');
    _log('远程 URL: $url');
    _log('本地路径: $localPath');
    _log('分支: ${config.branch}');

    final parentDir = Directory(localPath).parent;
    if (!await parentDir.exists()) {
      _log('创建父目录: ${parentDir.path}');
      await parentDir.create(recursive: true);
    }

    try {
      _log('开始克隆...');
      final stopwatch = Stopwatch()..start();
      git2.Repository.clone(
        url: url,
        localPath: localPath,
        callbacks: _buildCallbacks(config, remote: remote),
      );
      stopwatch.stop();
      _log('克隆成功！耗时: ${stopwatch.elapsedMilliseconds}ms');
      
      // 列出克隆的文件
      final repoDir = Directory(localPath);
      final files = await repoDir.list(recursive: true).where((f) => f is File).toList();
      _log('克隆了 ${files.length} 个文件');
    } catch (e) {
      _log('克隆失败: $e');
      rethrow;
    }
  }

  /// 获取远程更新
  Future<void> fetch({
    required GitConfig config,
    required String localPath,
    String? remoteName,
  }) async {
    if (!_isInitialized) await initialize();

    final remote = config.remotes.firstWhere(
      (r) => r.name == (remoteName ?? config.defaultRemote),
      orElse: () => config.primaryRemote ?? GitRemote(name: remoteName ?? 'origin', url: config.repoUrl),
    );
    
    _log('========== Fetch ==========');
    _log('本地路径: $localPath');
    _log('远程名称: ${remote.name}');

    final repo = git2.Repository.open(localPath);

    // 如果需要，更新远程 URL
    final url = _getProcessedUrl(config, remote: remote);
    final configEntry = repo.config['remote.${remote.name}.url'];
    final currentUrl = configEntry.value;
    if (currentUrl != url) {
      _log('更新远程 URL: $currentUrl -> $url');
      git2.Remote.setUrl(repo: repo, remote: remote.name, url: url);
    } else {
      _log('远程 URL: $url');
    }

    final gitRemote = git2.Remote.lookup(repo: repo, name: remote.name);

    _log('开始获取远程更新...');
    try {
      final stopwatch = Stopwatch()..start();
      gitRemote.fetch(
        callbacks: _buildCallbacks(config, remote: remote),
      );
      stopwatch.stop();
      _log('Fetch 成功！耗时: ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      _log('Fetch 失败: $e');
      rethrow;
    } finally {
      gitRemote.free();
      repo.free();
    }
  }

  /// 推送
  Future<void> push({
    required GitConfig config,
    required String localPath,
    String? remoteName,
  }) async {
    if (!_isInitialized) await initialize();

    final remote = config.remotes.firstWhere(
      (r) => r.name == (remoteName ?? config.defaultRemote),
      orElse: () => config.primaryRemote ?? GitRemote(name: remoteName ?? 'origin', url: config.repoUrl),
    );

    _log('========== Push ==========');
    _log('本地路径: $localPath');
    _log('远程名称: ${remote.name}');

    final repo = git2.Repository.open(localPath);

    // 如果需要，更新远程 URL
    final url = _getProcessedUrl(config, remote: remote);
    final configEntry = repo.config['remote.${remote.name}.url'];
    final currentUrl = configEntry.value;
    if (currentUrl != url) {
      _log('更新远程 URL: $currentUrl -> $url');
      git2.Remote.setUrl(repo: repo, remote: remote.name, url: url);
    } else {
      _log('远程 URL: $url');
    }

    final gitRemote = git2.Remote.lookup(repo: repo, name: remote.name);

    _log('开始推送到远程...');
    try {
      final stopwatch = Stopwatch()..start();
      gitRemote.push(
        callbacks: _buildCallbacks(config, remote: remote),
      );
      stopwatch.stop();
      _log('Push 成功！耗时: ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      _log('Push 失败: $e');
      rethrow;
    } finally {
      gitRemote.free();
      repo.free();
    }
  }

  /// 初始化本地仓库
  void initLocalRepo(String path) {
    git2.Repository.init(path: path);
  }

  /// 添加文件
  void add(String repoPath, String filePattern) {
    _log('========== Add ==========');
    _log('仓库路径: $repoPath');
    _log('文件模式: $filePattern');
    
    final repo = git2.Repository.open(repoPath);
    final index = repo.index;
    
    int addedCount = 0;
    if (filePattern == '.') {
      // 遍历添加所有变更的文件
      final statusMap = repo.status;
      _log('状态检查: 发现 ${statusMap.length} 个变更');
      for (final file in statusMap.keys) {
        _log('  添加: $file');
        index.add(file);
        addedCount++;
      }
    } else {
      index.add(filePattern);
      addedCount = 1;
    }
    index.write();
    repo.free();
    _log('添加了 $addedCount 个文件到暂存区');
  }

  /// 提交
  void commit({
    required String repoPath,
    required String message,
    required String authorName,
    required String authorEmail,
  }) {
    _log('========== Commit ==========');
    _log('仓库路径: $repoPath');
    _log('提交信息: $message');
    _log('作者: $authorName <$authorEmail>');
    
    final repo = git2.Repository.open(repoPath);

    // 获取索引并写入树
    final index = repo.index;
    index.write();
    final treeOid = index.writeTree();
    final tree = git2.Tree.lookup(repo: repo, oid: treeOid);
    _log('树 OID: $treeOid');

    // 获取父提交
    final List<git2.Commit> parents = [];
    if (!repo.isEmpty) {
      final headCommit = git2.Commit.lookup(repo: repo, oid: repo.head.target);
      parents.add(headCommit);
      _log('父提交: ${headCommit.oid}');
    } else {
      _log('首次提交（无父提交）');
    }

    // 使用 Commit.create 静态方法创建提交
    final commitOid = git2.Commit.create(
      repo: repo,
      updateRef: 'HEAD',
      author: git2.Signature.create(
        name: authorName,
        email: authorEmail,
        time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ),
      committer: git2.Signature.create(
        name: authorName,
        email: authorEmail,
        time: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ),
      message: message,
      tree: tree,
      parents: parents,
    );
    _log('提交成功！OID: $commitOid');

    // 释放资源
    tree.free();
    for (final parent in parents) {
      parent.free();
    }
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

  /// 拉取
  Future<void> pull({
    required GitConfig config,
    required String localPath,
    String? remoteName,
  }) async {
    if (!_isInitialized) await initialize();

    final remote = config.remotes.firstWhere(
      (r) => r.name == (remoteName ?? config.defaultRemote),
      orElse: () => config.primaryRemote ?? GitRemote(name: remoteName ?? 'origin', url: config.repoUrl),
    );

    _log('========== Pull ==========');
    _log('本地路径: $localPath');
    _log('远程名称: ${remote.name}');

    final repo = git2.Repository.open(localPath);

    // 如果需要，更新远程 URL
    final url = _getProcessedUrl(config, remote: remote);
    final configEntry = repo.config['remote.${remote.name}.url'];
    final currentUrl = configEntry.value;
    if (currentUrl != url) {
      _log('更新远程 URL: $currentUrl -> $url');
      git2.Remote.setUrl(repo: repo, remote: remote.name, url: url);
    } else {
      _log('远程 URL: $url');
    }

    // 获取远程更新
    _log('开始 fetch...');
    final gitRemote = git2.Remote.lookup(repo: repo, name: remote.name);
    try {
      gitRemote.fetch(
        callbacks: _buildCallbacks(config, remote: remote),
      );
      _log('Fetch 完成');
    } catch (e) {
      _log('Fetch 失败: $e');
      rethrow;
    } finally {
      gitRemote.free();
    }

    // 处理空仓库：本地没有任何提交时，fetch 不会自动创建远程分支引用
    // 需要手动创建本地分支并关联远程分支
    if (repo.isEmpty) {
      _log('本地仓库为空，尝试从远程分支初始化...');
      try {
        // 尝试通过 FETCH_HEAD 获取远程分支的 OID
        final fetchHead = git2.Reference.lookup(
          repo: repo,
          name: 'FETCH_HEAD',
        );
        final remoteOid = fetchHead.target;
        _log('FETCH_HEAD OID: $remoteOid');
        fetchHead.free();

        // 创建本地分支指向远程提交
        final localBranch = git2.Branch.create(
          repo: repo,
          name: config.branch,
          target: remoteOid,
          force: false,
        );
        _log('已创建本地分支: ${config.branch}');

        // 设置 HEAD 为符号引用，指向本地分支
        git2.Reference.setTarget(
          repo: repo,
          name: 'HEAD',
          target: 'refs/heads/${config.branch}',
        );

        // 检出工作目录
        final commit = git2.Commit.lookup(repo: repo, oid: remoteOid);
        repo.reset(oid: commit.oid, resetType: git2.GitReset.hard);
        commit.free();
        localBranch.free();

        _log('空仓库初始化完成，已从远程分支检出文件');
        repo.free();
        return;
      } catch (e) {
        _log('空仓库初始化失败: $e');
        _log('提示：如果远程仓库也是空的，请先在远程创建一个提交');
        repo.free();
        rethrow;
      }
    }

    // 合并远程分支
    _log('开始合并远程分支...');
    git2.Branch? remoteBranch;
    try {
      remoteBranch = git2.Branch.lookup(
        repo: repo,
        name: '${remote.name}/${config.branch}',
        type: git2.GitBranch.remote,
      );
    } catch (e) {
      _log('查找远程分支失败: $e');
      _log('尝试通过 FETCH_HEAD 获取远程提交...');
      // 降级方案：通过 FETCH_HEAD 获取远程提交
      try {
        final fetchHead = git2.Reference.lookup(
          repo: repo,
          name: 'FETCH_HEAD',
        );
        final remoteOid = fetchHead.target;
        _log('通过 FETCH_HEAD 获取到远程提交: $remoteOid');
        fetchHead.free();

        final annotatedCommit = git2.AnnotatedCommit.lookup(
          repo: repo,
          oid: remoteOid,
        );

        final analysis = git2.Merge.analysis(
          repo: repo,
          theirHead: annotatedCommit.oid,
        );
        _log('分析结果: $analysis');

        if (analysis == git2.GitMergeAnalysis.upToDate) {
          _log('已是最新，无需合并');
          annotatedCommit.free();
          repo.free();
          return;
        }

        if (analysis == git2.GitMergeAnalysis.fastForward) {
          _log('执行快进合并...');
          final refName = 'refs/heads/${config.branch}';
          git2.Reference.setTarget(
            repo: repo,
            name: refName,
            target: annotatedCommit.oid,
          );
          final commit = git2.Commit.lookup(repo: repo, oid: annotatedCommit.oid);
          repo.reset(oid: commit.oid, resetType: git2.GitReset.hard);
          commit.free();
          _log('快进合并完成');
        } else if (analysis == git2.GitMergeAnalysis.normal) {
          _log('执行普通合并...');
          git2.Merge.commit(repo: repo, commit: annotatedCommit);
          _log('普通合并完成（可能需要解决冲突）');
        }

        annotatedCommit.free();
        repo.free();
        _log('Pull 完成（通过 FETCH_HEAD 降级）');
        return;
      } catch (e2) {
        _log('FETCH_HEAD 降级方案也失败: $e2');
        repo.free();
        rethrow;
      }
    }

    _log('远程分支: ${remoteBranch.name}');

    final annotatedCommit = git2.AnnotatedCommit.lookup(
      repo: repo,
      oid: remoteBranch.target,
    );
    _log('远程提交: ${annotatedCommit.oid}');

    // 分析合并
    final analysis = git2.Merge.analysis(
      repo: repo,
      theirHead: annotatedCommit.oid,
    );
    _log('分析结果: ${analysis}');

    if (analysis == git2.GitMergeAnalysis.upToDate) {
      _log('已是最新，无需合并');
      annotatedCommit.free();
      remoteBranch.free();
      repo.free();
      return;
    }

    if (analysis == git2.GitMergeAnalysis.fastForward) {
      _log('执行快进合并...');
      // 快进合并
      final refName = 'refs/heads/${config.branch}';
      git2.Reference.setTarget(
        repo: repo,
        name: refName,
        target: annotatedCommit.oid,
      );
      // 更新工作目录
      final commit = git2.Commit.lookup(repo: repo, oid: annotatedCommit.oid);
      repo.reset(oid: commit.oid, resetType: git2.GitReset.hard);
      commit.free();
      _log('快进合并完成');
    } else if (analysis == git2.GitMergeAnalysis.normal) {
      _log('执行普通合并...');
      // 普通合并
      git2.Merge.commit(repo: repo, commit: annotatedCommit);
      _log('普通合并完成（可能需要解决冲突）');
    }

    annotatedCommit.free();
    remoteBranch.free();
    repo.free();
    _log('Pull 完成');
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
  ///
  /// 各平台路径（用户可从其他应用访问）：
  /// - Android: /storage/emulated/0/Android/data/<包名>/files/ObsidianGit/notes-repo/
  ///   （Android 11+ 文件管理器可浏览 Android/data/ 目录）
  /// - iOS: Documents/ObsidianGit/notes-repo/（通过 Files App 访问）
  /// - macOS: ~/Documents/ObsidianGit/notes-repo/
  /// - Linux: ~/Documents/ObsidianGit/notes-repo/
  /// - Windows: C:\Users\<用户>\Documents\ObsidianGit\notes-repo\
  ///
  /// 注意：Android 上不能使用 /storage/emulated/0/Documents/ 等公共目录，
  /// 因为 libgit2 会检查仓库目录的 owner，App 运行在 u0_aXXX 用户下，
  /// 而公共目录属于 shell 用户，会报 GIT_ERROR_CONFIG 错误。
  Future<String> getRepoPath() async {
    if (Platform.isAndroid) {
      // Android: 使用 App 外部存储目录（属于 App 用户，libgit2 不会报错）
      // 路径类似: /storage/emulated/0/Android/data/com.example.obsidian_git/files/ObsidianGit/notes-repo/
      // Android 11+ 用户可通过文件管理器浏览 Android/data/<包名>/ 访问
      final appDir = await getExternalStorageDirectory();
      if (appDir != null) {
        final obsidianDir = Directory(p.join(appDir.path, 'ObsidianGit'));
        if (!await obsidianDir.exists()) {
          await obsidianDir.create(recursive: true);
        }
        return p.join(obsidianDir.path, 'notes-repo');
      }
      // 降级：使用应用内部文档目录
      final fallbackDir = await getApplicationDocumentsDirectory();
      return p.join(fallbackDir.path, 'notes-repo');
    } else {
      // 桌面平台和 iOS：使用 Documents/ObsidianGit/ 目录
      final appDir = await getApplicationDocumentsDirectory();
      final obsidianDir = Directory(p.join(appDir.path, 'ObsidianGit'));
      if (!await obsidianDir.exists()) {
        await obsidianDir.create(recursive: true);
      }
      return p.join(obsidianDir.path, 'notes-repo');
    }
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
