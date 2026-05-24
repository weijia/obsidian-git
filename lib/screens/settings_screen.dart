import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/git_config.dart';
import '../services/git_service.dart';
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

  final GitService _gitService = GitService();

  GitConfig? _config;
  bool _isLoading = true;
  bool _autoSync = false;
  SyncFrequency _syncFrequency = SyncFrequency.manual;
  bool _isCloning = false;
  bool _isSyncing = false;
  String? _sshKeyPath;
  String? _sshPublicKey;
  String? _sshKeyPassword;
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
      _sshKeyPassword = prefs.getString('git_ssh_key_password');
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

  /// 克隆或更新仓库
  Future<void> _cloneOrUpdateRepo() async {
    final repoUrl = _repoUrlController.text.trim();
    if (repoUrl.isEmpty) {
      _showStatus('请先输入仓库地址', success: false);
      return;
    }

    setState(() => _isCloning = true);

    try {
      final localPath = await _gitService.getRepoPath();
      final isExistingRepo = _gitService.isGitRepo(localPath);

      // 读取私钥
      String? privateKey;
      if (_sshKeyPath != null) {
        privateKey = await File(_sshKeyPath!).readAsString();
      }

      if (isExistingRepo) {
        // 已存在，执行 fetch
        await _gitService.fetch(
          localPath: localPath,
          privateKey: privateKey,
          privateKeyPassword: _sshKeyPassword,
        );
        _showStatus('仓库已更新', success: true);
      } else {
        // 克隆新仓库
        await _gitService.clone(
          url: repoUrl,
          localPath: localPath,
          privateKey: privateKey,
          privateKeyPassword: _sshKeyPassword,
        );
        await _gitService.setRepoPath(localPath);
        _showStatus('仓库克隆成功', success: true);
      }
    } catch (e) {
      _showStatus('操作失败: $e', success: false);
    } finally {
      setState(() => _isCloning = false);
    }
  }

  /// 同步到远程
  Future<void> _syncToRemote() async {
    setState(() => _isSyncing = true);

    try {
      final localPath = await _gitService.getRepoPath();
      
      if (!_gitService.isGitRepo(localPath)) {
        _showStatus('请先克隆仓库', success: false);
        setState(() => _isSyncing = false);
        return;
      }

      // 读取私钥
      String? privateKey;
      if (_sshKeyPath != null) {
        privateKey = await File(_sshKeyPath!).readAsString();
      }

      await _gitService.sync(
        localPath: localPath,
        authorName: _usernameController.text.isNotEmpty 
            ? _usernameController.text 
            : 'Obsidian Git User',
        authorEmail: _emailController.text.isNotEmpty 
            ? _emailController.text 
            : 'user@example.com',
        privateKey: privateKey,
        privateKeyPassword: _sshKeyPassword,
      );

      _showStatus('同步成功', success: true);
    } catch (e) {
      _showStatus('同步失败: $e', success: false);
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  /// 生成 SSH 密钥对
  Future<void> _generateSSHKey() async {
    try {
      setState(() => _isLoading = true);
      
      final keys = await _gitService.generateRsaKeys();
      
      // 保存到应用目录
      final appDir = await getApplicationDocumentsDirectory();
      final sshDir = Directory(p.join(appDir.path, '.ssh'));
      if (!await sshDir.exists()) {
        await sshDir.create(recursive: true);
      }

      final privateKeyPath = p.join(sshDir.path, 'id_rsa');
      await File(privateKeyPath).writeAsString(keys['privateKey']!);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('git_ssh_key_path', privateKeyPath);
      await prefs.setString('git_ssh_public_key', keys['publicKey']!);

      setState(() {
        _sshKeyPath = privateKeyPath;
        _sshPublicKey = keys['publicKey'];
        _isLoading = false;
      });

      // 显示公钥
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('SSH 密钥已生成'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('请将以下公钥添加到您的 Git 托管服务：'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SelectableText(
                    keys['publicKey']!.trim(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: keys['publicKey']!.trim()));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('公钥已复制')),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('复制并关闭'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showStatus('生成密钥失败: $e', success: false);
    }
  }

  /// 导入 SSH 私钥
  Future<void> _importSSHKey() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) return;

      final privateKey = await File(file.path!).readAsString();

      // 保存到应用目录
      final appDir = await getApplicationDocumentsDirectory();
      final sshDir = Directory(p.join(appDir.path, '.ssh'));
      if (!await sshDir.exists()) {
        await sshDir.create(recursive: true);
      }

      final privateKeyPath = p.join(sshDir.path, 'id_rsa_imported');
      await File(privateKeyPath).writeAsString(privateKey);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('git_ssh_key_path', privateKeyPath);

      // 尝试提取公钥（如果私钥包含）
      // 这里简化处理，实际可能需要单独导入公钥

      setState(() {
        _sshKeyPath = privateKeyPath;
      });

      _showStatus('私钥已导入', success: true);
    } catch (e) {
      _showStatus('导入失败: $e', success: false);
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
                            hintText: 'git@github.com:user/repo.git',
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
                                onPressed: _isCloning ? null : _cloneOrUpdateRepo,
                                icon: _isCloning
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.download),
                                label: Text(_isCloning ? '克隆中...' : '克隆/更新'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isSyncing ? null : _syncToRemote,
                                icon: _isSyncing
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.sync),
                                label: Text(_isSyncing ? '同步中...' : '同步到远程'),
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
                          subtitle: const Text('生成 RSA 密钥对'),
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
                                  const SnackBar(content: Text('公钥已复制')),
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
