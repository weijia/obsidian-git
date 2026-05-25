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
  final _httpsTokenController = TextEditingController();

  final GitService _gitService = GitService();

  GitConfig? _config;
  bool _isLoading = true;
  bool _autoSync = false;
  SyncFrequency _syncFrequency = SyncFrequency.manual;
  bool _isCloning = false;
  bool _isSyncing = false;
  AuthMethod _authMethod = AuthMethod.https; // 默认使用 HTTPS
  String? _sshKeyPath;
  String? _sshPublicKey;
  String? _sshKeyPassword;
  String? _statusMessage;
  bool? _statusSuccess;
  bool _showToken = false; // 是否显示 Token

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _authMethod = AuthMethod.values.firstWhere(
        (e) => e.name == prefs.getString('git_auth_method'),
        orElse: () => AuthMethod.https,
      );
      _config = GitConfig(
        repoUrl: prefs.getString('git_repo_url') ?? '',
        branch: prefs.getString('git_branch') ?? 'main',
        localPath: prefs.getString('git_local_path') ?? '',
        username: prefs.getString('git_username'),
        email: prefs.getString('git_email'),
        httpsToken: prefs.getString('git_https_token'),
        authMethod: _authMethod,
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
      _httpsTokenController.text = _config?.httpsToken ?? '';
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
    await prefs.setString('git_https_token', _httpsTokenController.text);
    await prefs.setString('git_auth_method', _authMethod.name);
    await prefs.setBool('git_auto_sync', _autoSync);
    await prefs.setString('git_sync_frequency', _syncFrequency.name);

    if (mounted) {
      _showStatus('设置已保存', success: true);
    }
  }

  /// 创建 GitConfig 对象
  GitConfig _buildConfig() {
    String? privateKey;
    if (_authMethod == AuthMethod.ssh && _sshKeyPath != null) {
      try {
        privateKey = File(_sshKeyPath!).readAsStringSync();
      } catch (e) {
        print('读取私钥失败: $e');
      }
    }

    return GitConfig(
      repoUrl: _repoUrlController.text.trim(),
      branch: _branchController.text.trim(),
      localPath: '', // 由 GitService 决定
      username: _usernameController.text.trim(),
      email: _emailController.text.trim(),
      httpsToken: _httpsTokenController.text.trim(),
      authMethod: _authMethod,
      sshPublicKey: _sshPublicKey,
      sshPrivateKey: privateKey,
      sshKeyPassword: _sshKeyPassword,
      autoSync: _autoSync,
      syncFrequency: _syncFrequency,
    );
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
      final config = _buildConfig();

      if (isExistingRepo) {
        // 已存在，执行 fetch
        await _gitService.fetch(
          config: config,
          localPath: localPath,
        );
        _showStatus('仓库已更新', success: true);
      } else {
        // 克隆新仓库
        await _gitService.clone(
          config: config,
          localPath: localPath,
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

      final config = _buildConfig();

      await _gitService.sync(
        localPath: localPath,
        authorName: _usernameController.text.isNotEmpty 
            ? _usernameController.text 
            : 'Obsidian Git User',
        authorEmail: _emailController.text.isNotEmpty 
            ? _emailController.text 
            : 'user@example.com',
        publicKey: config.sshPublicKey,
        privateKey: config.sshPrivateKey,
        privateKeyPassword: config.sshKeyPassword,
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
      
      // 使用系统 ssh-keygen 命令生成（如果可用）
      final appDir = await getApplicationDocumentsDirectory();
      final sshDir = Directory(p.join(appDir.path, '.ssh'));
      if (!await sshDir.exists()) {
        await sshDir.create(recursive: true);
      }
      final privateKeyPath = p.join(sshDir.path, 'id_rsa');
      final publicKeyPath = p.join(sshDir.path, 'id_rsa.pub');

      // 删除已有密钥
      if (await File(privateKeyPath).exists()) {
        await File(privateKeyPath).delete();
      }
      if (await File(publicKeyPath).exists()) {
        await File(publicKeyPath).delete();
      }

      final result = await Process.run('ssh-keygen', [
        '-t', 'rsa',
        '-b', '4096',
        '-f', privateKeyPath,
        '-N', '',
        '-C', 'obsidian-git',
      ]);

      if (result.exitCode == 0) {
        final privateKey = await File(privateKeyPath).readAsString();
        final publicKey = await File(publicKeyPath).readAsString();
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('git_ssh_key_path', privateKeyPath);
        await prefs.setString('git_ssh_public_key', publicKey);

        setState(() {
          _sshKeyPath = privateKeyPath;
          _sshPublicKey = publicKey;
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
                      publicKey.trim(),
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
                    Clipboard.setData(ClipboardData(text: publicKey.trim()));
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
      } else {
        throw Exception('ssh-keygen 失败: ${result.stderr}');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showStatus('生成密钥失败: $e\n\n请在电脑上使用 ssh-keygen 生成后导入。', success: false);
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

      setState(() {
        _sshKeyPath = privateKeyPath;
      });

      _showStatus('私钥已导入', success: true);
    } catch (e) {
      _showStatus('导入失败: $e', success: false);
    }
  }

  void _showStatus(String message, {required bool success, bool copyable = true}) {
    setState(() {
      _statusMessage = message;
      _statusSuccess = success;
    });

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: null,
        ),
      );
    } else {
      // 错误信息显示为可复制的对话框
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 8),
              const Text('操作失败'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                message,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
            TextButton.icon(
              onPressed: () {
                // 复制错误信息到剪贴板
                Clipboard.setData(ClipboardData(text: message));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('错误信息已复制')),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('复制'),
            ),
          ],
        ),
      );
    }
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
                        // 认证方式选择
                        DropdownButtonFormField<AuthMethod>(
                          value: _authMethod,
                          decoration: const InputDecoration(
                            labelText: '认证方式',
                            border: OutlineInputBorder(),
                          ),
                          items: AuthMethod.values.map((method) {
                            return DropdownMenuItem(
                              value: method,
                              child: Text(method.label),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _authMethod = value);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _authMethod.description,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _repoUrlController,
                          decoration: InputDecoration(
                            labelText: '仓库地址',
                            hintText: _authMethod == AuthMethod.https
                                ? 'https://gitee.com/username/repo.git'
                                : 'git@gitee.com:username/repo.git',
                            border: const OutlineInputBorder(),
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

                    // HTTPS Token 配置（仅在 HTTPS 模式下显示）
                    if (_authMethod == AuthMethod.https)
                      _buildSection(
                        title: 'HTTPS 认证',
                        icon: Icons.token,
                        children: [
                          TextFormField(
                            controller: _httpsTokenController,
                            decoration: InputDecoration(
                              labelText: 'Personal Access Token',
                              hintText: '请输入您的 Personal Access Token',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _showToken ? Icons.visibility_off : Icons.visibility,
                                ),
                                onPressed: () {
                                  setState(() => _showToken = !_showToken);
                                },
                              ),
                            ),
                            obscureText: !_showToken,
                            validator: (value) {
                              // Token 是可选的（公开仓库不需要）
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '如何获取 Token：\n'
                            '• Gitee: 设置 -> 私人令牌 -> 生成新令牌\n'
                            '• GitHub: Settings -> Developer settings -> Personal access tokens',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    if (_authMethod == AuthMethod.https) const SizedBox(height: 24),

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

                    // SSH 密钥（仅在 SSH 模式下显示）
                    if (_authMethod == AuthMethod.ssh)
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
                    if (_authMethod == AuthMethod.ssh) const SizedBox(height: 24),

                    // 关于
                    _buildSection(
                      title: '关于',
                      icon: Icons.info_outline,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.code),
                          title: const Text('版本'),
                          subtitle: Text(AppVersion.fullVersion),
                        ),
                      ],
                    ),
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
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }
}
