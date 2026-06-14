import 'package:equatable/equatable.dart';

/// Git Remote 配置
class GitRemote extends Equatable {
  final String name; // remote 名称，如 origin, upstream
  final String url; // 远程 URL
  final String? httpsToken; // HTTPS Token（每个 remote 可以不同）
  final String? sshPrivateKey; // SSH 私钥
  final String? sshPublicKey; // SSH 公钥
  final String? sshKeyPassword; // SSH 密钥密码
  final AuthMethod authMethod;

  const GitRemote({
    required this.name,
    required this.url,
    this.httpsToken,
    this.sshPrivateKey,
    this.sshPublicKey,
    this.sshKeyPassword,
    this.authMethod = AuthMethod.https,
  });

  /// 是否使用 SSH
  bool get useSSH => authMethod == AuthMethod.ssh;

  /// 是否使用 HTTPS
  bool get useHTTPS => authMethod == AuthMethod.https;

  /// 是否已配置
  bool get isConfigured => url.isNotEmpty;

  GitRemote copyWith({
    String? name,
    String? url,
    String? httpsToken,
    String? sshPrivateKey,
    String? sshPublicKey,
    String? sshKeyPassword,
    AuthMethod? authMethod,
  }) {
    return GitRemote(
      name: name ?? this.name,
      url: url ?? this.url,
      httpsToken: httpsToken ?? this.httpsToken,
      sshPrivateKey: sshPrivateKey ?? this.sshPrivateKey,
      sshPublicKey: sshPublicKey ?? this.sshPublicKey,
      sshKeyPassword: sshKeyPassword ?? this.sshKeyPassword,
      authMethod: authMethod ?? this.authMethod,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'httpsToken': httpsToken,
    'sshPrivateKey': sshPrivateKey,
    'sshPublicKey': sshPublicKey,
    'sshKeyPassword': sshKeyPassword,
    'authMethod': authMethod.name,
  };

  factory GitRemote.fromJson(Map<String, dynamic> json) {
    return GitRemote(
      name: json['name'] as String? ?? 'origin',
      url: json['url'] as String? ?? '',
      httpsToken: json['httpsToken'] as String?,
      sshPrivateKey: json['sshPrivateKey'] as String?,
      sshPublicKey: json['sshPublicKey'] as String?,
      sshKeyPassword: json['sshKeyPassword'] as String?,
      authMethod: AuthMethod.values.firstWhere(
        (e) => e.name == json['authMethod'],
        orElse: () => AuthMethod.https,
      ),
    );
  }

  @override
  List<Object?> get props => [name, url, httpsToken, sshPrivateKey, sshPublicKey, sshKeyPassword, authMethod];
}

/// Git 配置模型
class GitConfig extends Equatable {
  final String repoUrl; // 主 remote URL（向后兼容）
  final String branch;
  final String localPath;
  final String? username;
  final String? email;
  final String? sshKeyPath;
  final String? sshPublicKey;
  final String? sshPrivateKey;
  final String? sshKeyPassword;
  final String? httpsToken; // HTTPS Personal Access Token
  final AuthMethod authMethod;
  final SyncFrequency syncFrequency;
  final bool autoSync;
  final DateTime? lastSyncTime;
  final SyncStatus lastSyncStatus;
  
  /// 多 remote 支持
  final List<GitRemote> remotes;
  final String defaultRemote; // 默认推送的 remote

  const GitConfig({
    required this.repoUrl,
    this.branch = 'main',
    required this.localPath,
    this.username,
    this.email,
    this.sshKeyPath,
    this.sshPublicKey,
    this.sshPrivateKey,
    this.sshKeyPassword,
    this.httpsToken,
    this.authMethod = AuthMethod.https, // 默认使用 HTTPS
    this.syncFrequency = SyncFrequency.manual,
    this.autoSync = false,
    this.lastSyncTime,
    this.lastSyncStatus = SyncStatus.notSynced,
    this.remotes = const [],
    this.defaultRemote = 'origin',
  });

  /// 是否使用 SSH
  bool get useSSH => authMethod == AuthMethod.ssh;

  /// 是否使用 HTTPS
  bool get useHTTPS => authMethod == AuthMethod.https;

  /// 是否已配置
  bool get isConfigured => repoUrl.isNotEmpty && localPath.isNotEmpty;

  /// 获取认证方式标签
  String get authMethodLabel => authMethod.label;
  
  /// 获取默认 remote
  GitRemote? get primaryRemote {
    if (remotes.isEmpty) {
      // 向后兼容：从旧字段创建 remote
      if (repoUrl.isNotEmpty) {
        return GitRemote(
          name: defaultRemote,
          url: repoUrl,
          httpsToken: httpsToken,
          sshPrivateKey: sshPrivateKey,
          sshPublicKey: sshPublicKey,
          sshKeyPassword: sshKeyPassword,
          authMethod: authMethod,
        );
      }
      return null;
    }
    return remotes.firstWhere(
      (r) => r.name == defaultRemote,
      orElse: () => remotes.first,
    );
  }

  GitConfig copyWith({
    String? repoUrl,
    String? branch,
    String? localPath,
    String? username,
    String? email,
    String? sshKeyPath,
    String? sshPublicKey,
    String? sshPrivateKey,
    String? sshKeyPassword,
    String? httpsToken,
    AuthMethod? authMethod,
    SyncFrequency? syncFrequency,
    bool? autoSync,
    DateTime? lastSyncTime,
    SyncStatus? lastSyncStatus,
    List<GitRemote>? remotes,
    String? defaultRemote,
  }) {
    return GitConfig(
      repoUrl: repoUrl ?? this.repoUrl,
      branch: branch ?? this.branch,
      localPath: localPath ?? this.localPath,
      username: username ?? this.username,
      email: email ?? this.email,
      sshKeyPath: sshKeyPath ?? this.sshKeyPath,
      sshPublicKey: sshPublicKey ?? this.sshPublicKey,
      sshPrivateKey: sshPrivateKey ?? this.sshPrivateKey,
      sshKeyPassword: sshKeyPassword ?? this.sshKeyPassword,
      httpsToken: httpsToken ?? this.httpsToken,
      authMethod: authMethod ?? this.authMethod,
      syncFrequency: syncFrequency ?? this.syncFrequency,
      autoSync: autoSync ?? this.autoSync,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      lastSyncStatus: lastSyncStatus ?? this.lastSyncStatus,
      remotes: remotes ?? this.remotes,
      defaultRemote: defaultRemote ?? this.defaultRemote,
    );
  }

  @override
  List<Object?> get props => [
        repoUrl,
        branch,
        localPath,
        username,
        email,
        sshKeyPath,
        sshPublicKey,
        sshPrivateKey,
        sshKeyPassword,
        httpsToken,
        authMethod,
        syncFrequency,
        autoSync,
        lastSyncTime,
        lastSyncStatus,
        remotes,
        defaultRemote,
      ];
}

/// 认证方式
enum AuthMethod {
  https('HTTPS (推荐)', '使用 Personal Access Token 认证'),
  ssh('SSH', '使用 SSH 密钥认证');

  final String label;
  final String description;
  const AuthMethod(this.label, this.description);
}

/// 同步频率
enum SyncFrequency {
  manual('手动同步'),
  realtime('实时同步'),
  minutes5('每5分钟'),
  minutes15('每15分钟'),
  minutes30('每30分钟'),
  hourly('每小时');

  final String label;
  const SyncFrequency(this.label);
}

/// 同步状态
enum SyncStatus {
  notSynced('未同步'),
  syncing('同步中'),
  synced('已同步'),
  error('同步失败');

  final String label;
  const SyncStatus(this.label);
}
