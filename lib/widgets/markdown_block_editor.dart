import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

class MarkdownBlockEditor extends StatefulWidget {
  const MarkdownBlockEditor({
    required this.controller,
    this.errorText,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  State<MarkdownBlockEditor> createState() => _MarkdownBlockEditorState();
}

class _MarkdownBlockEditorState extends State<MarkdownBlockEditor> {
  final _activeKey = GlobalKey();
  final _focusNode = FocusNode();
  late final List<_MarkdownBlock> _blocks;
  late TextEditingController _activeController;
  late int _activeIndex;
  bool _settingActiveText = false;

  @override
  void initState() {
    super.initState();
    _blocks = _parseBlocks(widget.controller.text);
    if (_blocks.isEmpty) _blocks.add(_MarkdownBlock(''));
    if (_blocks.last.raw.trim().isNotEmpty) _blocks.add(_MarkdownBlock(''));
    _activeIndex = _blocks.length - 1;
    _activeController = TextEditingController(text: _blocks[_activeIndex].raw)
      ..addListener(_activeTextChanged);
  }

  @override
  void dispose() {
    _activeController
      ..removeListener(_activeTextChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _activeTextChanged() {
    if (_settingActiveText) return;
    _blocks[_activeIndex].raw = _activeController.text;
    _syncDocument();
    if (mounted) setState(() {});
  }

  void _syncDocument() {
    final text = _blocks
        .map((block) => block.raw.trimRight())
        .where((raw) => raw.trim().isNotEmpty)
        .join('\n\n');
    widget.controller.value = widget.controller.value.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
    widget.onChanged?.call(text);
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF0D2A36),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.errorText == null
                ? Colors.white.withValues(alpha: .1)
                : Theme.of(context).colorScheme.error,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildToolbar(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                itemCount: _blocks.length,
                itemBuilder: (context, index) => index == _activeIndex
                    ? _buildActiveBlock()
                    : _buildRenderedBlock(index),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 9, 16, 11),
              decoration: const BoxDecoration(
                color: Color(0xFF0A222D),
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(15)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.errorText ??
                          'Enter 完成当前块 · Shift+Enter 块内换行 · 点击内容重新编辑',
                      style: TextStyle(
                        color: widget.errorText == null
                            ? Colors.white.withValues(alpha: .5)
                            : Theme.of(context).colorScheme.error,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_blocks.where((block) => block.raw.trim().isNotEmpty).length} 个内容块',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .4),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildToolbar() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF173E4C), Color(0xFF1D354F)],
          ),
          borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
        ),
        child: Row(
          children: [
            const Icon(Icons.view_agenda_outlined, size: 18),
            const SizedBox(width: 8),
            const Text('块编辑器', style: TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            _toolButton('标题', Icons.format_size,
                () => _insertMarkdown('## ', '', '小标题')),
            _toolButton('粗体', Icons.format_bold,
                () => _insertMarkdown('**', '**', '重点')),
            _toolButton('列表', Icons.format_list_bulleted,
                () => _insertMarkdown('- ', '', '列表项')),
            _toolButton('引用', Icons.format_quote,
                () => _insertMarkdown('> ', '', '引用')),
            _toolButton(
                '行内代码', Icons.code, () => _insertMarkdown('`', '`', '代码')),
            _toolButton('代码块', Icons.data_object, _insertCodeBlock),
          ],
        ),
      );

  Widget _buildActiveBlock() => Padding(
        key: _activeKey,
        padding: const EdgeInsets.only(bottom: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF123B49),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0xFF68D9CE), width: 1.4),
            boxShadow: const [
              BoxShadow(color: Color(0x3300D7C4), blurRadius: 16),
            ],
          ),
          child: Focus(
            onKeyEvent: _handleKeyEvent,
            child: TextField(
              controller: _activeController,
              focusNode: _focusNode,
              cursorColor: const Color(0xFF8FF5E9),
              cursorWidth: 2.2,
              cursorHeight: 22,
              keyboardType: TextInputType.multiline,
              minLines: _isFencedBlock(_activeController.text) ? 5 : 1,
              maxLines: null,
              decoration: const InputDecoration(
                hintText: '输入 Markdown，按 Enter 完成这一块…',
                border: InputBorder.none,
                filled: false,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              style: TextStyle(
                height: 1.55,
                fontSize: 15.5,
                fontFamily:
                    _isFencedBlock(_activeController.text) ? 'monospace' : null,
              ),
            ),
          ),
        ),
      );

  Widget _buildRenderedBlock(int index) {
    final raw = _blocks[index].raw;
    if (raw.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _activateBlock(index),
          hoverColor: Colors.white.withValues(alpha: .055),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: MarkdownBody(
                    data: raw,
                    styleSheet: _markdownStyle(context),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 15,
                    color: Colors.white.withValues(alpha: .24),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) {
      if (event.logicalKey == LogicalKeyboardKey.backspace &&
          _activeController.text.isEmpty &&
          _activeIndex > 0) {
        _removeEmptyAndEditPrevious();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;

    final selection = _activeController.selection;
    if (!selection.isValid || selection.end != _activeController.text.length) {
      return KeyEventResult.ignored;
    }
    final raw = _activeController.text;
    if (_hasUnclosedFence(raw)) return KeyEventResult.ignored;

    final listPrefix = _nextListPrefix(raw);
    if (listPrefix != null && raw.trim() == listPrefix.trim()) {
      _activeController.clear();
      _commitActive();
      return KeyEventResult.handled;
    }
    _commitActive(nextRaw: listPrefix ?? '');
    return KeyEventResult.handled;
  }

  void _commitActive({String nextRaw = ''}) {
    final current = _activeController.text.trimRight();
    _blocks[_activeIndex].raw = current;
    if (current.trim().isEmpty) {
      _blocks[_activeIndex].raw = nextRaw;
    } else {
      _blocks.insert(_activeIndex + 1, _MarkdownBlock(nextRaw));
      _activeIndex++;
    }
    _setActiveText(_blocks[_activeIndex].raw);
    _syncDocument();
    setState(() {});
    _focusActive(atEnd: true);
  }

  void _activateBlock(int index) {
    final activeRaw = _activeController.text.trimRight();
    _blocks[_activeIndex].raw = activeRaw;
    if (activeRaw.trim().isEmpty && _blocks.length > 1) {
      final oldActive = _activeIndex;
      _blocks.removeAt(oldActive);
      if (oldActive < index) index--;
    }
    _activeIndex = index;
    _setActiveText(_blocks[index].raw);
    _syncDocument();
    setState(() {});
    _focusActive(atEnd: true);
  }

  void _removeEmptyAndEditPrevious() {
    _blocks.removeAt(_activeIndex);
    _activeIndex--;
    _setActiveText(_blocks[_activeIndex].raw);
    _syncDocument();
    setState(() {});
    _focusActive(atEnd: true);
  }

  void _setActiveText(String text) {
    _settingActiveText = true;
    _activeController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _settingActiveText = false;
  }

  void _focusActive({bool atEnd = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      if (atEnd) {
        _activeController.selection = TextSelection.collapsed(
          offset: _activeController.text.length,
        );
      }
      final activeContext = _activeKey.currentContext;
      if (activeContext != null) {
        Scrollable.ensureVisible(
          activeContext,
          duration: const Duration(milliseconds: 180),
          alignment: .7,
        );
      }
    });
  }

  Widget _toolButton(String tooltip, IconData icon, VoidCallback onPressed) =>
      IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
      );

  void _insertMarkdown(String prefix, String suffix, String placeholder) {
    final selection = _activeController.selection;
    final hasSelection = selection.isValid && selection.start != selection.end;
    final start =
        selection.isValid ? selection.start : _activeController.text.length;
    final end = selection.isValid ? selection.end : start;
    final selected = hasSelection
        ? _activeController.text.substring(start, end)
        : placeholder;
    final replacement = '$prefix$selected$suffix';
    _activeController.value = TextEditingValue(
      text: _activeController.text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    _focusNode.requestFocus();
  }

  void _insertCodeBlock() {
    final selection = _activeController.selection;
    final hasSelection = selection.isValid && selection.start != selection.end;
    final start =
        selection.isValid ? selection.start : _activeController.text.length;
    final end = selection.isValid ? selection.end : start;
    final selected =
        hasSelection ? _activeController.text.substring(start, end) : '在这里输入代码';
    final replacement = '```\n$selected\n```';
    _activeController.value = TextEditingValue(
      text: _activeController.text.replaceRange(start, end, replacement),
      selection: TextSelection(
        baseOffset: start + 4,
        extentOffset: start + 4 + selected.length,
      ),
    );
    _focusNode.requestFocus();
  }

  String? _nextListPrefix(String raw) {
    if (raw.contains('\n')) return null;
    final unordered = RegExp(r'^(\s*[-*+]\s+)').firstMatch(raw);
    if (unordered != null) return unordered.group(1);
    final ordered = RegExp(r'^(\s*)(\d+)([.)]\s+)').firstMatch(raw);
    if (ordered == null) return null;
    final next = int.parse(ordered.group(2)!) + 1;
    return '${ordered.group(1)}$next${ordered.group(3)}';
  }

  bool _isFencedBlock(String raw) =>
      RegExp(r'^\s*(```|~~~)', multiLine: true).hasMatch(raw);

  bool _hasUnclosedFence(String raw) {
    final fences =
        RegExp(r'^\s*(```+|~~~+)', multiLine: true).allMatches(raw).length;
    return fences.isOdd;
  }

  MarkdownStyleSheet _markdownStyle(BuildContext context) => MarkdownStyleSheet(
        p: const TextStyle(height: 1.62, fontSize: 15.5),
        h1: const TextStyle(
          color: Color(0xFFFFD17E),
          fontSize: 25,
          fontWeight: FontWeight.w700,
        ),
        h2: const TextStyle(
          color: Color(0xFF82E0D5),
          fontSize: 21,
          fontWeight: FontWeight.w700,
        ),
        h3: const TextStyle(
          color: Color(0xFFBCC8FF),
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        blockquoteDecoration: BoxDecoration(
          color: const Color(0xFF092630),
          borderRadius: BorderRadius.circular(8),
          border: const Border(
            left: BorderSide(color: Color(0xFF61D1C5), width: 4),
          ),
        ),
        codeblockDecoration: BoxDecoration(
          color: const Color(0xFF061D27),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        code: const TextStyle(
          color: Color(0xFFFFC9E8),
          backgroundColor: Color(0xFF061D27),
          fontFamily: 'monospace',
        ),
      );
}

class _MarkdownBlock {
  _MarkdownBlock(this.raw);

  String raw;
}

List<_MarkdownBlock> _parseBlocks(String markdown) {
  final normalized = markdown.replaceAll('\r\n', '\n').trim();
  if (normalized.isEmpty) return [];
  final blocks = <_MarkdownBlock>[];
  final current = <String>[];
  var inFence = false;

  void flush() {
    final raw = current.join('\n').trimRight();
    if (raw.trim().isNotEmpty) blocks.add(_MarkdownBlock(raw));
    current.clear();
  }

  for (final line in normalized.split('\n')) {
    final isFence = RegExp(r'^\s*(```+|~~~+)').hasMatch(line);
    if (isFence) {
      current.add(line);
      inFence = !inFence;
      if (!inFence) flush();
      continue;
    }
    if (!inFence && line.trim().isEmpty) {
      flush();
      continue;
    }
    current.add(line);
  }
  flush();
  return blocks;
}
