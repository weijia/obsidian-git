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
    this.syncFrequency = SyncFrequency.manual,
    this.autoSync = false,
    this.lastSyncTime,
    this.lastSyncStatus = SyncStatus.notSynced,
  });

  /// 是否使用 SSH
  bool get useSSH => sshPrivateKey != null && sshPrivateKey!.isNotEmpty;

  /// 是否已配置
  bool get isConfigured => repoUrl.isNotEmpty && localPath.isNotEmpty;

  GitConfig copyWith({
    String? repoUrl,
    String? branch,
    String? localPath,
    String? username,
    String? email,
    String? sshKeyPath,
    String? sshPublicKey,
    String? sshPrivateKey,
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
        syncFrequency,
        autoSync,
        lastSyncTime,
        lastSyncStatus,
      ];
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
