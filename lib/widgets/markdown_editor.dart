import 'package:flutter/material.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/note.dart';
import '../../blocs/notes/notes_bloc.dart';

/// WYSIWYG Markdown 编辑器组件 - 支持源码模式和可视化模式切换
class MarkdownEditor extends StatefulWidget {
  final Note note;
  final bool readOnly;
  final bool isSourceMode;
  final ValueChanged<bool>? onSourceModeChanged;

  const MarkdownEditor({
    super.key,
    required this.note,
    this.readOnly = false,
    this.isSourceMode = false,
    this.onSourceModeChanged,
  });

  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  late EditorState _editorState;
  late TextEditingController _sourceController;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initEditor();
  }

  void _initEditor() {
    final document = _markdownToDocument(widget.note.content);
    _editorState = EditorState(document: document);
    _sourceController = TextEditingController(text: widget.note.content);
    _sourceController.addListener(_onSourceChanged);

    _editorState.transactionStream.listen((_) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted && !widget.isSourceMode) {
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
      _initEditor();
    } else if (oldWidget.isSourceMode != widget.isSourceMode) {
      // 模式切换
      if (widget.isSourceMode) {
        // 切换到源码模式
        final markdown = _documentToMarkdown(_editorState.document);
        _sourceController.text = markdown;
      } else {
        // 切换到可视化模式
        final document = _markdownToDocument(_sourceController.text);
        _editorState = EditorState(document: document);
      }
    }
  }

  void _onSourceChanged() {
    if (widget.isSourceMode) {
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _saveSourceContent();
        }
      });
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
        // 工具栏（仅在可视化模式显示）
        if (!widget.readOnly && !widget.isSourceMode) _buildToolbar(),
        // 编辑器
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: widget.isSourceMode
                ? _buildSourceEditor()
                : _buildVisualEditor(),
          ),
        ),
      ],
    );
  }

  Widget _buildVisualEditor() {
    final colorScheme = Theme.of(context).colorScheme;
    // 获取屏幕宽度，减去边距
    final screenWidth = MediaQuery.of(context).size.width;
    final editorWidth = screenWidth - 32; // 左右各 16px 边距

    return AppFlowyEditor(
      editorState: _editorState,
      editable: !widget.readOnly,
      autoFocus: true,
      editorStyle: EditorStyle.desktop(
        padding: const EdgeInsets.all(16),
        cursorColor: colorScheme.primary,
        selectionColor: colorScheme.primaryContainer.withAlpha(102),
        // 限制最大宽度，防止内容超出屏幕
        maxWidth: editorWidth,
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
            backgroundColor: colorScheme.primaryContainer.withAlpha(77),
            fontFamily: 'monospace',
            fontSize: 14,
          ),
        ),
      ),
      blockComponentBuilders: {
        ...standardBlockComponentBuilderMap,
        // 为表格添加行/列操作菜单
        TableBlockKeys.type: TableBlockComponentBuilder(
          menuBuilder: _buildTableMenu,
        ),
      },
    );
  }

  Widget _buildSourceEditor() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Markdown 源码',
            style: TextStyle(
              color: colorScheme.outline,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TextField(
              controller: _sourceController,
              maxLines: null,
              expands: true,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 14,
                fontFamily: 'monospace',
                height: 1.6,
              ),
              decoration: InputDecoration(
                hintText: '在此输入 Markdown 源码...',
                hintStyle: TextStyle(
                  color: colorScheme.outline,
                  fontFamily: 'monospace',
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
                contentPadding: const EdgeInsets.all(12),
                filled: true,
                fillColor: colorScheme.surfaceContainerLow,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    final colorScheme = Theme.of(context).colorScheme;

    // 检测光标是否在表格内
    final isInTable = _isCursorInTable();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isInTable ? colorScheme.primaryContainer.withAlpha(128) : colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withAlpha(128),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // 撤销 / 重做
            _buildToolbarButton(
              icon: Icons.undo,
              tooltip: '撤销',
              onPressed: _undo,
            ),
            _buildToolbarButton(
              icon: Icons.redo,
              tooltip: '重做',
              onPressed: _redo,
            ),
            const SizedBox(width: 8),
            _buildDivider(),
            const SizedBox(width: 8),
            if (isInTable) ...[
              // 表格内专用操作按钮
              _buildToolbarButton(
                icon: Icons.add,
                tooltip: '在下方插入行',
                onPressed: () => _tableAction(TableDirection.row, TableActions.add),
              ),
              _buildToolbarButton(
                icon: Icons.add_box_outlined,
                tooltip: '在右侧插入列',
                onPressed: () => _tableAction(TableDirection.col, TableActions.add),
              ),
              _buildToolbarButton(
                icon: Icons.delete_outline,
                tooltip: '删除当前行',
                onPressed: () => _tableAction(TableDirection.row, TableActions.delete),
              ),
              _buildToolbarButton(
                icon: Icons.delete_sweep_outlined,
                tooltip: '删除当前列',
                onPressed: () => _tableAction(TableDirection.col, TableActions.delete),
              ),
              _buildToolbarButton(
                icon: Icons.content_copy,
                tooltip: '复制当前行',
                onPressed: () => _tableAction(TableDirection.row, TableActions.duplicate),
              ),
              _buildToolbarButton(
                icon: Icons.clear_all,
                tooltip: '清空单元格',
                onPressed: () => _tableAction(TableDirection.row, TableActions.clear),
              ),
              const SizedBox(width: 8),
              _buildDivider(),
              const SizedBox(width: 8),
            ],
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

  /// 检测当前光标是否在表格内
  bool _isCursorInTable() {
    final selection = _editorState.selection;
    if (selection == null) return false;

    final node = _editorState.getNodeAtPath(selection.end.path);
    if (node == null) return false;

    // 向上查找父节点，检查是否有表格类型
    var current = node;
    while (current.parent != null) {
      if (current.type == TableCellBlockKeys.type ||
          current.type == TableBlockKeys.type) {
        return true;
      }
      current = current.parent!;
    }

    return false;
  }

  /// 执行表格操作
  void _tableAction(
    TableDirection direction,
    void Function(Node, int, EditorState, TableDirection) action,
  ) {
    final selection = _editorState.selection;
    if (selection == null) return;

    final node = _editorState.getNodeAtPath(selection.end.path);
    if (node == null) return;

    // 找到表格节点和单元格位置
    Node? tableNode;
    Node? cellNode;
    var current = node;
    while (current.parent != null) {
      if (current.type == TableCellBlockKeys.type) {
        cellNode = current;
      }
      if (current.type == TableBlockKeys.type) {
        tableNode = current;
        break;
      }
      current = current.parent!;
    }

    if (tableNode == null || cellNode == null) return;

    // 获取单元格位置
    final colPosition = cellNode.attributes[TableCellBlockKeys.colPosition] as int? ?? 0;
    final rowPosition = cellNode.attributes[TableCellBlockKeys.rowPosition] as int? ?? 0;

    // 计算在表格中的索引位置
    final index = direction == TableDirection.row ? rowPosition : colPosition;

    // 执行操作
    action(tableNode, index, _editorState, direction);
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
      color: Theme.of(context).colorScheme.outlineVariant.withAlpha(128),
    );
  }

  // ============== 撤销 / 重做 ==============

  void _undo() {
    _editorState.undoManager.undo();
  }

  void _redo() {
    _editorState.undoManager.redo();
  }

  // ============== 文本格式化 ==============

  void _toggleBold() {
    _editorState.toggleAttribute(AppFlowyRichTextKeys.bold);
  }

  void _toggleItalic() {
    _editorState.toggleAttribute(AppFlowyRichTextKeys.italic);
  }

  void _toggleUnderline() {
    _editorState.toggleAttribute(AppFlowyRichTextKeys.underline);
  }

  void _toggleStrikethrough() {
    _editorState.toggleAttribute(AppFlowyRichTextKeys.strikethrough);
  }

  // ============== 块级元素 ==============

  void _insertHeading(int level) {
    final selection = _editorState.selection;
    if (selection == null) return;
    _editorState.formatNode(
      selection,
      (node) {
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

  void _insertBulletList() {
    final selection = _editorState.selection;
    if (selection == null) return;
    _editorState.formatNode(
      selection,
      (node) {
        final delta = node.delta?.toJson() ?? [];
        return node.copyWith(
          type: BulletedListBlockKeys.type,
          attributes: {blockComponentDelta: delta},
        );
      },
    );
  }

  void _insertNumberedList() {
    final selection = _editorState.selection;
    if (selection == null) return;
    _editorState.formatNode(
      selection,
      (node) {
        final delta = node.delta?.toJson() ?? [];
        return node.copyWith(
          type: NumberedListBlockKeys.type,
          attributes: {blockComponentDelta: delta},
        );
      },
    );
  }

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

  void _insertQuote() {
    final selection = _editorState.selection;
    if (selection == null) return;
    _editorState.formatNode(
      selection,
      (node) {
        final delta = node.delta?.toJson() ?? [];
        return node.copyWith(
          type: QuoteBlockKeys.type,
          attributes: {blockComponentDelta: delta},
        );
      },
    );
  }

  void _insertCodeBlock() {
    final selection = _editorState.selection;
    if (selection == null) return;
    _editorState.formatNode(
      selection,
      (node) {
        final delta = node.delta?.toJson() ?? [];
        return node.copyWith(
          type: QuoteBlockKeys.type,
          attributes: {blockComponentDelta: delta},
        );
      },
    );
  }

  // ============== 表格 ==============

  /// 表格操作菜单构建器
  ///
  /// 点击表格行/列头时显示操作菜单，支持：
  /// - 添加/删除/复制行
  /// - 添加/删除/复制列
  /// - 清空单元格内容
  Widget _buildTableMenu(
    Node node,
    EditorState editorState,
    int index,
    TableDirection direction,
    VoidCallback? onShow,
    VoidCallback? onHide,
  ) {
    final isRow = direction == TableDirection.row;
    final label = isRow ? '行' : '列';
    final total = isRow
        ? (node.attributes[TableBlockKeys.rowsLen] as int? ?? 0)
        : (node.attributes[TableBlockKeys.colsLen] as int? ?? 0);

    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'add':
            TableActions.add(node, index, editorState, direction);
          case 'delete':
            if (total > (isRow ? 1 : 1)) {
              TableActions.delete(node, index, editorState, direction);
            }
          case 'duplicate':
            TableActions.duplicate(node, index, editorState, direction);
          case 'clear':
            TableActions.clear(node, index, editorState, direction);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'add',
          child: Row(
            children: [
              const Icon(Icons.add, size: 18),
              const SizedBox(width: 8),
              Text('在下方插入${label}', style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'duplicate',
          child: Row(
            children: [
              const Icon(Icons.content_copy, size: 18),
              const SizedBox(width: 8),
              Text('复制此${label}', style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
        if (total > 1)
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 18, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 8),
                Text(
                  '删除此${label}',
                  style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.error),
                ),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'clear',
          child: Row(
            children: [
              const Icon(Icons.clear_all, size: 18),
              const SizedBox(width: 8),
              Text('清空此${label}内容', style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          Icons.more_horiz,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// 保存的选区，用于在对话框关闭后恢复插入位置
  Selection? _savedSelection;

  void _showInsertTableDialog() {
    // 在弹出对话框前保存当前选区，因为对话框会导致编辑器失去焦点
    _savedSelection = _editorState.selection;
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
                      onChanged: (value) =>
                          setState(() => rows = value.round()),
                    ),
                  ),
                  SizedBox(width: 30, child: Text(rows.toString())),
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
                      onChanged: (value) =>
                          setState(() => cols = value.round()),
                    ),
                  ),
                  SizedBox(width: 30, child: Text(cols.toString())),
                ],
              ),
              const SizedBox(height: 16),
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
                                fontWeight:
                                    r == 0 ? FontWeight.bold : null,
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

  Node _createTableNode({required int rows, required int cols}) {
    // 获取屏幕宽度，计算合适的列宽
    final screenWidth = MediaQuery.of(context).size.width;
    final availableWidth = screenWidth - 64; // 减去边距和表格边框
    final colWidth = (availableWidth / cols).clamp(60.0, 200.0); // 最小 60，最大 200
    
    // 先创建所有单元格子节点
    final List<Node> cells = [];
    for (var col = 0; col < cols; col++) {
      for (var row = 0; row < rows; row++) {
        final content = row == 0 ? '标题 ${col + 1}' : '';
        final cell = Node(
          type: TableCellBlockKeys.type,
          attributes: {
            TableCellBlockKeys.rowPosition: row,
            TableCellBlockKeys.colPosition: col,
            TableCellBlockKeys.width: colWidth,
            TableCellBlockKeys.height: 40.0,
          },
          children: [
            paragraphNode(text: content),
          ],
        );
        cells.add(cell);
      }
    }

    // 创建表格节点，通过 children 参数传入单元格
    return Node(
      type: TableBlockKeys.type,
      attributes: {
        TableBlockKeys.colsLen: cols,
        TableBlockKeys.rowsLen: rows,
        TableBlockKeys.colDefaultWidth: colWidth,
        TableBlockKeys.rowDefaultHeight: 40.0,
        TableBlockKeys.colMinimumWidth: 40.0,
        TableBlockKeys.borderWidth: 1.0,
      },
      children: cells,
    );
  }

  void _insertTable({required int rows, required int cols}) {
    try {
      final tableNode = _createTableNode(rows: rows, cols: cols);
      final transaction = _editorState.transaction;

      // 使用保存的选区（对话框关闭后编辑器选区会丢失）
      final selection = _savedSelection ?? _editorState.selection;
      Path insertPath;

      if (selection != null && selection.end.path.isNotEmpty) {
        // 找到选区所在的顶层块节点，在其后插入表格
        final topPath = [selection.end.path.first];
        final topNode = _editorState.getNodeAtPath(topPath);
        if (topNode != null) {
          insertPath = topNode.path.next;
        } else {
          insertPath = [_editorState.document.root.children.length];
        }
      } else {
        // 没有选区，插入到文档末尾
        insertPath = [_editorState.document.root.children.length];
      }

      transaction.insertNode(insertPath, tableNode);
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
      debugPrint('插入表格失败: $e');
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

  // ============== 保存 ==============

  void _saveContent() {
    final markdown = _documentToMarkdown(_editorState.document);
    final updatedNote = widget.note.copyWith(
      content: markdown,
      modifiedAt: DateTime.now(),
    );
    context.read<NotesBloc>().add(UpdateNote(updatedNote));
  }

  void _saveSourceContent() {
    final updatedNote = widget.note.copyWith(
      content: _sourceController.text,
      modifiedAt: DateTime.now(),
    );
    context.read<NotesBloc>().add(UpdateNote(updatedNote));
  }

  // ============== 转换 ==============

  Document _markdownToDocument(String markdown) {
    try {
      if (markdown.trim().isEmpty) {
        return EditorState.blank(withInitialText: true).document;
      }
      return markdownToDocument(markdown);
    } catch (e) {
      return EditorState.blank(withInitialText: true).document;
    }
  }

  String _documentToMarkdown(Document document) {
    try {
      return documentToMarkdown(document);
    } catch (e) {
      return '';
    }
  }

  @override
  void dispose() {
    _sourceController.dispose();
    super.dispose();
  }
}
