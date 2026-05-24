import 'package:equatable/equatable.dart';

/// 文件夹模型
class Folder extends Equatable {
  final String id;
  final String name;
  final String path;
  final String? parentPath;
  final List<Folder> subFolders;
  final int noteCount;

  const Folder({
    required this.id,
    required this.name,
    required this.path,
    this.parentPath,
    this.subFolders = const [],
    this.noteCount = 0,
  });

  /// 从路径创建文件夹
  factory Folder.fromPath(String path) {
    final name = path.split('/').last;
    final parentPath = path.contains('/')
        ? path.substring(0, path.lastIndexOf('/'))
        : null;
    return Folder(
      id: path.hashCode.toString(),
      name: name,
      path: path,
      parentPath: parentPath,
    );
  }

  /// 根文件夹
  factory Folder.root() {
    return const Folder(
      id: 'root',
      name: '根目录',
      path: '',
    );
  }

  /// 是否为根文件夹
  bool get isRoot => path.isEmpty;

  /// 层级深度
  int get depth => path.isEmpty ? 0 : path.split('/').length;

  Folder copyWith({
    String? id,
    String? name,
    String? path,
    String? parentPath,
    List<Folder>? subFolders,
    int? noteCount,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      parentPath: parentPath ?? this.parentPath,
      subFolders: subFolders ?? this.subFolders,
      noteCount: noteCount ?? this.noteCount,
    );
  }

  @override
  List<Object?> get props => [id, name, path, parentPath, subFolders, noteCount];
}
