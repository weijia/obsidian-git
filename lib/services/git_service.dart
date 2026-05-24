import 'dart:io';
import '../models/git_config.dart';

/// Git 同步服务（简化版）
/// 注意：dart_git API 较为底层，这里提供基础功能框架
class GitService {
  GitConfig? _config;
  Process? _gitProcess;

  GitConfig? get config => _config;

  /// 初始化配置
  Future<void> init(GitConfig config) async {
    _config = config;

    // 确保本地目录存在
    final dir = Directory(config.localPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// 克隆远程仓库
  Future<CloneResult> clone({
    required String repoUrl,
    required String localPath,
    String branch = 'main',
    void Function(double progress)? onProgress,
  }) async {
    try {
      // 确保父目录存在
      final parentDir = Directory(localPath).parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      // 使用系统 git 命令克隆
      final result = await Process.run(
        'git',
        ['clone', '-b', branch, repoUrl, localPath],
      );

      if (result.exitCode == 0) {
        _config = GitConfig(
          repoUrl: repoUrl,
          branch: branch,
          localPath: localPath,
        );
        return CloneResult(success: true, localPath: localPath);
      } else {
        return CloneResult(
          success: false,
          error: result.stderr.toString(),
        );
      }
    } catch (e) {
      return CloneResult(success: false, error: e.toString());
    }
  }

  /// 拉取远程更新
  Future<SyncResult> pull() async {
    if (_config == null) {
      return SyncResult(success: false, error: '仓库未初始化');
    }

    try {
      final result = await Process.run(
        'git',
        ['pull', 'origin', _config!.branch],
        workingDirectory: _config!.localPath,
      );

      return SyncResult(
        success: result.exitCode == 0,
        error: result.exitCode != 0 ? result.stderr.toString() : null,
      );
    } catch (e) {
      return SyncResult(success: false, error: e.toString());
    }
  }

  /// 推送到远程
  Future<SyncResult> push() async {
    if (_config == null) {
      return SyncResult(success: false, error: '仓库未初始化');
    }

    try {
      final result = await Process.run(
        'git',
        ['push', 'origin', _config!.branch],
        workingDirectory: _config!.localPath,
      );

      return SyncResult(
        success: result.exitCode == 0,
        error: result.exitCode != 0 ? result.stderr.toString() : null,
      );
    } catch (e) {
      return SyncResult(success: false, error: e.toString());
    }
  }

  /// 完整同步（pull + commit + push）
  Future<SyncResult> sync({
    String commitMessage = 'Auto sync from Obsidian Git',
  }) async {
    if (_config == null) {
      return SyncResult(success: false, error: '仓库未初始化');
    }

    try {
      // 1. 拉取远程更新
      final pullResult = await pull();
      if (!pullResult.success && !pullResult.error!.contains('no remote')) {
        return pullResult;
      }

      // 2. 添加所有更改
      await Process.run(
        'git',
        ['add', '.'],
        workingDirectory: _config!.localPath,
      );

      // 3. 检查是否有更改需要提交
      final statusResult = await Process.run(
        'git',
        ['status', '--porcelain'],
        workingDirectory: _config!.localPath,
      );

      if (statusResult.stdout.toString().trim().isNotEmpty) {
        // 4. 提交更改
        await Process.run(
          'git',
          ['commit', '-m', commitMessage],
          workingDirectory: _config!.localPath,
        );

        // 5. 推送到远程
        final pushResult = await push();
        if (!pushResult.success) {
          return pushResult;
        }
      }

      return SyncResult(success: true);
    } catch (e) {
      return SyncResult(success: false, error: e.toString());
    }
  }

  /// 添加文件到暂存区
  Future<void> addFile(String filePath) async {
    if (_config == null) return;
    await Process.run(
      'git',
      ['add', filePath],
      workingDirectory: _config!.localPath,
    );
  }

  /// 提交更改
  Future<void> commit(String message) async {
    if (_config == null) return;
    await Process.run(
      'git',
      ['commit', '-m', message],
      workingDirectory: _config!.localPath,
    );
  }

  /// 获取当前状态
  Future<GitStatus> status() async {
    if (_config == null) {
      return GitStatus.notInitialized;
    }

    try {
      final result = await Process.run(
        'git',
        ['status', '--porcelain'],
        workingDirectory: _config!.localPath,
      );

      if (result.exitCode != 0) {
        return GitStatus.error;
      }

      if (result.stdout.toString().trim().isEmpty) {
        return GitStatus.clean;
      }
      return GitStatus.hasChanges;
    } catch (e) {
      return GitStatus.error;
    }
  }

  /// 获取提交历史
  Future<List<CommitInfo>> getCommitHistory({int limit = 50}) async {
    if (_config == null) return [];

    try {
      final result = await Process.run(
        'git',
        ['log', '--oneline', '-n', limit.toString()],
        workingDirectory: _config!.localPath,
      );

      if (result.exitCode != 0) return [];

      final lines = result.stdout.toString().split('\n');
      return lines.where((l) => l.isNotEmpty).map((line) {
        final parts = line.split(' ');
        return CommitInfo(
          hash: parts.first,
          message: parts.skip(1).join(' '),
          author: '',
          date: DateTime.now(),
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// 关闭仓库
  void close() {
    _gitProcess?.kill();
    _gitProcess = null;
  }
}

/// 克隆结果
class CloneResult {
  final bool success;
  final String? error;
  final String? localPath;

  CloneResult({required this.success, this.error, this.localPath});
}

/// 同步结果
class SyncResult {
  final bool success;
  final String? error;

  SyncResult({required this.success, this.error});
}

/// Git 状态
enum GitStatus {
  notInitialized,
  clean,
  hasChanges,
  error,
}

/// 提交信息
class CommitInfo {
  final String hash;
  final String message;
  final String author;
  final DateTime date;

  CommitInfo({
    required this.hash,
    required this.message,
    required this.author,
    required this.date,
  });
}
