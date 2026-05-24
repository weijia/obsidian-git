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
              autoFocus: true,
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
              // 使用标准块组件构建器
              blockComponentBuilders: standardBlockComponentBuilderMap,
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
              onPressed: _insertBulletList,
            ),
            _buildToolbarButton(
              icon: Icons.format_list_numbered,
              tooltip: '有序列表',
              onPressed: _insertNumberedList,
            ),
            _buildToolbarButton(
              icon: Icons.checklist,
              tooltip: '待办列表',
              onPressed: _insertTodoList,
            ),
            const SizedBox(width: 8),
            _buildDivider(),
            const SizedBox(width: 8),
            // 其他
            _buildToolbarButton(
              icon: Icons.format_quote,
              tooltip: '引用',
              onPressed: _insertQuote,
            ),
            _buildToolbarButton(
              icon: Icons.code,
              tooltip: '代码块',
              onPressed: _insertCodeBlock,
            ),
            _buildToolbarButton(
              icon: Icons.table_chart,
              tooltip: '插入表格',
              onPressed: _showInsertTableDialog,
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

  // ============== 文本格式化方法 ==============

  /// 切换粗体
  void _toggleBold() {
    _editorState.toggleAttribute(AppFlowyRichTextKeys.bold);
  }

  /// 切换斜体
  void _toggleItalic() {
    _editorState.toggleAttribute(AppFlowyRichTextKeys.italic);
  }

  /// 切换下划线
  void _toggleUnderline() {
    _editorState.toggleAttribute(AppFlowyRichTextKeys.underline);
  }

  /// 切换删除线
  void _toggleStrikethrough() {
    _editorState.toggleAttribute(AppFlowyRichTextKeys.strikethrough);
  }

  // ============== 块级元素插入方法 ==============

  /// 插入标题
  void _insertHeading(int level) {
    final selection = _editorState.selection;
    if (selection == null) return;

    // 使用 formatNode 将当前节点转换为标题
    _editorState.formatNode(
      selection,
      (node) {
        // 保留原有文本内容
        final delta = node.delta?.toJson() ?? [];
        return node.copyWith(
          type: HeadingBlockKeys.type,
          attributes: {
            HeadingBlockKeys.level: level,
            blockComponentDelta: delta,
          },
        );
      },
    );
  }

  /// 插入无序列表
  void _insertBulletList() {
    final selection = _editorState.selection;
    if (selection == null) return;

    _editorState.formatNode(
      selection,
      (node) {
        final delta = node.delta?.toJson() ?? [];
        return node.copyWith(
          type: BulletedListBlockKeys.type,
          attributes: {
            blockComponentDelta: delta,
          },
        );
      },
    );
  }

  /// 插入有序列表
  void _insertNumberedList() {
    final selection = _editorState.selection;
    if (selection == null) return;

    _editorState.formatNode(
      selection,
      (node) {
        final delta = node.delta?.toJson() ?? [];
        return node.copyWith(
          type: NumberedListBlockKeys.type,
          attributes: {
            blockComponentDelta: delta,
          },
        );
      },
    );
  }

  /// 插入待办列表
  void _insertTodoList() {
    final selection = _editorState.selection;
    if (selection == null) return;

    _editorState.formatNode(
      selection,
      (node) {
        final delta = node.delta?.toJson() ?? [];
        return node.copyWith(
          type: TodoListBlockKeys.type,
          attributes: {
            TodoListBlockKeys.checked: false,
            blockComponentDelta: delta,
          },
        );
      },
    );
  }

  /// 插入引用
  void _insertQuote() {
    final selection = _editorState.selection;
    if (selection == null) return;

    _editorState.formatNode(
      selection,
      (node) {
        final delta = node.delta?.toJson() ?? [];
        return node.copyWith(
          type: QuoteBlockKeys.type,
          attributes: {
            blockComponentDelta: delta,
          },
        );
      },
    );
  }

  /// 插入代码块（使用引用块作为替代）
  void _insertCodeBlock() {
    final selection = _editorState.selection;
    if (selection == null) return;

    _editorState.formatNode(
      selection,
      (node) {
        final delta = node.delta?.toJson() ?? [];
        return node.copyWith(
          type: QuoteBlockKeys.type,
          attributes: {
            blockComponentDelta: delta,
          },
        );
      },
    );
  }

  // ============== 表格插入方法 ==============

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
                  children: List.generate(
                    rows,
                    (r) => Row(
                      children: List.generate(
                        cols,
                        (c) => Expanded(
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

  /// 创建表格节点
  Node _createTableNode({required int rows, required int cols}) {
    // 创建表格节点
    final tableNode = Node(
      type: TableBlockKeys.type,
      attributes: {
        TableBlockKeys.colsLen: cols,
        TableBlockKeys.rowsLen: rows,
      },
    );

    // 按列优先顺序添加单元格
    for (var col = 0; col < cols; col++) {
      for (var row = 0; row < rows; row++) {
        final content = row == 0 ? '标题 ${col + 1}' : '';
        final cell = tableCellNode(content, row, col);
        tableNode.insert(cell);
      }
    }

    return tableNode;
  }

  /// 插入表格
  void _insertTable({required int rows, required int cols}) {
    try {
      final selection = _editorState.selection;
      final transaction = _editorState.transaction;
      final tableNode = _createTableNode(rows: rows, cols: cols);

      if (selection != null) {
        // 在当前选择位置后插入表格
        final node = _editorState.getNodeAtPath(selection.end.path);
        if (node != null) {
          transaction.insertNode(selection.end.path.next, tableNode);
        } else {
          _insertTableAtEnd(tableNode);
          return;
        }
      } else {
        // 没有选择，在文档末尾插入
        _insertTableAtEnd(tableNode);
        return;
      }

      _editorState.apply(transaction);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已插入 ${rows}x$cols 表格'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('插入表格失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  /// 在文档末尾插入表格
  void _insertTableAtEnd(Node tableNode) {
    try {
      final transaction = _editorState.transaction;
      final document = _editorState.document;

      final lastNode = document.root.children.lastOrNull;
      Path insertPath;
      if (lastNode != null) {
        insertPath = lastNode.path.next;
      } else {
        insertPath = [0];
      }

      transaction.insertNode(insertPath, tableNode);
      _editorState.apply(transaction);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('表格已插入'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('插入表格失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  // ============== 保存和转换方法 ==============

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
}
