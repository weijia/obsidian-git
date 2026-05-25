import 'package:equatable/equatable.dart';

/// Git 配置模型
class GitConfig extends Equatable {
  final String repoUrl;
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
  });

  /// 是否使用 SSH
  bool get useSSH => authMethod == AuthMethod.ssh;

  /// 是否使用 HTTPS
  bool get useHTTPS => authMethod == AuthMethod.https;

  /// 是否已配置
  bool get isConfigured => repoUrl.isNotEmpty && localPath.isNotEmpty;

  /// 获取认证方式标签
  String get authMethodLabel => authMethod.label;

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
