import 'package:flutter/material.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/note.dart';
import '../../blocs/notes/notes_bloc.dart';

/// WYSIWYG Markdown 编辑器组件
class MarkdownEditor extends StatefulWidget {
  final Note note;
  final bool readOnly;

  const MarkdownEditor({
    super.key,
    required this.note,
    this.readOnly = false,
  });

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  late EditorState _editorState;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initEditor();
  }

  void _initEditor() {
    // 将 Markdown 转换为 AppFlowy Editor 文档
    final document = _markdownToDocument(widget.note.content);
    _editorState = EditorState(document: document);

    // 监听内容变化
    _editorState.transactionStream.listen((_) {
      // 内容已更改，延迟保存
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _saveContent();
        }
      });
    });

    _isInitialized = true;
  }

  @override
  void didUpdateWidget(MarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.filePath != widget.note.filePath) {
      // 笔记切换，重新初始化编辑器
      _initEditor();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // 工具栏
        if (!widget.readOnly) _buildToolbar(),
        // 编辑器
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: AppFlowyEditor(
              editorState: _editorState,
              editable: !widget.readOnly,
              // 配置编辑器样式，与 App 主题协调
              editorStyle: EditorStyle.desktop(
                padding: const EdgeInsets.all(16),
                cursorColor: colorScheme.primary,
                selectionColor: colorScheme.primaryContainer.withOpacity(0.4),
                textStyleConfiguration: TextStyleConfiguration(
                  text: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    height: 1.5,
                  ),
                  bold: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                  italic: TextStyle(
                    color: colorScheme.onSurface,
                    fontStyle: FontStyle.italic,
                  ),
                  underline: TextStyle(
                    color: colorScheme.onSurface,
                    decoration: TextDecoration.underline,
                  ),
                  strikethrough: TextStyle(
                    color: colorScheme.onSurface,
                    decoration: TextDecoration.lineThrough,
                  ),
                  code: TextStyle(
                    color: colorScheme.primary,
                    backgroundColor: colorScheme.primaryContainer.withOpacity(0.3),
                    fontFamily: 'monospace',
                    fontSize: 14,
                  ),
                ),
              ),
              // 配置块组件样式
              blockComponentBuilders: {
                ...standardBlockComponentBuilderMap,
                // 自定义标题样式
                'heading': HeadingBlockComponentBuilder(
                  textStyleBuilder: (level) {
                    final double fontSize;
                    switch (level) {
                      case 1:
                        fontSize = 28;
                        break;
                      case 2:
                        fontSize = 24;
                        break;
                      case 3:
                        fontSize = 20;
                        break;
                      case 4:
                        fontSize = 18;
                        break;
                      case 5:
                        fontSize = 16;
                        break;
                      case 6:
                        fontSize = 14;
                        break;
                      default:
                        fontSize = 16;
                    }
                    return TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: fontSize,
                      fontWeight: level <= 2 ? FontWeight.bold : FontWeight.w600,
                    );
                  },
                ),
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withOpacity(0.5),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // 标题
            _buildToolbarButton(
              icon: Icons.title,
              tooltip: '标题 H1',
              onPressed: () => _insertHeading(1),
            ),
            _buildToolbarButton(
              icon: Icons.format_size,
              tooltip: '副标题 H2',
              onPressed: () => _insertHeading(2),
            ),
            const SizedBox(width: 8),
            _buildDivider(),
            const SizedBox(width: 8),
            // 格式化
            _buildToolbarButton(
              icon: Icons.format_bold,
              tooltip: '粗体',
              onPressed: _toggleBold,
            ),
            _buildToolbarButton(
              icon: Icons.format_italic,
              tooltip: '斜体',
              onPressed: _toggleItalic,
            ),
            _buildToolbarButton(
              icon: Icons.format_underlined,
              tooltip: '下划线',
              onPressed: _toggleUnderline,
            ),
            _buildToolbarButton(
              icon: Icons.strikethrough_s,
              tooltip: '删除线',
              onPressed: _toggleStrikethrough,
            ),
            const SizedBox(width: 8),
            _buildDivider(),
            const SizedBox(width: 8),
            // 列表
            _buildToolbarButton(
              icon: Icons.format_list_bulleted,
              tooltip: '无序列表',
              onPressed: _toggleBulletList,
            ),
            _buildToolbarButton(
              icon: Icons.format_list_numbered,
              tooltip: '有序列表',
              onPressed: _toggleNumberedList,
            ),
            _buildToolbarButton(
              icon: Icons.checklist,
              tooltip: '待办列表',
              onPressed: _toggleTodoList,
            ),
            const SizedBox(width: 8),
            _buildDivider(),
            const SizedBox(width: 8),
            // 其他
            _buildToolbarButton(
              icon: Icons.format_quote,
              tooltip: '引用',
              onPressed: _toggleQuote,
            ),
            _buildToolbarButton(
              icon: Icons.code,
              tooltip: '代码块',
              onPressed: _toggleCodeBlock,
            ),
            _buildToolbarButton(
              icon: Icons.table_chart,
              tooltip: '插入表格',
              onPressed: _showInsertTableDialog,
            ),
            _buildToolbarButton(
              icon: Icons.image,
              tooltip: '插入图片',
              onPressed: _insertImage,
            ),
            _buildToolbarButton(
              icon: Icons.link,
              tooltip: '插入链接',
              onPressed: _insertLink,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.all(6),
            child: Icon(
              icon,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 20,
      width: 1,
      color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
    );
  }

  // 编辑器操作方法
  void _insertHeading(int level) {
    final selection = _editorState.selection;
    if (selection == null) return;

    final node = _editorState.getNodeAtPath(selection.start.path);
    if (node != null) {
      final transaction = _editorState.transaction;
      transaction.updateNode(node, {
        'subtype': 'heading',
        'level': level,
      });
      _editorState.apply(transaction);
    }
  }

  void _toggleBold() {
    _editorState.toggleAttribute('bold');
  }

  void _toggleItalic() {
    _editorState.toggleAttribute('italic');
  }

  void _toggleUnderline() {
    _editorState.toggleAttribute('underline');
  }

  void _toggleStrikethrough() {
    _editorState.toggleAttribute('strikethrough');
  }

  void _toggleBulletList() {
    _editorState.toggleAttribute('bullet');
  }

  void _toggleNumberedList() {
    _editorState.toggleAttribute('number');
  }

  void _toggleTodoList() {
    _editorState.toggleAttribute('todo');
  }

  void _toggleQuote() {
    _editorState.toggleAttribute('quote');
  }

  void _toggleCodeBlock() {
    _editorState.toggleAttribute('code');
  }

  /// 显示插入表格对话框
  void _showInsertTableDialog() {
    int rows = 3;
    int cols = 3;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('插入表格'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text('行数:'),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Slider(
                      value: rows.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: rows.toString(),
                      onChanged: (value) {
                        setState(() {
                          rows = value.round();
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 30,
                    child: Text(rows.toString()),
                  ),
                ],
              ),
              Row(
                children: [
                  const Text('列数:'),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Slider(
                      value: cols.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: cols.toString(),
                      onChanged: (value) {
                        setState(() {
                          cols = value.round();
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 30,
                    child: Text(cols.toString()),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 预览
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  children: List.generate(rows, (r) =>
                    Row(
                      children: List.generate(cols, (c) =>
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.all(1),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              color: Colors.grey.shade100,
                            ),
                            child: Text(
                              r == 0 ? '标题${c + 1}' : '单元格',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: r == 0 ? FontWeight.bold : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _insertTable(rows: rows, cols: cols);
              },
              child: const Text('插入'),
            ),
          ],
        ),
      ),
    );
  }

  /// 插入表格
  void _insertTable({required int rows, required int cols}) {
    final selection = _editorState.selection;

    // 如果没有选择，在文档末尾插入
    if (selection == null) {
      _insertTableAtEnd(rows: rows, cols: cols);
      return;
    }

    try {
      final transaction = _editorState.transaction;

      // 创建表格节点 - 使用正确的 AppFlowy Editor 表格结构
      final tableNode = Node(
        type: 'table',
        attributes: {
          'cols_len': cols,
        },
        children: [
          for (var i = 0; i < rows; i++)
            Node(
              type: 'table_row',
              attributes: {
                'row_position': i,
              },
              children: [
                for (var j = 0; j < cols; j++)
                  Node(
                    type: 'table_cell',
                    attributes: {
                      'col_position': j,
                      'row_position': i,
                    },
                    children: [
                      Node(
                        type: 'paragraph',
                        attributes: {
                          'delta': [
                            {
                              'insert': i == 0 ? '标题 ${j + 1}' : '',
                            },
                          ],
                        },
                      ),
                    ],
                  ),
              ],
            ),
        ],
      );

      // 在当前选择位置后插入表格
      final node = _editorState.getNodeAtPath(selection.end.path);
      if (node != null) {
        // 在当前节点后插入
        transaction.insertNode(selection.end.path.next, tableNode);
      } else {
        // 如果无法获取节点，在文档末尾插入
        _insertTableAtEnd(rows: rows, cols: cols);
        return;
      }

      _editorState.apply(transaction);

      // 显示成功提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已插入 ${rows}x$cols 表格'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      // 如果插入失败，尝试在末尾插入
      _insertTableAtEnd(rows: rows, cols: cols);
    }
  }

  /// 在文档末尾插入表格
  void _insertTableAtEnd({required int rows, required int cols}) {
    try {
      final transaction = _editorState.transaction;
      final document = _editorState.document;

      // 获取文档最后一个节点的路径
      final lastNode = document.root.children.lastOrNull;
      Path insertPath;
      if (lastNode != null) {
        insertPath = lastNode.path.next;
      } else {
        insertPath = [0];
      }

      // 创建表格节点
      final tableNode = Node(
        type: 'table',
        attributes: {
          'cols_len': cols,
        },
        children: [
          for (var i = 0; i < rows; i++)
            Node(
              type: 'table_row',
              attributes: {
                'row_position': i,
              },
              children: [
                for (var j = 0; j < cols; j++)
                  Node(
                    type: 'table_cell',
                    attributes: {
                      'col_position': j,
                      'row_position': i,
                    },
                    children: [
                      Node(
                        type: 'paragraph',
                        attributes: {
                          'delta': [
                            {
                              'insert': i == 0 ? '标题 ${j + 1}' : '',
                            },
                          ],
                        },
                      ),
                    ],
                  ),
              ],
            ),
        ],
      );

      transaction.insertNode(insertPath, tableNode);
      _editorState.apply(transaction);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已插入 ${rows}x$cols 表格'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('插入表格失败: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _insertImage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('图片插入功能即将推出')),
    );
  }

  void _insertLink() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('链接插入功能即将推出')),
    );
  }

  void _saveContent() {
    final markdown = _documentToMarkdown(_editorState.document);
    final updatedNote = widget.note.copyWith(
      content: markdown,
      modifiedAt: DateTime.now(),
    );
    context.read<NotesBloc>().add(UpdateNote(updatedNote));
  }

  /// 将 Markdown 转换为 AppFlowy Editor 文档
  Document _markdownToDocument(String markdown) {
    try {
      if (markdown.trim().isEmpty) {
        // 空内容时创建带初始段落的文档，确保可编辑
        return EditorState.blank(withInitialText: true).document;
      }
      // 使用 AppFlowy Editor 的 Markdown 解析器
      return markdownToDocument(markdown);
    } catch (e) {
      // 如果解析失败，返回带初始段落的文档
      return EditorState.blank(withInitialText: true).document;
    }
  }

  /// 将 AppFlowy Editor 文档转换为 Markdown
  String _documentToMarkdown(Document document) {
    try {
      return documentToMarkdown(document);
    } catch (e) {
      return '';
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}
