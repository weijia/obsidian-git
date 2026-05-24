import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存')),
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
            tooltip: '保存',
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
                    // Git 仓库配置
                    _buildSection(
                      title: 'Git 仓库配置',
                      icon: Icons.source,
                      children: [
                        TextFormField(
                          controller: _repoUrlController,
                          decoration: const InputDecoration(
                            labelText: '仓库地址',
                            hintText: 'https://github.com/user/repo.git',
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
                          initialValue: _syncFrequency,
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
                    // SSH 密钥（高级）
                    _buildSection(
                      title: 'SSH 密钥（高级）',
                      icon: Icons.key,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.vpn_key),
                          title: const Text('生成 SSH 密钥'),
                          subtitle: const Text('生成新的 SSH 密钥对'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _generateSSHKey,
                        ),
                        ListTile(
                          leading: const Icon(Icons.upload_file),
                          title: const Text('导入 SSH 密钥'),
                          subtitle: const Text('导入已有的 SSH 私钥'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _importSSHKey,
                        ),
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
                        ListTile(
                          leading: const Icon(Icons.code),
                          title: const Text('开源许可'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            showLicensePage(context: context);
                          },
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

  void _generateSSHKey() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('生成 SSH 密钥'),
        content: const Text('此功能将生成 Ed25519 SSH 密钥对。公钥将显示以便添加到您的 Git 托管服务。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: 实现 SSH 密钥生成
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('SSH 密钥生成功能即将推出')),
              );
            },
            child: const Text('生成'),
          ),
        ],
      ),
    );
  }

  void _importSSHKey() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入 SSH 密钥'),
        content: const Text('请选择您的 SSH 私钥文件（通常位于 ~/.ssh/id_ed25519 或 ~/.ssh/id_rsa）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: 实现文件选择和导入
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('SSH 密钥导入功能即将推出')),
              );
            },
            child: const Text('选择文件'),
          ),
        ],
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
