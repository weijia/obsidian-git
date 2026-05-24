import 'package:equatable/equatable.dart';

/// 笔记模型
class Note extends Equatable {
  final String id;
  final String title;
  final String content;
  final String filePath;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final List<String> tags;
  final String? folderPath;

  const Note({
    required this.id,
    required this.title,
    required this.content,
    required this.filePath,
    required this.createdAt,
    required this.modifiedAt,
    this.tags = const [],
    this.folderPath,
  });

  /// 从文件路径创建笔记
  factory Note.fromFilePath(String filePath, {String content = ''}) {
    final fileName = filePath.split('/').last;
    final title = fileName.replaceAll('.md', '');
    final now = DateTime.now();
    return Note(
      id: filePath.hashCode.toString(),
      title: title,
      content: content,
      filePath: filePath,
      createdAt: now,
      modifiedAt: now,
      folderPath: filePath.contains('/')
          ? filePath.substring(0, filePath.lastIndexOf('/'))
          : null,
    );
  }

  /// 从 Markdown 内容解析笔记（含 YAML front matter）
  factory Note.fromMarkdown(String filePath, String markdown) {
    final lines = markdown.split('\n');
    String title = '';
    List<String> tags = [];
    String content = markdown;
    DateTime createdAt = DateTime.now();
    DateTime modifiedAt = DateTime.now();

    // 解析 YAML front matter
    if (lines.isNotEmpty && lines[0].trim() == '---') {
      final endIndex = lines.indexOf('---', 1);
      if (endIndex > 0) {
        final yamlContent = lines.sublist(1, endIndex).join('\n');
        content = lines.sublist(endIndex + 1).join('\n');

        // 简单解析 YAML
        for (final line in yamlContent.split('\n')) {
          if (line.startsWith('title:')) {
            title = line.substring(6).trim();
          } else if (line.startsWith('tags:')) {
            final tagsStr = line.substring(5).trim();
            if (tagsStr.startsWith('[') && tagsStr.endsWith(']')) {
              tags = tagsStr
                  .substring(1, tagsStr.length - 1)
                  .split(',')
                  .map((t) => t.trim())
                  .where((t) => t.isNotEmpty)
                  .toList();
            }
          } else if (line.startsWith('created:')) {
            try {
              createdAt = DateTime.parse(line.substring(8).trim());
            } catch (_) {}
          } else if (line.startsWith('modified:')) {
            try {
              modifiedAt = DateTime.parse(line.substring(9).trim());
            } catch (_) {}
          }
        }
      }
    }

    if (title.isEmpty) {
      title = filePath.split('/').last.replaceAll('.md', '');
    }

    return Note(
      id: filePath.hashCode.toString(),
      title: title,
      content: content,
      filePath: filePath,
      createdAt: createdAt,
      modifiedAt: modifiedAt,
      tags: tags,
      folderPath: filePath.contains('/')
          ? filePath.substring(0, filePath.lastIndexOf('/'))
          : null,
    );
  }

  /// 转换为 Markdown（含 YAML front matter）
  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln('---');
    buffer.writeln('title: $title');
    if (tags.isNotEmpty) {
      buffer.writeln('tags: [${tags.join(', ')}]');
    }
    buffer.writeln('created: ${createdAt.toIso8601String()}');
    buffer.writeln('modified: ${modifiedAt.toIso8601String()}');
    buffer.writeln('---');
    buffer.writeln(content);
    return buffer.toString();
  }

  /// 复制并修改
  Note copyWith({
    String? id,
    String? title,
    String? content,
    String? filePath,
    DateTime? createdAt,
    DateTime? modifiedAt,
    List<String>? tags,
    String? folderPath,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      filePath: filePath ?? this.filePath,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      tags: tags ?? this.tags,
      folderPath: folderPath ?? this.folderPath,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        content,
        filePath,
        createdAt,
        modifiedAt,
        tags,
        folderPath,
      ];
}
