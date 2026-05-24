/// 版本信息
/// 
/// 构建时由 GitHub Actions 通过 --dart-define 注入：
/// - 有 tag 时: VERSION_NAME=v1.0.0, VERSION_TYPE=tag, VERSION_TAG=v1.0.0
/// - 无 tag 时: VERSION_NAME=0.0.0-20260524.143025+08, VERSION_TYPE=datetime, 
///   VERSION_DATETIME=20260524.143025, VERSION_TIMEZONE=UTC+8
class AppVersion {
  /// 版本名称
  static const String versionName = String.fromEnvironment(
    'VERSION_NAME',
    defaultValue: '0.0.0-dev',
  );

  /// 构建类型: tag 或 datetime
  static const String versionType = String.fromEnvironment(
    'VERSION_TYPE',
    defaultValue: 'dev',
  );

  /// Git tag（仅 tag 类型有值）
  static const String versionTag = String.fromEnvironment(
    'VERSION_TAG',
    defaultValue: '',
  );

  /// 构建日期时间（仅 datetime 类型有值）
  static const String versionDatetime = String.fromEnvironment(
    'VERSION_DATETIME',
    defaultValue: '',
  );

  /// 时区标识
  static const String versionTimezone = String.fromEnvironment(
    'VERSION_TIMEZONE',
    defaultValue: '',
  );

  /// 完整版本描述
  static String get fullVersion {
    if (versionType == 'tag') {
      return versionName;
    }
    return '$versionName ($versionTimezone)';
  }

  /// 构建信息
  static String get buildInfo {
    final buffer = StringBuffer();
    buffer.writeln('版本: $versionName');
    if (versionType == 'tag') {
      buffer.writeln('构建类型: 正式版 (Tag: $versionTag)');
    } else {
      buffer.writeln('构建类型: 开发版');
      if (versionDatetime.isNotEmpty) {
        buffer.writeln('构建时间: $versionDatetime');
      }
      if (versionTimezone.isNotEmpty) {
        buffer.writeln('时区: $versionTimezone');
      }
    }
    return buffer.toString();
  }
}
