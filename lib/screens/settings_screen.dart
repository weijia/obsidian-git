  Future<void> _loadConfig() async {
    // 从 SettingsService 加载（JSON 配置文件，支持 SD 卡持久化）
    await _settingsService.loadSettings();
    final config = _settingsService.gitConfig;
    
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
      } else {
        // 配置文件中没有，尝试从 SharedPreferences 兼容加载旧数据
        final prefs = await SharedPreferences.getInstance();
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