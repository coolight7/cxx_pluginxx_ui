// 纯文本降级：规范模型 → 行式文本（Dart 绑定）
//
// 输出与 C++ 绑定逐字节一致（diff 由测试用同一批夹具对比）：不使用语言相关文案，
// 数值一律走 [formatNumber]。
import 'dart:math' as math;

import 'gen/blocks.g.dart';
import 'model.dart';

const int _fallbackDividerWidth = 40;
const int _progressBarCells = 10;

/// 显示列宽（CJK 与全角符号按 2 列，组合字符按 0 列）
int displayWidth(String text) {
  int width = 0;
  for (final int cp in text.runes) {
    if (_isZeroWidth(cp)) {
      continue;
    }
    width += _isWide(cp) ? 2 : 1;
  }
  return width;
}

bool _isWide(int cp) {
  if (cp < 0x1100) {
    return false;
  }
  return (cp >= 0x1100 && cp <= 0x115F) ||
      (cp >= 0x2E80 && cp <= 0x303E) ||
      (cp >= 0x3041 && cp <= 0x33FF) ||
      (cp >= 0x3400 && cp <= 0x4DBF) ||
      (cp >= 0x4E00 && cp <= 0x9FFF) ||
      (cp >= 0xA000 && cp <= 0xA4CF) ||
      (cp >= 0xAC00 && cp <= 0xD7A3) ||
      (cp >= 0xF900 && cp <= 0xFAFF) ||
      (cp >= 0xFE10 && cp <= 0xFE19) ||
      (cp >= 0xFE30 && cp <= 0xFE6F) ||
      (cp >= 0xFF00 && cp <= 0xFF60) ||
      (cp >= 0xFFE0 && cp <= 0xFFE6) ||
      (cp >= 0x1F300 && cp <= 0x1F64F) ||
      (cp >= 0x1F900 && cp <= 0x1F9FF) ||
      (cp >= 0x20000 && cp <= 0x3FFFD);
}

bool _isZeroWidth(int cp) =>
    (cp >= 0x0300 && cp <= 0x036F) ||
    (cp >= 0x200B && cp <= 0x200F) ||
    (cp >= 0x20D0 && cp <= 0x20FF) ||
    (cp >= 0xFE00 && cp <= 0xFE0F) ||
    (cp >= 0xFE20 && cp <= 0xFE2F) ||
    cp == 0xFEFF;

class _Ctx {
  _Ctx(this.width, this.lookup, [this.cellWidth = kDefaultCellWidth]);

  final int width;
  final String Function(String key)? lookup;

  /// 留白换算基准：`Padding` 的左留白（u）按它折算成缩进列数（与 C++ 侧同口径）
  final double cellWidth;

  String text(TextValue value) => value.resolve(lookup: lookup);

  /// 本轮的折行宽度（扣掉当前缩进；<=0 表示不折行）
  int availableWidth(int indent) {
    if (width <= 0) {
      return 0;
    }
    return math.max(1, width - indent);
  }

  /// 派生一个折行宽度更小的上下文（用于缩进后的子树）
  _Ctx withWidth(int nextWidth) => _Ctx(nextWidth, lookup, cellWidth);
}

String _repeat(String unit, int count) {
  if (count <= 0) {
    return '';
  }
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < count; i++) {
    out.write(unit);
  }
  return out.toString();
}

/// 硬折行（按显示列宽切分；宽字符不会被切开）
List<String> wrapLines(String text, int width) {
  final List<String> lines = <String>[];
  if (width <= 0) {
    return <String>[text];
  }
  final List<String> segments = text.split('\n');
  for (final String segment in segments) {
    final StringBuffer current = StringBuffer();
    int used = 0;
    for (final int cp in segment.runes) {
      final int w = _isZeroWidth(cp) ? 0 : (_isWide(cp) ? 2 : 1);
      if (used + w > width && current.isNotEmpty) {
        lines.add(current.toString());
        current.clear();
        used = 0;
      }
      current.writeCharCode(cp);
      used += w;
    }
    lines.add(current.toString());
  }
  return lines;
}

String _linesOf(String text, _Ctx ctx) => wrapLines(text, ctx.width).join('\n');

/// `Padding` 的左留白折算成缩进列数（u → 列，四舍五入；与 C++ 侧同口径）
int _indentColumns(ItemData item, _Ctx ctx) {
  final double cell = ctx.cellWidth > 0 ? ctx.cellWidth : kDefaultCellWidth;
  final double left = item.hasPadding ? item.padding.left : 0;
  if (cell <= 0 || left <= 0) {
    return 0;
  }
  return (left / cell).round();
}

String _indentLines(String text, String prefix) =>
    text.split('\n').map((String line) => '$prefix$line').join('\n');

String _padEnd(String text, int targetWidth) {
  final int pad = targetWidth - displayWidth(text);
  return pad > 0 ? text + _repeat(' ', pad) : text;
}

String _padStart(String text, int targetWidth) {
  final int pad = targetWidth - displayWidth(text);
  return pad > 0 ? _repeat(' ', pad) + text : text;
}

String _alignTo(String text, int targetWidth, String align) {
  if (align == 'end') {
    return _padStart(text, targetWidth);
  }
  if (align == 'center') {
    final int pad = targetWidth - displayWidth(text);
    if (pad > 0) {
      final int left = pad ~/ 2;
      return _repeat(' ', left) + text + _repeat(' ', pad - left);
    }
    return text;
  }
  return _padEnd(text, targetWidth);
}

/// 单个组件 → 文本（返回 null 表示"没有内容可显示"）
String? _itemText(ItemData item, _Ctx ctx) {
  String text(TextValue value) => ctx.text(value);

  switch (item.kind) {
    case 'Text':
      final String value = text(item.text);
      if (value.isEmpty) {
        return null;
      }
      List<String> lines = wrapLines(value, ctx.width);
      if (item.maxLines > 0 && lines.length > item.maxLines) {
        lines = lines.sublist(0, item.maxLines);
      }
      return lines.join('\n');
    case 'Divider':
      return _repeat('-', ctx.width > 0 ? ctx.width : _fallbackDividerWidth);
    case 'Gap':
      return '';
    case 'Button':
      final String label = text(item.label);
      return label.isEmpty ? null : '[$label]';
    case 'Block':
      final String head = text(item.title);
      final String body = _childrenText(item.children, ctx);
      if (head.isEmpty && body.isEmpty) {
        return null;
      }
      if (head.isEmpty) {
        return body;
      }
      return body.isEmpty ? head : '$head\n${_indentLines(body, '  ')}';
    case 'Row':
      final String row = _childrenText(item.children, ctx, separator: ' | ');
      return row.isEmpty ? null : row;
    case 'Column':
    case 'SizedBox':
    case 'Align':
    case 'Expanded':
      final String column = _childrenText(item.children, ctx);
      return column.isEmpty ? null : column;
    case 'Padding':
      // 留白按左留白折算成缩进列数（u → 列，四舍五入）：折行宽度扣掉缩进，每行加前导空格。
      // 与 C++ 侧同口径（见 src/plain_text.cpp 的 Padding 分支）。
      final int indent = _indentColumns(item, ctx);
      final String body =
          _childrenText(item.children, ctx.withWidth(ctx.availableWidth(indent)));
      if (body.isEmpty) {
        return null;
      }
      return indent > 0 ? _indentLines(body, _repeat(' ', indent)) : body;
    case 'Spacer':
      return null;
    case 'Collapse':
      final String head = '${item.expanded ? '[-] ' : '[+] '}${text(item.title)}';
      if (!item.expanded) {
        return head;
      }
      final String body = _childrenText(item.children, ctx);
      return body.isEmpty ? head : '$head\n${_indentLines(body, '  ')}';
    case 'KV':
      int keyWidth = 0;
      for (final KeyValuePair pair in item.pairs) {
        final int width = displayWidth(text(pair.key));
        if (width > keyWidth) {
          keyWidth = width;
        }
      }
      final List<String> lines = <String>[];
      for (final KeyValuePair pair in item.pairs) {
        final String key = text(pair.key);
        final String value = text(pair.value);
        if (key.isEmpty && value.isEmpty) {
          continue;
        }
        lines.add('${_padEnd(key, keyWidth)}${item.sep}$value');
      }
      return lines.isEmpty ? null : lines.join('\n');
    case 'Table':
      return _tableText(item, ctx);
    case 'Tree':
      return _treeText(item, ctx);
    case 'Progress':
      final double total = item.total > 0 ? item.total : 100;
      int filled = (_progressBarCells * item.value / total + 0.5).floor();
      filled = filled < 0 ? 0 : (filled > _progressBarCells ? _progressBarCells : filled);
      String bar =
          '[${_repeat('#', filled)}${_repeat('-', _progressBarCells - filled)}]';
      final String label = text(item.label);
      if (item.showValue) {
        bar = '$bar ${formatNumber(item.value)}${item.unit}';
      }
      return label.isEmpty ? bar : '$label: $bar';
    case 'Badge':
      final String value = text(item.text);
      return value.isEmpty ? null : '[$value]';
    case 'Control':
      final String label = text(item.label);
      final String value = _controlValueText(item, ctx);
      if (label.isEmpty) {
        return value.isEmpty ? null : value;
      }
      return '$label: $value';
    case 'Markdown':
      return item.markdown.isEmpty ? null : _linesOf(item.markdown, ctx);
    case 'Icon':
      final String value = item.glyph.isNotEmpty
          ? item.glyph
          : (item.icon.isNotEmpty ? item.icon : text(item.alt));
      return value.isEmpty ? null : value;
    case 'Stack':
      for (int i = item.children.length - 1; i >= 0; i--) {
        final String? rendered = _itemText(item.children[i], ctx);
        if (null != rendered) {
          return rendered;
        }
      }
      return null;
    case 'Image':
      final String alt = text(item.alt);
      return alt.isEmpty ? null : alt;
    case 'Diff':
      final List<String> lines = <String>[];
      if (item.path.isNotEmpty) {
        lines.add('@@ ${item.path}');
      }
      for (final String line in item.oldStr.split('\n')) {
        if (line.isNotEmpty) {
          lines.add('- $line');
        }
      }
      for (final String line in item.newStr.split('\n')) {
        if (line.isNotEmpty) {
          lines.add('+ $line');
        }
      }
      return lines.isEmpty ? null : lines.join('\n');
    case 'Sparkline':
      return _sparklineText(item);
    case 'Diagram':
      return item.mermaid.isEmpty ? null : _linesOf(item.mermaid, ctx);
    case 'musicxx.Shader':
      return item.fallback.isEmpty ? null : item.fallback;
    default:
      return item.fallback.isEmpty ? null : item.fallback;
  }
}

String _childrenText(List<ItemData> children, _Ctx ctx, {String? separator}) {
  final List<String> parts = <String>[];
  for (final ItemData child in children) {
    final String? rendered = _itemText(child, ctx);
    if (null != rendered) {
      parts.add(rendered);
    }
  }
  return parts.join(separator ?? '\n');
}

String _controlValueText(ItemData item, _Ctx ctx) {
  final Object? raw = item.controlValue;
  if (item.control == 'checkbox' || item.control == 'switch') {
    return raw == true ? 'true' : 'false';
  }
  if (item.control == 'buttons' || item.control == 'select') {
    for (final ControlOption option in item.options) {
      if (option.value == raw && option.label.isNotEmpty) {
        return ctx.text(option.label);
      }
    }
  }
  return stringifyValue(raw);
}

String? _tableText(ItemData item, _Ctx ctx) {
  int columns = item.columns.length;
  for (final List<TableCell> row in item.rows) {
    if (row.length > columns) {
      columns = row.length;
    }
  }
  if (columns == 0) {
    return null;
  }
  final List<String> headers = List<String>.filled(columns, '');
  final List<String> aligns = List<String>.filled(columns, 'start');
  for (int c = 0; c < item.columns.length; c++) {
    headers[c] = ctx.text(item.columns[c].title);
    aligns[c] = item.columns[c].align;
  }
  final List<List<String>> cells = <List<String>>[];
  for (final List<TableCell> row in item.rows) {
    final List<String> line = List<String>.filled(columns, '');
    for (int c = 0; c < row.length; c++) {
      line[c] = ctx.text(row[c].text);
    }
    cells.add(line);
  }
  final List<int> widths = <int>[];
  for (int c = 0; c < columns; c++) {
    widths.add(displayWidth(headers[c]));
  }
  for (final List<String> row in cells) {
    for (int c = 0; c < columns; c++) {
      final int width = displayWidth(row[c]);
      if (width > widths[c]) {
        widths[c] = width;
      }
    }
  }
  int total = (columns - 1) * 2;
  for (final int width in widths) {
    total += width;
  }

  final List<String> lines = <String>[];
  if (item.header) {
    final StringBuffer head = StringBuffer();
    for (int c = 0; c < columns; c++) {
      if (c > 0) {
        head.write('  ');
      }
      head.write(_alignTo(headers[c], widths[c], aligns[c]));
    }
    lines.add(head.toString());
    lines.add(_repeat('-', total));
  }
  for (final List<String> row in cells) {
    final StringBuffer line = StringBuffer();
    for (int c = 0; c < columns; c++) {
      if (c > 0) {
        line.write('  ');
      }
      line.write(_alignTo(row[c], widths[c], aligns[c]));
    }
    lines.add(line.toString());
  }
  return lines.join('\n');
}

String? _treeText(ItemData item, _Ctx ctx) {
  final List<String> lines = <String>[];
  void walk(List<TreeNode> nodes, String prefix, bool root) {
    for (int i = 0; i < nodes.length; i++) {
      final TreeNode node = nodes[i];
      final bool last = i + 1 == nodes.length;
      if (item.connector) {
        lines.add('$prefix${last ? '`- ' : '|- '}${ctx.text(node.label)}');
      } else {
        lines.add('${prefix.isEmpty && root ? '' : '$prefix  '}${ctx.text(node.label)}');
      }
      if (node.children.isNotEmpty) {
        walk(node.children, item.connector ? '$prefix${last ? '   ' : '|  '}' : prefix, false);
      }
    }
  }

  walk(item.nodes, '', true);
  return lines.isEmpty ? null : lines.join('\n');
}

String? _sparklineText(ItemData item) {
  if (item.data.isEmpty) {
    return null;
  }
  const List<String> blocks = <String>[
    '\u2581', '\u2582', '\u2583', '\u2584', '\u2585', '\u2586', '\u2587', '\u2588',
  ];
  const List<String> bars = <String>[
    '\u258F', '\u258E', '\u258D', '\u258C', '\u258B', '\u258A', '\u2589', '\u2588',
  ];
  double minValue = item.data.first;
  double maxValue = item.data.first;
  if (item.hasMin) {
    minValue = item.minValue;
  } else {
    for (final double v in item.data) {
      if (v < minValue) {
        minValue = v;
      }
    }
  }
  if (item.hasMax) {
    maxValue = item.maxValue;
  } else {
    for (final double v in item.data) {
      if (v > maxValue) {
        maxValue = v;
      }
    }
  }
  final double span = maxValue > minValue ? maxValue - minValue : 1;
  final StringBuffer art = StringBuffer();
  for (final double v in item.data) {
    final double ratio = (v - minValue) / span;
    int level = (ratio * 7 + 0.5).floor();
    level = level < 0 ? 0 : (level > 7 ? 7 : level);
    art.write(item.glyphStyle == 'bar' ? bars[level] : blocks[level]);
  }
  if (item.showLast) {
    art.write(' ');
    art.write(formatNumber(item.data.last));
  }
  return art.toString();
}

/// 组件列表 → 纯文本
String plainText(List<ItemData> items, {int width = 0, String Function(String key)? lookup}) {
  final _Ctx ctx = _Ctx(width, lookup);
  final List<String> parts = <String>[];
  for (final ItemData item in items) {
    final String? rendered = _itemText(item, ctx);
    if (null != rendered) {
      parts.add(rendered);
    }
  }
  return parts.join('\n');
}

/// 单个组件 → 纯文本
String plainTextItem(ItemData item, {int width = 0, String Function(String key)? lookup}) =>
    _itemText(item, _Ctx(width, lookup)) ?? '';

/// 整份内容 → 纯文本（标题 / 副标题在前）
String plainTextDocument(UiDocument doc, {int width = 0, String Function(String key)? lookup}) {
  final _Ctx ctx = _Ctx(width, lookup);
  final List<String> parts = <String>[];
  final String title = ctx.text(doc.title);
  if (title.isNotEmpty) {
    parts.add(title);
  }
  final String subtitle = ctx.text(doc.subtitle);
  if (subtitle.isNotEmpty) {
    parts.add(subtitle);
  }
  for (final ItemData item in doc.blocks) {
    final String? rendered = _itemText(item, ctx);
    if (null != rendered) {
      parts.add(rendered);
    }
  }
  return parts.join('\n');
}
