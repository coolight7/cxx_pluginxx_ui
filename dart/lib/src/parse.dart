// 组件描述 → 规范模型（解析与序列化，Dart 绑定）
//
// 与 C++ 绑定同口径：未知组件 / 未知字段 / 未知枚举值 / 超限内容都不使整份描述失效，
// 按"跳过 / 默认值 / 截断"处理并记进 [ParseReport]。
import 'capabilities.dart';
import 'gen/blocks.g.dart';
import 'model.dart';

/// 解析过程中的提示（客户端记日志；不影响结果）
class ParseReport {
  final List<String> warnings = <String>[];

  /// 是否存在任何截断
  bool truncated = false;

  void warn(String message) => warnings.add(message);
}

Map<String, Object?>? _asMap(Object? value) =>
    value is Map ? value.cast<String, Object?>() : null;

String _str(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  return value is String ? value : '';
}

bool _has(Map<String, Object?> json, String key) =>
    json.containsKey(key) && null != json[key];

double _num(Map<String, Object?> json, String key, double fallback) {
  final Object? value = json[key];
  return value is num ? value.toDouble() : fallback;
}

bool _bool(Map<String, Object?> json, String key, bool fallback) {
  final Object? value = json[key];
  return value is bool ? value : fallback;
}

/// 枚举字段：忽略大小写匹配生成表，未命中用默认值
String _enum(Map<String, Object?> json, String key, List<String> values, String fallback) {
  final String raw = _str(json, key);
  if (raw.isEmpty) {
    return fallback;
  }
  for (final String value in values) {
    if (value.toLowerCase() == raw.toLowerCase()) {
      return value;
    }
  }
  return fallback;
}

String _tone(Map<String, Object?> json, String key, [String fallback = 'normal']) =>
    _enum(json, key, kEnumTone, fallback);

String _clampBytes(String text, int maxBytes) {
  if (maxBytes <= 0 || text.length <= maxBytes) {
    return text;
  }
  // Dart 字符串按 UTF-16 计，按字符边界截断不会切坏代理对
  int cut = maxBytes;
  if (cut > 0 && cut < text.length) {
    final int unit = text.codeUnitAt(cut);
    if (unit >= 0xDC00 && unit <= 0xDFFF) {
      cut -= 1;
    }
  }
  return text.substring(0, cut);
}

TextValue _textValue(Object? value) {
  if (value is String) {
    return TextValue.of(value);
  }
  final Map<String, Object?>? map = _asMap(value);
  if (null == map) {
    if (value is num || value is bool) {
      return TextValue.of(stringifyValue(value));
    }
    return TextValue.empty;
  }
  return TextValue(
    key: _str(map, 'key'),
    fallback: _str(map, 'fallback'),
    args: map['args'],
  );
}

SizeValue _sizeValue(Object? value, ParseReport? report, String what) {
  if (value is num) {
    final double v = value.toDouble();
    if (v < 0) {
      report?.warn('$what 给了负值 ${formatNumber(v)}，按 0 处理');
      return const SizeValue.value(0);
    }
    return SizeValue.value(v);
  }
  if (value is String) {
    final String text = value.toLowerCase();
    if (text == 'auto' || text == 'gap') {
      return SizeValue.autoValue;
    }
    report?.warn('$what 的尺寸写法 `$value` 无法识别，按 auto 处理');
    return SizeValue.autoValue;
  }
  final Map<String, Object?>? map = _asMap(value);
  if (null != map && map.containsKey('percent')) {
    final Object? percent = map['percent'];
    final double p = percent is num ? percent.toDouble() : 0;
    if (p < 0) {
      report?.warn('$what 的 percent 为负，按 0 处理');
      return const SizeValue.percent(0);
    }
    return SizeValue.percent(p);
  }
  return SizeValue.autoValue;
}

Edges _edges(Object? value, ParseReport? report, String what) {
  if (value is num) {
    final double v = value.toDouble();
    if (v < 0) {
      report?.warn('$what 给了负值 ${formatNumber(v)}，按 0 处理');
      return Edges.zero;
    }
    return Edges.all(v);
  }
  final Map<String, Object?>? map = _asMap(value);
  if (null == map) {
    return Edges.zero;
  }
  double pick(String key, double fallback) {
    final Object? raw = map[key];
    if (raw is! num) {
      return fallback;
    }
    final double v = raw.toDouble();
    if (v < 0) {
      report?.warn('$what.$key 给了负值，按 0 处理');
      return 0;
    }
    return v;
  }

  final double all = pick('all', 0);
  final double horizontal = pick('horizontal', all);
  final double vertical = pick('vertical', all);
  return Edges(
    left: pick('left', horizontal),
    top: pick('top', vertical),
    right: pick('right', horizontal),
    bottom: pick('bottom', vertical),
  );
}

UiAction? _action(Object? value) {
  if (value is String) {
    return UiAction(kind: ActionKind.dispatch, name: value);
  }
  final Map<String, Object?>? map = _asMap(value);
  if (null == map) {
    return null;
  }
  final String kind = _enum(map, 'kind', kEnumActionKind, 'none');
  switch (kind) {
    case 'dispatch':
      return UiAction(kind: ActionKind.dispatch, name: _str(map, 'name'), args: map['args']);
    case 'route':
      return UiAction(kind: ActionKind.route, route: _str(map, 'route'));
    case 'command':
      return UiAction(kind: ActionKind.command, name: _str(map, 'name'), args: map['args']);
    default:
      return null;
  }
}

class _Ctx {
  _Ctx(this.limits, this.report);

  final Limits limits;
  final ParseReport? report;

  void warn(String message) => report?.warn(message);

  void truncate(String message) {
    report
      ?..warn(message)
      ..truncated = true;
  }
}

ItemData _parseBlockImpl(Object? value, _Ctx ctx, int depth) {
  final Map<String, Object?>? json = _asMap(value);
  if (null == json) {
    final ItemData item = ItemData();
    item.known = false;
    return item;
  }

  final String? canonical = canonicalKind(_str(json, 'kind'));
  if (null == canonical) {
    final ItemData item = ItemData();
    item.known = false;
    item.fallback = _str(json, 'fallback');
    return item;
  }

  final ItemData item = ItemData(kind: canonical);
  item.id = _str(json, 'id');
  item.fallback = _str(json, 'fallback');
  item.action = _action(json['action']);

  if (_has(json, 'text')) {
    final Object? raw = json['text'];
    item.text = raw is String
        ? TextValue.of(_clampBytes(raw, ctx.limits.maxTextBytes))
        : _textValue(raw);
  }

  List<ItemData> children(String key, String what) {
    final Object? raw = json[key];
    if (raw is! List) {
      return <ItemData>[];
    }
    // 顶层块算第 1 层：块自身在第 depth 层（0 起），子块在第 depth+1 层
    if (depth >= ctx.limits.maxDepth) {
      ctx.truncate('$what 超过层级上限 ${ctx.limits.maxDepth}，子块被丢弃');
      return <ItemData>[];
    }
    final int count = raw.length > ctx.limits.maxItems ? ctx.limits.maxItems : raw.length;
    if (count < raw.length) {
      ctx.truncate('$what 的子块超过上限 ${ctx.limits.maxItems}，已截断');
    }
    return <ItemData>[
      for (int i = 0; i < count; i++) _parseBlockImpl(raw[i], ctx, depth + 1),
    ];
  }

  switch (canonical) {
    case 'Text':
      item.textType = _enum(json, 'type', kEnumTextType, 'body');
      item.tone = _tone(json, 'tone');
      item.bold = _bool(json, 'bold', false);
      item.dim = _bool(json, 'dim', false);
      item.mono = _bool(json, 'mono', false);
      item.wrap = _bool(json, 'wrap', true);
      item.maxLines = _num(json, 'maxLines', 0).toInt();
      item.align = _enum(json, 'align', kEnumAlignH, 'start');
      return item;
    case 'Divider':
      return item;
    case 'Gap':
      item.size = _has(json, 'size')
          ? _sizeValue(json['size'], ctx.report, 'Gap.size')
          : SizeValue.autoValue;
      return item;
    case 'Button':
      item.label = _textValue(json['label']);
      item.variant = _enum(json, 'variant', kEnumButtonVariant, 'secondary');
      item.icon = _str(json, 'icon');
      item.disabled = _bool(json, 'disabled', false);
      return item;
    case 'Block':
      item.title = _textValue(json['title']);
      item.variant = _enum(json, 'variant', kEnumBlockVariant, 'card');
      if (_has(json, 'padding')) {
        item.padding = _edges(json['padding'], ctx.report, 'Block.padding');
        item.hasPadding = true;
      }
      if (_has(json, 'margin')) {
        item.margin = _edges(json['margin'], ctx.report, 'Block.margin');
        item.hasMargin = true;
      }
      item.children = children('children', 'Block.children');
      return item;
    case 'Row':
    case 'Column':
      if (_has(json, 'gap')) {
        item.gap = _sizeValue(json['gap'], ctx.report, '${item.kind}.gap');
        item.hasGap = true;
      }
      item.main = _enum(json, 'main', kEnumMainAxis, 'start');
      item.cross = _enum(json, 'cross', kEnumAlignHV, 'start');
      item.children = children('children', '${item.kind}.children');
      return item;
    case 'Expanded':
    case 'Spacer':
      final int flex = _num(json, 'flex', 1).toInt();
      if (flex < 1) {
        ctx.warn('${item.kind}.flex 小于 1 没有意义，按 1 处理');
        item.flex = 1;
      } else {
        item.flex = flex;
      }
      if (canonical == 'Expanded') {
        item.children = children('children', 'Expanded.children');
      }
      return item;
    case 'SizedBox':
      if (_has(json, 'width')) {
        item.width = _sizeValue(json['width'], ctx.report, 'SizedBox.width');
      }
      if (_has(json, 'height')) {
        item.height = _sizeValue(json['height'], ctx.report, 'SizedBox.height');
      }
      item.aspect = _num(json, 'aspect', 0);
      item.children = children('children', 'SizedBox.children');
      return item;
    case 'Padding':
      item.padding = _edges(json['padding'], ctx.report, 'Padding.padding');
      item.hasPadding = true;
      item.children = children('children', 'Padding.children');
      return item;
    case 'Align':
      item.align = _enum(json, 'align', kEnumAlignHV, 'center');
      item.vertical = _enum(json, 'vertical', kEnumAlignHV, 'center');
      item.children = children('children', 'Align.children');
      return item;
    case 'Collapse':
      item.title = _textValue(json['title']);
      item.expanded = _bool(json, 'expanded', true);
      item.children = children('children', 'Collapse.children');
      return item;
    case 'KV':
      item.pairs = _pairs(json['pairs'], ctx, 'KV.pairs');
      item.sep = _has(json, 'sep') ? _str(json, 'sep') : ' : ';
      item.keyWidth = _has(json, 'keyWidth')
          ? _sizeValue(json['keyWidth'], ctx.report, 'KV.keyWidth')
          : SizeValue.autoValue;
      return item;
    case 'Table':
      item.header = _bool(json, 'header', true);
      item.columns = _columns(json['columns'], ctx, 'Table.columns');
      item.rows = _rows(json['rows'], ctx, 'Table.rows');
      return item;
    case 'Tree':
      item.connector = _bool(json, 'connector', true);
      item.nodes = _nodes(json['nodes'], ctx, 'Tree.nodes');
      return item;
    case 'Progress':
      item.value = _num(json, 'value', 0);
      item.total = _num(json, 'total', 100);
      item.label = _textValue(json['label']);
      item.unit = _has(json, 'unit') ? _str(json, 'unit') : '%';
      item.showValue = _bool(json, 'showValue', true);
      item.tone = _tone(json, 'tone', 'accent');
      item.thresholds = _thresholds(json['thresholds'], ctx);
      if (_has(json, 'width')) {
        item.width = _sizeValue(json['width'], ctx.report, 'Progress.width');
      }
      return item;
    case 'Badge':
      item.tone = _tone(json, 'tone', 'accent');
      return item;
    case 'Control':
      item.control = _enum(json, 'control', kEnumControlKind, '');
      item.label = _textValue(json['label']);
      item.help = _textValue(json['help']);
      item.options = _options(json['options'], ctx, 'Control.options');
      item.controlValue = json['value'];
      item.disabled = _bool(json, 'disabled', false);
      item.integer = _bool(json, 'integer', false);
      item.multiline = _bool(json, 'multiline', false);
      if (_has(json, 'min')) {
        item.hasMin = true;
        item.minValue = _num(json, 'min', 0);
      }
      if (_has(json, 'max')) {
        item.hasMax = true;
        item.maxValue = _num(json, 'max', 0);
      }
      if (_has(json, 'step')) {
        item.hasStep = true;
        item.step = _num(json, 'step', 0);
      }
      return item;
    case 'Markdown':
      final String source = _str(json, 'text');
      item.markdown = _clampBytes(source, ctx.limits.maxTextBytes);
      if (item.markdown.length < source.length) {
        ctx.truncate('Markdown 文本超过长度上限，已截断');
      }
      return item;
    case 'Icon':
      item.icon = _str(json, 'name');
      item.glyph = _str(json, 'glyph');
      item.tone = _tone(json, 'tone');
      item.alt = _textValue(json['alt']);
      if (_has(json, 'size')) {
        item.size = _sizeValue(json['size'], ctx.report, 'Icon.size');
      }
      return item;
    case 'Stack':
      item.align = _enum(json, 'align', kEnumAlignHV, 'start');
      item.vertical = _enum(json, 'vertical', kEnumAlignHV, 'start');
      item.children = children('children', 'Stack.children');
      return item;
    case 'Image':
      item.source = _has(json, 'source') ? _str(json, 'source') : 'file';
      item.src = _str(json, 'src');
      item.aspect = _num(json, 'aspect', 0);
      item.radius = _num(json, 'radius', 0);
      item.fit = _enum(json, 'fit', kEnumImageFit, 'contain');
      item.alt = _textValue(json['alt']);
      if (_has(json, 'width')) {
        item.width = _sizeValue(json['width'], ctx.report, 'Image.width');
      }
      if (_has(json, 'height')) {
        item.height = _sizeValue(json['height'], ctx.report, 'Image.height');
      }
      return item;
    case 'Diff':
      item.path = _clampBytes(_str(json, 'path'), ctx.limits.maxTextBytes);
      item.oldStr = _clampBytes(_str(json, 'oldStr'), ctx.limits.maxTextBytes);
      item.newStr = _clampBytes(_str(json, 'newStr'), ctx.limits.maxTextBytes);
      return item;
    case 'Sparkline':
      item.data = _numbers(json['data'], ctx, 'Sparkline.data');
      item.glyphHeight = _num(json, 'height', 1).toInt();
      item.glyphStyle = _enum(json, 'glyphStyle', kEnumSparkStyle, 'block');
      item.tone = _tone(json, 'tone', 'accent');
      item.showLast = _bool(json, 'showLast', true);
      item.colors = _tones(json['colors'], ctx);
      if (_has(json, 'min')) {
        item.hasMin = true;
        item.minValue = _num(json, 'min', 0);
      }
      if (_has(json, 'max')) {
        item.hasMax = true;
        item.maxValue = _num(json, 'max', 0);
      }
      return item;
    case 'Diagram':
      item.mermaid = _clampBytes(_str(json, 'mermaid'), ctx.limits.maxTextBytes);
      return item;
    case 'musicxx.Shader':
      item.bundle = _str(json, 'bundle');
      item.speed = _num(json, 'speed', 1);
      item.maxFps = _num(json, 'maxFps', 0).toInt();
      item.animate = _bool(json, 'animate', true);
      item.resolutionScale = _num(json, 'resolutionScale', 1);
      item.shaderArgs = json['args'];
      return item;
    default:
      return item;
  }
}

List<KeyValuePair> _pairs(Object? value, _Ctx ctx, String what) {
  if (value is! List) {
    return <KeyValuePair>[];
  }
  final int count = value.length > ctx.limits.maxItems ? ctx.limits.maxItems : value.length;
  if (count < value.length) {
    ctx.truncate('$what 的条目超过上限，已截断');
  }
  final List<KeyValuePair> out = <KeyValuePair>[];
  for (int i = 0; i < count; i++) {
    final Map<String, Object?>? map = _asMap(value[i]);
    if (null == map) {
      continue;
    }
    out.add(
      KeyValuePair(
        key: _textValue(map['k']),
        value: _textValue(map['v']),
        kTone: _tone(map, 'kTone', ''),
        vTone: _tone(map, 'vTone', ''),
      ),
    );
  }
  return out;
}

List<TableColumn> _columns(Object? value, _Ctx ctx, String what) {
  if (value is! List) {
    return <TableColumn>[];
  }
  final int count = value.length > ctx.limits.maxTableColumns
      ? ctx.limits.maxTableColumns
      : value.length;
  if (count < value.length) {
    ctx.truncate('$what 的列数超过上限 ${ctx.limits.maxTableColumns}，已截断');
  }
  final List<TableColumn> out = <TableColumn>[];
  for (int i = 0; i < count; i++) {
    final Map<String, Object?>? map = _asMap(value[i]);
    if (null == map) {
      out.add(TableColumn(title: _textValue(value[i])));
      continue;
    }
    out.add(
      TableColumn(
        title: _textValue(map['title']),
        align: _enum(map, 'align', kEnumAlignH, 'start'),
        width: _has(map, 'width')
            ? _sizeValue(map['width'], ctx.report, '$what[$i].width')
            : SizeValue.autoValue,
        tone: _tone(map, 'tone', ''),
      ),
    );
  }
  return out;
}

List<List<TableCell>> _rows(Object? value, _Ctx ctx, String what) {
  if (value is! List) {
    return <List<TableCell>>[];
  }
  final int count = value.length > ctx.limits.maxTableRows
      ? ctx.limits.maxTableRows
      : value.length;
  if (count < value.length) {
    ctx.truncate('$what 的行数超过上限 ${ctx.limits.maxTableRows}，已截断');
  }
  final List<List<TableCell>> out = <List<TableCell>>[];
  for (int i = 0; i < count; i++) {
    final Object? row = value[i];
    final List<TableCell> cells = <TableCell>[];
    if (row is List) {
      final int cellCount = row.length > ctx.limits.maxTableColumns
          ? ctx.limits.maxTableColumns
          : row.length;
      if (cellCount < row.length) {
        ctx.truncate('$what[$i] 的单元格超过列数上限，已截断');
      }
      for (int c = 0; c < cellCount; c++) {
        final Map<String, Object?>? map = _asMap(row[c]);
        if (null == map) {
          cells.add(TableCell(text: _textValue(row[c])));
          continue;
        }
        cells.add(
          TableCell(
            text: _textValue(map['text']),
            tone: _tone(map, 'tone', ''),
            action: _action(map['action']),
          ),
        );
      }
    }
    out.add(cells);
  }
  return out;
}

TreeNode _treeNode(Object? value, _Ctx ctx, int depth, List<int> budget) {
  final Map<String, Object?>? map = _asMap(value);
  if (null == map || budget[0] <= 0) {
    return const TreeNode();
  }
  budget[0] -= 1;
  final Object? rawChildren = map['children'];
  final List<TreeNode> children = <TreeNode>[];
  if (rawChildren is List && depth < ctx.limits.maxDepth) {
    final int count =
        rawChildren.length > ctx.limits.maxItems ? ctx.limits.maxItems : rawChildren.length;
    if (count < rawChildren.length) {
      ctx.truncate('树节点的子节点超过上限，已截断');
    }
    for (int i = 0; i < count; i++) {
      children.add(_treeNode(rawChildren[i], ctx, depth + 1, budget));
    }
  }
  return TreeNode(
    label: _textValue(map['label']),
    tone: _tone(map, 'tone', ''),
    action: _action(map['action']),
    children: children,
  );
}

List<TreeNode> _nodes(Object? value, _Ctx ctx, String what) {
  if (value is! List) {
    return <TreeNode>[];
  }
  final List<int> budget = <int>[ctx.limits.maxTreeNodes];
  final int count = value.length > ctx.limits.maxItems ? ctx.limits.maxItems : value.length;
  if (count < value.length) {
    ctx.truncate('$what 的节点超过上限，已截断');
  }
  final List<TreeNode> out = <TreeNode>[];
  for (int i = 0; i < count && budget[0] > 0; i++) {
    out.add(_treeNode(value[i], ctx, 0, budget));
  }
  if (budget[0] <= 0) {
    ctx.truncate('$what 的节点总数超过上限 ${ctx.limits.maxTreeNodes}，已截断');
  }
  return out;
}

List<Threshold> _thresholds(Object? value, _Ctx ctx) {
  if (value is! List) {
    return <Threshold>[];
  }
  final List<Threshold> out = <Threshold>[];
  for (final Object? node in value) {
    final Map<String, Object?>? map = _asMap(node);
    if (null == map) {
      continue;
    }
    out.add(Threshold(at: _num(map, 'at', 0), tone: _tone(map, 'tone', 'accent')));
  }
  return out;
}

List<double> _numbers(Object? value, _Ctx ctx, String what) {
  if (value is! List) {
    return <double>[];
  }
  final int count =
      value.length > ctx.limits.maxDataPoints ? ctx.limits.maxDataPoints : value.length;
  if (count < value.length) {
    ctx.truncate('$what 的数据点超过上限，已截断');
  }
  return <double>[
    for (int i = 0; i < count; i++)
      if (value[i] is num) (value[i] as num).toDouble(),
  ];
}

List<String> _tones(Object? value, _Ctx ctx) {
  if (value is! List) {
    return <String>[];
  }
  final List<String> out = <String>[];
  for (final Object? node in value) {
    if (node is! String) {
      continue;
    }
    for (final String tone in kEnumTone) {
      if (tone.toLowerCase() == node.toLowerCase()) {
        out.add(tone);
        break;
      }
    }
  }
  return out;
}

List<ControlOption> _options(Object? value, _Ctx ctx, String what) {
  if (value is! List) {
    return <ControlOption>[];
  }
  final int count = value.length > ctx.limits.maxItems ? ctx.limits.maxItems : value.length;
  if (count < value.length) {
    ctx.truncate('$what 的候选项超过上限，已截断');
  }
  final List<ControlOption> out = <ControlOption>[];
  for (int i = 0; i < count; i++) {
    final Map<String, Object?>? map = _asMap(value[i]);
    if (null == map) {
      out.add(ControlOption(value: value[i], label: _textValue(value[i])));
      continue;
    }
    out.add(
      ControlOption(
        value: map['value'],
        label: _textValue(map['label']),
        tone: _tone(map, 'tone', ''),
      ),
    );
  }
  return out;
}

/// 解析单个块
ItemData parseBlock(Object? json, {Limits limits = const Limits(), ParseReport? report}) =>
    _parseBlockImpl(json, _Ctx(limits, report), 0);

/// 解析块数组（也接受 `{blocks:[…]}` / `{items:[…]}` 包装）
List<ItemData> parseBlocks(
  Object? json, {
  Limits limits = const Limits(),
  ParseReport? report,
}) {
  final _Ctx ctx = _Ctx(limits, report);
  Object? array = json;
  final Map<String, Object?>? map = _asMap(json);
  if (null != map) {
    array = map['blocks'] ?? map['items'];
  }
  if (array is! List) {
    return <ItemData>[];
  }
  return _parseBlockImplList(array, ctx);
}

List<ItemData> _parseBlockImplList(List<Object?> array, _Ctx ctx) {
  final int count = array.length > ctx.limits.maxItems ? ctx.limits.maxItems : array.length;
  if (count < array.length) {
    ctx.truncate('blocks 的子块超过上限 ${ctx.limits.maxItems}，已截断');
  }
  return <ItemData>[
    for (int i = 0; i < count; i++) _parseBlockImpl(array[i], ctx, 0),
  ];
}

/// 解析一份界面内容（`{title, subtitle, blocks}` 或裸块数组）
UiDocument parseDocument(
  Object? json, {
  Limits limits = const Limits(),
  ParseReport? report,
}) {
  final UiDocument doc = UiDocument();
  final _Ctx ctx = _Ctx(limits, report);
  if (json is List) {
    doc.blocks = _parseBlockImplList(json, ctx);
    return doc;
  }
  final Map<String, Object?>? map = _asMap(json);
  if (null == map) {
    return doc;
  }
  doc.title = _textValue(map['title']);
  doc.subtitle = _textValue(map['subtitle']);
  final Object? blocks = map['blocks'] ?? map['items'];
  if (blocks is List) {
    doc.blocks = _parseBlockImplList(blocks, ctx);
  }
  return doc;
}

// ===== 序列化 =====

Object? _textValueToJson(TextValue value) {
  if (value.key.isEmpty && null == value.args) {
    return value.fallback;
  }
  return <String, Object?>{
    if (value.key.isNotEmpty) 'key': value.key,
    if (value.fallback.isNotEmpty) 'fallback': value.fallback,
    if (null != value.args) 'args': value.args,
  };
}

Object _sizeValueToJson(SizeValue value) {
  switch (value.mode) {
    case SizeMode.value:
      return value.value;
    case SizeMode.percent:
      return <String, Object?>{'percent': value.value};
    case SizeMode.auto:
      return 'auto';
  }
}

Map<String, Object?> _edgesToJson(Edges edges) => <String, Object?>{
      'left': edges.left,
      'top': edges.top,
      'right': edges.right,
      'bottom': edges.bottom,
    };

Object? _actionToJson(UiAction? action) {
  if (null == action || action.isEmpty) {
    return null;
  }
  switch (action.kind) {
    case ActionKind.dispatch:
      if (null == action.args) {
        return action.name;
      }
      return <String, Object?>{'kind': 'dispatch', 'name': action.name, 'args': action.args};
    case ActionKind.route:
      return <String, Object?>{'kind': 'route', 'route': action.route};
    case ActionKind.command:
      return <String, Object?>{
        'kind': 'command',
        'name': action.name,
        if (null != action.args) 'args': action.args,
      };
    case ActionKind.none:
      return null;
  }
}

/// 组件项 → JSON（字段取缺省值时不输出）
Map<String, Object?> dumpItem(ItemData item) {
  final Map<String, Object?> out = <String, Object?>{'kind': item.kind};
  if (!item.known) {
    if (item.fallback.isNotEmpty) {
      out['fallback'] = item.fallback;
    }
    return out;
  }
  if (item.id.isNotEmpty) {
    out['id'] = item.id;
  }
  void putChildren() {
    if (item.children.isNotEmpty) {
      out['children'] = <Object?>[for (final ItemData child in item.children) dumpItem(child)];
    }
  }

  switch (item.kind) {
    case 'Text':
      if (item.text.isNotEmpty) {
        out['text'] = _textValueToJson(item.text);
      }
      out['type'] = item.textType;
      out['tone'] = item.tone;
      if (item.bold) {
        out['bold'] = true;
      }
      if (item.dim) {
        out['dim'] = true;
      }
      if (item.mono) {
        out['mono'] = true;
      }
      out['wrap'] = item.wrap;
      if (item.maxLines > 0) {
        out['maxLines'] = item.maxLines;
      }
      out['align'] = item.align;
      break;
    case 'Gap':
      out['size'] = _sizeValueToJson(item.size);
      break;
    case 'Button':
      if (item.label.isNotEmpty) {
        out['label'] = _textValueToJson(item.label);
      }
      out['variant'] = item.variant;
      if (item.icon.isNotEmpty) {
        out['icon'] = item.icon;
      }
      if (item.disabled) {
        out['disabled'] = true;
      }
      break;
    case 'Block':
      if (item.title.isNotEmpty) {
        out['title'] = _textValueToJson(item.title);
      }
      out['variant'] = item.variant;
      if (item.hasPadding) {
        out['padding'] = _edgesToJson(item.padding);
      }
      if (item.hasMargin) {
        out['margin'] = _edgesToJson(item.margin);
      }
      putChildren();
      break;
    case 'Row':
    case 'Column':
      if (item.hasGap) {
        out['gap'] = _sizeValueToJson(item.gap);
      }
      out['main'] = item.main;
      out['cross'] = item.cross;
      putChildren();
      break;
    case 'Expanded':
    case 'Spacer':
      out['flex'] = item.flex;
      putChildren();
      break;
    case 'SizedBox':
      if (!item.width.isAuto) {
        out['width'] = _sizeValueToJson(item.width);
      }
      if (!item.height.isAuto) {
        out['height'] = _sizeValueToJson(item.height);
      }
      if (item.aspect > 0) {
        out['aspect'] = item.aspect;
      }
      putChildren();
      break;
    case 'Padding':
      out['padding'] = _edgesToJson(item.padding);
      putChildren();
      break;
    case 'Align':
      out['align'] = item.align;
      out['vertical'] = item.vertical;
      putChildren();
      break;
    case 'Collapse':
      if (item.title.isNotEmpty) {
        out['title'] = _textValueToJson(item.title);
      }
      out['expanded'] = item.expanded;
      putChildren();
      break;
    case 'KV':
      out['pairs'] = <Object?>[
        for (final KeyValuePair pair in item.pairs)
          <String, Object?>{
            'k': _textValueToJson(pair.key),
            'v': _textValueToJson(pair.value),
            if (pair.kTone.isNotEmpty) 'kTone': pair.kTone,
            if (pair.vTone.isNotEmpty) 'vTone': pair.vTone,
          },
      ];
      out['keyWidth'] = _sizeValueToJson(item.keyWidth);
      out['sep'] = item.sep;
      break;
    case 'Table':
      out['header'] = item.header;
      out['columns'] = <Object?>[
        for (final TableColumn column in item.columns)
          <String, Object?>{
            if (column.title.isNotEmpty) 'title': _textValueToJson(column.title),
            'align': column.align,
            if (!column.width.isAuto) 'width': _sizeValueToJson(column.width),
            if (column.tone.isNotEmpty) 'tone': column.tone,
          },
      ];
      out['rows'] = <Object?>[
        for (final List<TableCell> row in item.rows)
          <Object?>[
            for (final TableCell cell in row)
              if (cell.tone.isEmpty && null == cell.action)
                _textValueToJson(cell.text)
              else
                <String, Object?>{
                  'text': _textValueToJson(cell.text),
                  if (cell.tone.isNotEmpty) 'tone': cell.tone,
                  if (null != _actionToJson(cell.action)) 'action': _actionToJson(cell.action),
                },
          ],
      ];
      break;
    case 'Tree':
      out['connector'] = item.connector;
      out['nodes'] = <Object?>[
        for (final TreeNode node in item.nodes) _treeNodeToJson(node),
      ];
      break;
    case 'Progress':
      out['value'] = item.value;
      out['total'] = item.total;
      if (item.label.isNotEmpty) {
        out['label'] = _textValueToJson(item.label);
      }
      out['unit'] = item.unit;
      out['showValue'] = item.showValue;
      out['tone'] = item.tone;
      if (item.thresholds.isNotEmpty) {
        out['thresholds'] = <Object?>[
          for (final Threshold threshold in item.thresholds)
            <String, Object?>{'at': threshold.at, 'tone': threshold.tone},
        ];
      }
      if (!item.width.isAuto) {
        out['width'] = _sizeValueToJson(item.width);
      }
      break;
    case 'Badge':
      if (item.text.isNotEmpty) {
        out['text'] = _textValueToJson(item.text);
      }
      out['tone'] = item.tone;
      break;
    case 'Control':
      out['control'] = item.control;
      if (item.label.isNotEmpty) {
        out['label'] = _textValueToJson(item.label);
      }
      if (item.help.isNotEmpty) {
        out['help'] = _textValueToJson(item.help);
      }
      if (item.options.isNotEmpty) {
        out['options'] = <Object?>[
          for (final ControlOption option in item.options)
            <String, Object?>{
              'value': option.value,
              'label': _textValueToJson(option.label),
              if (option.tone.isNotEmpty) 'tone': option.tone,
            },
        ];
      }
      if (null != item.controlValue) {
        out['value'] = item.controlValue;
      }
      if (item.disabled) {
        out['disabled'] = true;
      }
      if (item.integer) {
        out['integer'] = true;
      }
      if (item.multiline) {
        out['multiline'] = true;
      }
      if (item.hasMin) {
        out['min'] = item.minValue;
      }
      if (item.hasMax) {
        out['max'] = item.maxValue;
      }
      if (item.hasStep) {
        out['step'] = item.step;
      }
      break;
    case 'Markdown':
      out['text'] = item.markdown;
      break;
    case 'Icon':
      if (item.icon.isNotEmpty) {
        out['name'] = item.icon;
      }
      if (item.glyph.isNotEmpty) {
        out['glyph'] = item.glyph;
      }
      if (!item.size.isAuto) {
        out['size'] = _sizeValueToJson(item.size);
      }
      out['tone'] = item.tone;
      break;
    case 'Stack':
      out['align'] = item.align;
      out['vertical'] = item.vertical;
      putChildren();
      break;
    case 'Image':
      out['source'] = item.source;
      out['src'] = item.src;
      if (!item.width.isAuto) {
        out['width'] = _sizeValueToJson(item.width);
      }
      if (!item.height.isAuto) {
        out['height'] = _sizeValueToJson(item.height);
      }
      if (item.aspect > 0) {
        out['aspect'] = item.aspect;
      }
      if (item.radius > 0) {
        out['radius'] = item.radius;
      }
      out['fit'] = item.fit;
      if (item.alt.isNotEmpty) {
        out['alt'] = _textValueToJson(item.alt);
      }
      break;
    case 'Diff':
      if (item.path.isNotEmpty) {
        out['path'] = item.path;
      }
      out['oldStr'] = item.oldStr;
      out['newStr'] = item.newStr;
      break;
    case 'Sparkline':
      out['data'] = item.data;
      out['height'] = item.glyphHeight;
      out['glyphStyle'] = item.glyphStyle;
      if (item.hasMin) {
        out['min'] = item.minValue;
      }
      if (item.hasMax) {
        out['max'] = item.maxValue;
      }
      out['tone'] = item.tone;
      out['showLast'] = item.showLast;
      if (item.colors.isNotEmpty) {
        out['colors'] = item.colors;
      }
      break;
    case 'Diagram':
      out['mermaid'] = item.mermaid;
      break;
    case 'musicxx.Shader':
      out['bundle'] = item.bundle;
      if (null != item.shaderArgs) {
        out['args'] = item.shaderArgs;
      }
      out['speed'] = item.speed;
      out['animate'] = item.animate;
      out['resolutionScale'] = item.resolutionScale;
      if (item.maxFps > 0) {
        out['maxFps'] = item.maxFps;
      }
      break;
  }
  final Object? action = _actionToJson(item.action);
  if (null != action) {
    out['action'] = action;
  }
  return out;
}

Map<String, Object?> _treeNodeToJson(TreeNode node) => <String, Object?>{
      'label': _textValueToJson(node.label),
      if (node.tone.isNotEmpty) 'tone': node.tone,
      if (node.action?.isNotEmpty ?? false) 'action': _actionToJson(node.action),
      if (node.children.isNotEmpty)
        'children': <Object?>[for (final TreeNode child in node.children) _treeNodeToJson(child)],
    };

/// 组件列表 → JSON 数组
List<Object?> dumpBlocks(List<ItemData> items) =>
    <Object?>[for (final ItemData item in items) dumpItem(item)];

/// 整份内容 → JSON
Map<String, Object?> dumpDocument(UiDocument doc) => <String, Object?>{
      if (doc.title.isNotEmpty) 'title': _textValueToJson(doc.title),
      if (doc.subtitle.isNotEmpty) 'subtitle': _textValueToJson(doc.subtitle),
      'blocks': dumpBlocks(doc.blocks),
    };

// ===== 组件表查询与能力段 =====

/// 按名字查组件元信息（忽略大小写；未找到返回 null）
BlockMeta? findBlockMeta(String kind) {
  if (kind.isEmpty) {
    return null;
  }
  for (final BlockMeta meta in kBlockTable) {
    if (meta.kind.toLowerCase() == kind.toLowerCase()) {
      return meta;
    }
  }
  return null;
}

/// 组件名是否在组件表里（忽略大小写）
bool isKnownBlock(String kind) => null != findBlockMeta(kind);

/// 组件名的规范写法（未找到返回 null）
String? canonicalKind(String kind) => findBlockMeta(kind)?.kind;

/// 能力段 → JSON（客户端发布通道用它）
Map<String, Object?> capabilitiesToJson(PluginCapabilities caps) => <String, Object?>{
      'apiVersion': caps.apiVersion,
      'kind': caps.kind,
      'blocks': caps.blocks,
      'controls': caps.controls,
      if (caps.kind == 'tui')
        'cell': <String, Object?>{'width': caps.cell.width, 'height': caps.cell.height},
      'gap': caps.gap,
      if (caps.icons.isNotEmpty) 'icons': caps.icons,
      'percent': caps.percent,
      'aspect': caps.aspect,
      'limits': <String, Object?>{
        'maxDepth': caps.limits.maxDepth,
        'maxItems': caps.limits.maxItems,
        'maxTextBytes': caps.limits.maxTextBytes,
        'maxDocumentBytes': caps.limits.maxDocumentBytes,
        'maxTableRows': caps.limits.maxTableRows,
        'maxTableColumns': caps.limits.maxTableColumns,
        'maxTreeNodes': caps.limits.maxTreeNodes,
        'maxDataPoints': caps.limits.maxDataPoints,
      },
    };

/// JSON → 能力段（缺字段取默认值；未知字段忽略）
PluginCapabilities capabilitiesFromJson(Object? json) {
  final Map<String, Object?>? map = _asMap(json);
  final PluginCapabilities full = PluginCapabilities.full();
  if (null == map) {
    return full;
  }
  final List<Object?>? blocks = map['blocks'] is List ? map['blocks']! as List : null;
  final List<Object?>? controls = map['controls'] is List ? map['controls']! as List : null;
  final Map<String, Object?>? cell = _asMap(map['cell']);
  final Map<String, Object?>? limits = _asMap(map['limits']);
  return PluginCapabilities(
    apiVersion: _num(map, 'apiVersion', kUiApiVersion.toDouble()).toInt(),
    kind: _str(map, 'kind').toLowerCase() == 'tui' ? 'tui' : 'gui',
    blocks: null == blocks
        ? full.blocks
        : <String>[
            for (final Object? value in blocks)
              if (value is String) value,
          ],
    controls: null == controls
        ? full.controls
        : <String>[
            for (final Object? value in controls)
              if (value is String) value,
          ],
    cell: CellSize(
      width: null == cell ? kDefaultCellWidth : _num(cell, 'width', kDefaultCellWidth),
      height: null == cell ? kDefaultCellHeight : _num(cell, 'height', kDefaultCellHeight),
    ),
    gap: _num(map, 'gap', kDefaultGap),
    icons: map['icons'] is List
        ? <String>[
            for (final Object? value in (map['icons']! as List))
              if (value is String) value,
          ]
        : <String>[],
    percent: _bool(map, 'percent', true),
    aspect: _bool(map, 'aspect', true),
    limits: null == limits
        ? const Limits()
        : Limits(
            maxDepth: _num(limits, 'maxDepth', kMaxDepth.toDouble()).toInt(),
            maxItems: _num(limits, 'maxItems', kMaxItems.toDouble()).toInt(),
            maxTextBytes: _num(limits, 'maxTextBytes', kMaxTextBytes.toDouble()).toInt(),
            maxDocumentBytes:
                _num(limits, 'maxDocumentBytes', kMaxDocumentBytes.toDouble()).toInt(),
            maxTableRows: _num(limits, 'maxTableRows', kMaxTableRows.toDouble()).toInt(),
            maxTableColumns:
                _num(limits, 'maxTableColumns', kMaxTableColumns.toDouble()).toInt(),
            maxTreeNodes: _num(limits, 'maxTreeNodes', kMaxTreeNodes.toDouble()).toInt(),
            maxDataPoints: _num(limits, 'maxDataPoints', kMaxDataPoints.toDouble()).toInt(),
          ),
  );
}

/// 默认能力：全部组件与控件都支持
PluginCapabilities fullCapabilities() => PluginCapabilities.full();

/// 最小能力：只支持 Text
PluginCapabilities minimalCapabilities() => PluginCapabilities.minimal();
