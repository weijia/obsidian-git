import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/git_config.dart';
import '../services/git_service.dart';
import '../services/settings_service.dart';
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
  final SettingsService _settingsService = SettingsService();

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
    // 从 SettingsService 加载（JSON 配置文件，支持 SD 卡持久化）
    await _settingsService.loadSettings();
    final config = _settingsService.gitConfig;

    // 如果 SettingsService 中没有，兼容从 SharedPreferences 加载旧数据
    SharedPreferences? oldPrefs;
    if (config == null) {
      oldPrefs = await SharedPreferences.getInstance();
    }

    setState(() {
      if (config != null) {
        _authMethod = config.authMethod;
        _config = config;
        _repoUrlController.text = config.repoUrl;
        _branchController.text = config.branch;
        _usernameController.text = config.username ?? '';
        _emailController.text = config.email ?? '';
        _httpsTokenController.text = config.httpsToken ?? '';
        _autoSync = config.autoSync;
        _syncFrequency = config.syncFrequency;
        _sshKeyPath = config.sshKeyPath;
        _sshPublicKey = config.sshPublicKey;
        _sshKeyPassword = config.sshKeyPassword;
      } else if (oldPrefs != null) {
        // 兼容从 SharedPreferences 加载旧数据
        _authMethod = AuthMethod.values.firstWhere(
          (e) => e.name == oldPrefs!.getString('git_auth_method'),
          orElse: () => AuthMethod.https,
        );
        _config = GitConfig(
          repoUrl: oldPrefs.getString('git_repo_url') ?? '',
          branch: oldPrefs.getString('git_branch') ?? 'main',
          localPath: oldPrefs.getString('git_local_path') ?? '',
          username: oldPrefs.getString('git_username'),
          email: oldPrefs.getString('git_email'),
          httpsToken: oldPrefs.getString('git_https_token'),
          authMethod: _authMethod,
          autoSync: oldPrefs.getBool('git_auto_sync') ?? false,
          syncFrequency: SyncFrequency.values.firstWhere(
            (e) => e.name == oldPrefs!.getString('git_sync_frequency'),
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
        _sshKeyPath = oldPrefs.getString('git_ssh_key_path');
        _sshPublicKey = oldPrefs.getString('git_ssh_public_key');
        _sshKeyPassword = oldPrefs.getString('git_ssh_key_password');
      }
      _isLoading = false;
    });
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    // 保存到 SettingsService（JSON 配置文件，支持 SD 卡持久化）
    final config = _buildConfig();
    await _settingsService.setGitConfig(config);

    // 同时保存到 SharedPreferences（兼容旧版本）
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

  /// 克隆或更新仓库（异步操作，显示进度对话框）
  Future<void> _cloneOrUpdateRepo() async {
    final repoUrl = _repoUrlController.text.trim();
    if (repoUrl.isEmpty) {
      _showStatus('请先输入仓库地址', success: false);
      return;
    }

    final localPath = await _gitService.getRepoPath();
    final isExistingRepo = _gitService.isGitRepo(localPath);
    final config = _buildConfig();

    // 显示进度对话框
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CloneProgressDialog(
        isExistingRepo: isExistingRepo,
        onCancel: () {
          // 取消操作（当前版本不支持真正取消，只是关闭对话框）
          Navigator.of(context).pop();
        },
      ),
    );

    setState(() => _isCloning = true);

    try {
      if (isExistingRepo) {
        // 已存在，执行 fetch
        await _gitService.fetch(
          config: config,
          localPath: localPath,
        );
      } else {
        // 克隆新仓库
        await _gitService.clone(
          config: config,
          localPath: localPath,
        );
      }

      // 关键：将实际本地路径保存到设置中
      final savedConfig = _buildConfig();
      final configWithLocalPath = GitConfig(
        repoUrl: savedConfig.repoUrl,
        branch: savedConfig.branch,
        localPath: localPath,
        username: savedConfig.username,
        email: savedConfig.email,
        sshKeyPath: savedConfig.sshKeyPath,
        sshPublicKey: savedConfig.sshPublicKey,
        sshPrivateKey: savedConfig.sshPrivateKey,
        sshKeyPassword: savedConfig.sshKeyPassword,
        httpsToken: savedConfig.httpsToken,
        authMethod: savedConfig.authMethod,
        syncFrequency: savedConfig.syncFrequency,
        autoSync: savedConfig.autoSync,
      );
      await _settingsService.setGitConfig(configWithLocalPath);

      // 关闭进度对话框
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // 显示成功提示并返回
      if (mounted) {
        _showStatus(isExistingRepo ? '仓库已更新' : '仓库克隆成功', success: true);
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.pop(context, true);
        }
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
                        // 用户名
                        TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'Git 用户名',
                            hintText: '提交代码时显示的名字，如：zhangsan',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // 邮箱
                        TextFormField(
                          controller: _emailController,
                          decoration: const InputDecoration(
                            labelText: 'Git 邮箱',
                            hintText: '提交代码时显示的邮箱，如：zhangsan@example.com',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        if (_authMethod == AuthMethod.https) ...[
                          const SizedBox(height: 16),
                          // HTTPS Token / 密码
                          TextFormField(
                            controller: _httpsTokenController,
                            decoration: InputDecoration(
                              labelText: '访问令牌或密码',
                              hintText: 'Personal Access Token 或 Git 密码',
                              helperText: '支持填写 Personal Access Token（推荐）'
                                  '或 Git 账户密码。'
                                  '公开仓库可留空。',
                              helperMaxLines: 3,
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
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '如何获取 Personal Access Token：\n'
                            '  Gitee: 设置 -> 私人令牌 -> 生成新令牌\n'
                            '  GitHub: Settings -> Developer settings -> Personal access tokens\n'
                            '  如果没有 Token，也可以直接填写 Git 账户密码。',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
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

/// 克隆/更新进度对话框
class _CloneProgressDialog extends StatefulWidget {
  final bool isExistingRepo;
  final VoidCallback onCancel;

  const _CloneProgressDialog({
    required this.isExistingRepo,
    required this.onCancel,
  });

  @override
  State<_CloneProgressDialog> createState() => _CloneProgressDialogState();
}

class _CloneProgressDialogState extends State<_CloneProgressDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isExistingRepo ? '正在更新仓库...' : '正在克隆仓库...'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CircularProgressIndicator(
                value: null, // 不确定进度
                strokeWidth: 4,
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            widget.isExistingRepo
                ? '正在从远程获取更新...\n请保持网络连接'
                : '正在克隆远程仓库...\n这可能需要几分钟，请保持网络连接',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            '⏳ 请稍候...',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: const Text('取消'),
        ),
      ],
    );
  }
}

