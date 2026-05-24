import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/git_config.dart';
import '../version.dart';

/// 设置屏幕
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repoUrlController = TextEditingController();
  final _branchController = TextEditingController(text: 'main');
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();

  GitConfig? _config;
  bool _isLoading = true;
  bool _autoSync = false;
  SyncFrequency _syncFrequency = SyncFrequency.manual;
  bool _isCloning = false;
  bool _isSyncing = false;
  String? _sshKeyPath;
  String? _sshPublicKey;
  String? _statusMessage;
  bool? _statusSuccess;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _config = GitConfig(
        repoUrl: prefs.getString('git_repo_url') ?? '',
        branch: prefs.getString('git_branch') ?? 'main',
        localPath: prefs.getString('git_local_path') ?? '',
        username: prefs.getString('git_username'),
        email: prefs.getString('git_email'),
        autoSync: prefs.getBool('git_auto_sync') ?? false,
        syncFrequency: SyncFrequency.values.firstWhere(
          (e) => e.name == prefs.getString('git_sync_frequency'),
          orElse: () => SyncFrequency.manual,
        ),
      );
      _repoUrlController.text = _config?.repoUrl ?? '';
      _branchController.text = _config?.branch ?? 'main';
      _usernameController.text = _config?.username ?? '';
      _emailController.text = _config?.email ?? '';
      _autoSync = _config?.autoSync ?? false;
      _syncFrequency = _config?.syncFrequency ?? SyncFrequency.manual;
      _sshKeyPath = prefs.getString('git_ssh_key_path');
      _sshPublicKey = prefs.getString('git_ssh_public_key');
      _isLoading = false;
    });
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('git_repo_url', _repoUrlController.text);
    await prefs.setString('git_branch', _branchController.text);
    await prefs.setString('git_username', _usernameController.text);
    await prefs.setString('git_email', _emailController.text);
    await prefs.setBool('git_auto_sync', _autoSync);
    await prefs.setString('git_sync_frequency', _syncFrequency.name);

    if (mounted) {
      _showStatus('设置已保存', success: true);
    }
  }

  /// 克隆仓库
  Future<void> _cloneRepo() async {
    final repoUrl = _repoUrlController.text.trim();
    if (repoUrl.isEmpty) {
      _showStatus('请先输入仓库地址', success: false);
      return;
    }

    setState(() => _isCloning = true);

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final localPath = p.join(appDir.path, 'notes');

      // 检查目录是否已存在
      final dir = Directory(localPath);
      if (await dir.exists()) {
        // 目录已存在，尝试拉取
        final pullResult = await Process.run(
          'git',
          ['pull', 'origin', _branchController.text],
          workingDirectory: localPath,
        );
        if (pullResult.exitCode == 0) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('git_local_path', localPath);
          _showStatus('仓库已更新', success: true);
        } else {
          _showStatus('更新失败: ${pullResult.stderr}', success: false);
        }
      } else {
        // 克隆新仓库
        final result = await Process.run(
          'git',
          ['clone', '-b', _branchController.text, repoUrl, localPath],
        );

        if (result.exitCode == 0) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('git_local_path', localPath);
          _showStatus('仓库克隆成功', success: true);
        } else {
          _showStatus('克隆失败: ${result.stderr}', success: false);
        }
      }
    } catch (e) {
      _showStatus('操作失败: $e', success: false);
    } finally {
      setState(() => _isCloning = false);
    }
  }

  /// 手动同步
  Future<void> _manualSync() async {
    setState(() => _isSyncing = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final localPath = prefs.getString('git_local_path');
      if (localPath == null || localPath.isEmpty) {
        _showStatus('请先克隆仓库', success: false);
        setState(() => _isSyncing = false);
        return;
      }

      // 配置 git 用户信息
      final username = _usernameController.text.trim();
      final email = _emailController.text.trim();
      if (username.isNotEmpty) {
        await Process.run('git', ['config', 'user.name', username],
            workingDirectory: localPath);
      }
      if (email.isNotEmpty) {
        await Process.run('git', ['config', 'user.email', email],
            workingDirectory: localPath);
      }

      // 拉取远程更新
      final pullResult = await Process.run(
        'git',
        ['pull', 'origin', _branchController.text],
        workingDirectory: localPath,
      );

      // 添加所有更改
      await Process.run('git', ['add', '.'], workingDirectory: localPath);

      // 检查是否有更改
      final statusResult = await Process.run(
        'git',
        ['status', '--porcelain'],
        workingDirectory: localPath,
      );

      if (statusResult.stdout.toString().trim().isNotEmpty) {
        // 提交
        final now = DateTime.now();
        final commitMsg = 'Auto sync ${now.toIso8601String()}';
        await Process.run(
          'git',
          ['commit', '-m', commitMsg],
          workingDirectory: localPath,
        );

        // 推送
        final pushResult = await Process.run(
          'git',
          ['push', 'origin', _branchController.text],
          workingDirectory: localPath,
        );

        if (pushResult.exitCode == 0) {
          _showStatus('同步成功（已推送）', success: true);
        } else {
          _showStatus('推送失败: ${pushResult.stderr}', success: false);
        }
      } else {
        if (pullResult.exitCode == 0) {
          _showStatus('同步成功（已是最新）', success: true);
        } else {
          _showStatus('拉取失败: ${pullResult.stderr}', success: false);
        }
      }
    } catch (e) {
      _showStatus('同步失败: $e', success: false);
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  /// 导入 SSH 私钥
  Future<void> _importSSHKey() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) {
        _showStatus('无法读取文件路径', success: false);
        return;
      }

      // 读取私钥内容
      final privateKey = await File(file.path!).readAsString();

      // 保存到应用目录
      final appDir = await getApplicationDocumentsDirectory();
      final sshDir = Directory(p.join(appDir.path, '.ssh'));
      if (!await sshDir.exists()) {
        await sshDir.create(recursive: true);
      }

      final privateKeyPath = p.join(sshDir.path, 'id_ed25519');
      await File(privateKeyPath).writeAsString(privateKey);

      // 保存路径
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('git_ssh_key_path', privateKeyPath);

      setState(() {
        _sshKeyPath = privateKeyPath;
      });

      _showStatus('SSH 私钥已导入: ${p.basename(file.path!)}', success: true);
    } catch (e) {
      _showStatus('导入失败: $e', success: false);
    }
  }

  /// 生成 SSH 密钥对
  Future<void> _generateSSHKey() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final sshDir = Directory(p.join(appDir.path, '.ssh'));
      if (!await sshDir.exists()) {
        await sshDir.create(recursive: true);
      }

      final privateKeyPath = p.join(sshDir.path, 'id_ed25519');
      final publicKeyPath = p.join(sshDir.path, 'id_ed25519.pub');

      // 使用系统 ssh-keygen 生成密钥
      final result = await Process.run(
        'ssh-keygen',
        ['-t', 'ed25519', '-f', privateKeyPath, '-N', '', '-C', 'obsidian-git'],
      );

      if (result.exitCode == 0) {
        // 读取公钥
        final publicKey = await File(publicKeyPath).readAsString();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('git_ssh_key_path', privateKeyPath);
        await prefs.setString('git_ssh_public_key', publicKey);

        setState(() {
          _sshKeyPath = privateKeyPath;
          _sshPublicKey = publicKey;
        });

        // 显示公钥给用户复制
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('SSH 公钥已生成'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('请将以下公钥添加到您的 Git 托管服务（GitHub/GitLab 等）：'),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: SelectableText(
                      publicKey.trim(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () {
                      // 复制到剪贴板
                      Clipboard.setData(ClipboardData(text: publicKey.trim()));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('公钥已复制到剪贴板')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('复制公钥'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        }
      } else {
        _showStatus('生成失败: ${result.stderr}', success: false);
      }
    } catch (e) {
      _showStatus('生成失败: $e（可能设备上没有 ssh-keygen 命令）', success: false);
    }
  }

  void _showStatus(String message, {required bool success}) {
    setState(() {
      _statusMessage = message;
      _statusSuccess = success;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveConfig,
            tooltip: '保存设置',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 状态消息
                    if (_statusMessage != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (_statusSuccess ?? false)
                              ? Colors.green.shade50
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (_statusSuccess ?? false)
                                ? Colors.green.shade200
                                : Colors.red.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              (_statusSuccess ?? false)
                                  ? Icons.check_circle
                                  : Icons.error,
                              color: (_statusSuccess ?? false)
                                  ? Colors.green
                                  : Colors.red,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _statusMessage!,
                                style: TextStyle(
                                  color: (_statusSuccess ?? false)
                                      ? Colors.green.shade800
                                      : Colors.red.shade800,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () =>
                                  setState(() => _statusMessage = null),
                            ),
                          ],
                        ),
                      ),

                    // Git 仓库配置
                    _buildSection(
                      title: 'Git 仓库配置',
                      icon: Icons.source,
                      children: [
                        TextFormField(
                          controller: _repoUrlController,
                          decoration: const InputDecoration(
                            labelText: '仓库地址',
                            hintText: 'https://github.com/user/repo.git 或 git@github.com:user/repo.git',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return '请输入仓库地址';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _branchController,
                          decoration: const InputDecoration(
                            labelText: '分支',
                            hintText: 'main',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // 克隆/同步按钮
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isCloning ? null : _cloneRepo,
                                icon: _isCloning
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child:
                                            CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.download),
                                label: Text(_isCloning ? '克隆中...' : '克隆/更新仓库'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isSyncing ? null : _manualSync,
                                icon: _isSyncing
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child:
                                            CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.sync),
                                label: Text(_isSyncing ? '同步中...' : '立即同步'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // 用户信息
                    _buildSection(
                      title: '用户信息',
                      icon: Icons.person,
                      children: [
                        TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: '用户名',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            labelText: '邮箱',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // 同步设置
                    _buildSection(
                      title: '同步设置',
                      icon: Icons.sync,
                      children: [
                        SwitchListTile(
                          title: const Text('自动同步'),
                          subtitle: const Text('笔记更改后自动同步到 Git'),
                          value: _autoSync,
                          onChanged: (value) {
                            setState(() => _autoSync = value);
                          },
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<SyncFrequency>(
                          value: _syncFrequency,
                          decoration: const InputDecoration(
                            labelText: '同步频率',
                            border: OutlineInputBorder(),
                          ),
                          items: SyncFrequency.values.map((frequency) {
                            return DropdownMenuItem(
                              value: frequency,
                              child: Text(frequency.label),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _syncFrequency = value);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // SSH 密钥
                    _buildSection(
                      title: 'SSH 密钥',
                      icon: Icons.key,
                      children: [
                        if (_sshKeyPath != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle,
                                      color: Colors.green, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '已配置: ${p.basename(_sshKeyPath!)}',
                                      style: TextStyle(
                                          color: Colors.green.shade800,
                                          fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ListTile(
                          leading: const Icon(Icons.add_circle_outline),
                          title: const Text('生成 SSH 密钥'),
                          subtitle: const Text('生成 Ed25519 密钥对（需要设备支持 ssh-keygen）'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _generateSSHKey,
                        ),
                        ListTile(
                          leading: const Icon(Icons.upload_file),
                          title: const Text('导入 SSH 私钥'),
                          subtitle: const Text('选择已有的 SSH 私钥文件'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _importSSHKey,
                        ),
                        if (_sshPublicKey != null) ...[
                          const SizedBox(height: 8),
                          const Text('SSH 公钥：',
                              style: TextStyle(fontSize: 12)),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: SelectableText(
                              _sshPublicKey!.trim(),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: _sshPublicKey!.trim()),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('公钥已复制到剪贴板')),
                                );
                              },
                              icon: const Icon(Icons.copy, size: 14),
                              label: const Text('复制公钥'),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 24),

                    // 关于
                    _buildSection(
                      title: '关于',
                      icon: Icons.info_outline,
                      children: [
                        ListTile(
                          title: const Text('版本'),
                          subtitle: Text(AppVersion.fullVersion),
                        ),
                        ListTile(
                          title: const Text('构建信息'),
                          subtitle: Text(
                            AppVersion.versionType == 'tag'
                                ? '正式版 (Tag: ${AppVersion.versionTag})'
                                : '开发版\n构建时间: ${AppVersion.versionDatetime}\n时区: ${AppVersion.versionTimezone}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _repoUrlController.dispose();
    _branchController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }
}
