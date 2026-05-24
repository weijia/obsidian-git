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

    return Column(
      children: [
        // 工具栏
        if (!widget.readOnly) _buildToolbar(),
        // 编辑器
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: AppFlowyEditor(
              editorState: _editorState,
              editable: !widget.readOnly,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
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
              tooltip: '标题',
              onPressed: () => _insertHeading(1),
            ),
            _buildToolbarButton(
              icon: Icons.format_size,
              tooltip: '副标题',
              onPressed: () => _insertHeading(2),
            ),
            const SizedBox(width: 8),
            const VerticalDivider(),
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
            const VerticalDivider(),
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
            const VerticalDivider(),
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
              onPressed: _insertTable,
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
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 20),
        onPressed: onPressed,
        splashRadius: 20,
      ),
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

  void _insertTable() {
    final selection = _editorState.selection;
    if (selection == null) return;

    // 创建表格 - 使用正确的 AppFlowy Editor API
    final transaction = _editorState.transaction;
    
    // 创建表格节点
    final tableNode = Node(
      type: 'table',
      children: [
        for (var i = 0; i < 3; i++)
          Node(
            type: 'table_row',
            children: [
              for (var j = 0; j < 3; j++)
                Node(
                  type: 'table_cell',
                  children: [
                    Node(type: 'paragraph'),
                  ],
                ),
            ],
          ),
      ],
    );
    
    transaction.insertNode(selection.start.path, tableNode);
    _editorState.apply(transaction);
  }

  void _insertImage() {
    // TODO: 实现图片插入
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('图片插入功能即将推出')),
    );
  }

  void _insertLink() {
    // TODO: 实现链接插入
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
      // 使用 AppFlowy Editor 的 Markdown 解析器
      // markdownToDocument 直接返回 Document
      return markdownToDocument(markdown);
    } catch (e) {
      // 如果解析失败，返回空文档
      return Document.blank();
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
