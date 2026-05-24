import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/note.dart';
import '../models/folder.dart';

/// 笔记存储服务
class NoteStorageService {
  String? _basePath;

  String? get basePath => _basePath;

  /// 初始化存储路径
  Future<void> init(String? customPath) async {
    if (customPath != null && customPath.isNotEmpty) {
      _basePath = customPath;
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      _basePath = p.join(appDir.path, 'obsidian_git_notes');
    }

    // 确保目录存在
    final dir = Directory(_basePath!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// 获取所有笔记
  Future<List<Note>> getAllNotes() async {
    if (_basePath == null) return [];

    final notes = <Note>[];
    final dir = Directory(_basePath!);

    if (!await dir.exists()) return notes;

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.md')) {
        final relativePath = p.relative(entity.path, from: _basePath);
        try {
          final content = await entity.readAsString();
          notes.add(Note.fromMarkdown(relativePath, content));
        } catch (_) {
          notes.add(Note.fromFilePath(relativePath));
        }
      }
    }

    return notes;
  }

  /// 获取指定文件夹下的笔记
  Future<List<Note>> getNotesInFolder(String folderPath) async {
    if (_basePath == null) return [];

    final notes = <Note>[];
    final dir = Directory(p.join(_basePath!, folderPath));

    if (!await dir.exists()) return notes;

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.md')) {
        final relativePath = p.relative(entity.path, from: _basePath);
        try {
          final content = await entity.readAsString();
          notes.add(Note.fromMarkdown(relativePath, content));
        } catch (_) {
          notes.add(Note.fromFilePath(relativePath));
        }
      }
    }

    return notes;
  }

  /// 获取单个笔记
  Future<Note?> getNote(String filePath) async {
    if (_basePath == null) return null;

    final file = File(p.join(_basePath!, filePath));
    if (!await file.exists()) return null;

    try {
      final content = await file.readAsString();
      return Note.fromMarkdown(filePath, content);
    } catch (_) {
      return null;
    }
  }

  /// 保存笔记
  Future<bool> saveNote(Note note) async {
    if (_basePath == null) return false;

    try {
      final file = File(p.join(_basePath!, note.filePath));
      await file.parent.create(recursive: true);
      await file.writeAsString(note.toMarkdown());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 创建新笔记
  Future<Note> createNote({
    required String title,
    String? folderPath,
    String content = '',
  }) async {
    if (_basePath == null) {
      throw Exception('存储服务未初始化');
    }

    // 生成文件名
    final fileName = '${_sanitizeFileName(title)}.md';
    final filePath = folderPath != null && folderPath.isNotEmpty
        ? p.join(folderPath, fileName)
        : fileName;

    // 确保文件名唯一
    var finalPath = filePath;
    var counter = 1;
    while (await File(p.join(_basePath!, finalPath)).exists()) {
      finalPath = filePath.replaceAll('.md', '_$counter.md');
      counter++;
    }

    final note = Note(
      id: finalPath.hashCode.toString(),
      title: title,
      content: content,
      filePath: finalPath,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
      folderPath: folderPath,
    );

    await saveNote(note);
    return note;
  }

  /// 删除笔记
  Future<bool> deleteNote(String filePath) async {
    if (_basePath == null) return false;

    try {
      final file = File(p.join(_basePath!, filePath));
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 重命名笔记
  Future<Note?> renameNote(String oldPath, String newTitle) async {
    if (_basePath == null) return null;

    try {
      final oldFile = File(p.join(_basePath!, oldPath));
      if (!await oldFile.exists()) return null;

      final newFileName = '${_sanitizeFileName(newTitle)}.md';
      final folderPath = oldPath.contains('/')
          ? oldPath.substring(0, oldPath.lastIndexOf('/'))
          : null;
      final newPath = folderPath != null
          ? p.join(folderPath, newFileName)
          : newFileName;

      final newFile = File(p.join(_basePath!, newPath));
      await oldFile.rename(newFile.path);

      final content = await newFile.readAsString();
      return Note.fromMarkdown(newPath, content).copyWith(title: newTitle);
    } catch (_) {
      return null;
    }
  }

  /// 移动笔记到其他文件夹
  Future<bool> moveNote(String filePath, String newFolderPath) async {
    if (_basePath == null) return false;

    try {
      final oldFile = File(p.join(_basePath!, filePath));
      if (!await oldFile.exists()) return false;

      final fileName = filePath.split('/').last;
      final newPath = p.join(newFolderPath, fileName);
      final newFile = File(p.join(_basePath!, newPath));

      await newFile.parent.create(recursive: true);
      await oldFile.rename(newFile.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 获取所有文件夹
  Future<List<Folder>> getAllFolders() async {
    if (_basePath == null) return [];

    final folders = <Folder>[Folder.root()];
    final dir = Directory(_basePath!);

    if (!await dir.exists()) return folders;

    await for (final entity in dir.list(recursive: true)) {
      if (entity is Directory) {
        final relativePath = p.relative(entity.path, from: _basePath);
        if (relativePath != '.' && !relativePath.startsWith('.git')) {
          folders.add(Folder.fromPath(relativePath));
        }
      }
    }

    return folders;
  }

  /// 创建文件夹
  Future<Folder> createFolder(String folderPath) async {
    if (_basePath == null) {
      throw Exception('存储服务未初始化');
    }

    final dir = Directory(p.join(_basePath!, folderPath));
    await dir.create(recursive: true);
    return Folder.fromPath(folderPath);
  }

  /// 删除文件夹
  Future<bool> deleteFolder(String folderPath) async {
    if (_basePath == null) return false;

    try {
      final dir = Directory(p.join(_basePath!, folderPath));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 搜索笔记
  Future<List<Note>> searchNotes(String query) async {
    if (_basePath == null || query.isEmpty) return [];

    final allNotes = await getAllNotes();
    final lowerQuery = query.toLowerCase();

    return allNotes.where((note) {
      return note.title.toLowerCase().contains(lowerQuery) ||
          note.content.toLowerCase().contains(lowerQuery) ||
          note.tags.any((tag) => tag.toLowerCase().contains(lowerQuery));
    }).toList();
  }

  /// 清理文件名
  String _sanitizeFileName(String name) {
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
  }
}
