// 插件界面描述层的规范模型（Dart 绑定，schema v1）
//
// 与 C++ 绑定（include/pluginxx/ui/item.h）一一对应：字段名、默认值、解析口径都
// 保持一致，两端由 fixtures/ 下的同一批夹具约束。
//
// 三条约定（与 C++ 侧相同）：
// - 只描述"界面上有什么"，不含渲染概念（没有终端转义、没有像素精度要求）；
// - JSON 片段（动作参数、控件值）保留原值（Dart 里就是 `Object?`）；
// - 尺寸只有一个单位 u：GUI 1u = 1 逻辑像素，终端按客户端的 `cell` 换算成列/行。
//
// 组件全集与字段见生成的 docs/ui-schema.md（源：schema/ui.def.json）。

/// 尺寸取值的三种形态
enum SizeMode {
  /// 数值（u）
  value,

  /// 由内容决定
  auto,

  /// 占直接父容器可分配空间的比例
  percent,
}

/// 尺寸取值：数值（u）/ `auto` / `{ "percent": n }`
class SizeValue {
  const SizeValue.value(this.value) : mode = SizeMode.value;

  const SizeValue.auto()
      : mode = SizeMode.auto,
        value = 0;

  const SizeValue.percent(this.value) : mode = SizeMode.percent;

  final SizeMode mode;
  final double value;

  bool get isAuto => mode == SizeMode.auto;
  bool get isPercent => mode == SizeMode.percent;
  bool get isValue => mode == SizeMode.value;

  static const SizeValue autoValue = SizeValue.auto();
}

/// 四边数值（内边距 / 外边距）
class Edges {
  const Edges({this.left = 0, this.top = 0, this.right = 0, this.bottom = 0});

  const Edges.all(double v) : left = v, top = v, right = v, bottom = v;

  const Edges.axis(double horizontal, double vertical)
      : left = horizontal,
        top = vertical,
        right = horizontal,
        bottom = vertical;

  final double left;
  final double top;
  final double right;
  final double bottom;

  bool get isZero => 0 == left && 0 == top && 0 == right && 0 == bottom;

  static const Edges zero = Edges();
}

/// 文本取值：字面字符串，或 `{ key, fallback, args }`
///
/// 客户端优先按 [key] 取自己的语言表，取不到用 [fallback]（再取不到用 key 原文）；
/// [args] 是 `{n: 3}` 这类命名占位参数，用于替换文本里的 `{n}`。
class TextValue {
  const TextValue({this.key = '', this.fallback = '', this.args});

  const TextValue.of(String text)
      : key = '',
        fallback = text,
        args = null;

  final String key;
  final String fallback;
  final Object? args;

  bool get isEmpty => key.isEmpty && fallback.isEmpty;
  bool get isNotEmpty => !isEmpty;
  bool get hasKey => key.isNotEmpty;

  /// 解析成最终文本（缺键 → fallback → key 原文，最后做 `{n}` 占位替换）
  String resolve({String Function(String key)? lookup}) {
    String out = '';
    if (null != lookup && key.isNotEmpty) {
      out = lookup(key);
    }
    if (out.isEmpty) {
      out = fallback.isEmpty ? key : fallback;
    }
    return _applyArgs(out, args);
  }

  static String _applyArgs(String text, Object? args) {
    if (text.isEmpty || args is! Map || args.isEmpty) {
      return text;
    }
    final StringBuffer out = StringBuffer();
    int index = 0;
    while (index < text.length) {
      final int open = text.indexOf('{', index);
      if (open < 0) {
        out.write(text.substring(index));
        break;
      }
      final int close = text.indexOf('}', open + 1);
      if (close < 0) {
        out.write(text.substring(index));
        break;
      }
      final String name = text.substring(open + 1, close);
      final bool valid = name.isNotEmpty &&
          RegExp(r'^[A-Za-z0-9_]+$').hasMatch(name);
      if (!valid || !args.containsKey(name)) {
        // 不是占位或没有这个参数：原样保留
        out.write(text.substring(index, open + 1));
        index = open + 1;
        continue;
      }
      out.write(text.substring(index, open));
      out.write(stringifyValue(args[name]));
      index = close + 1;
    }
    return out.toString();
  }

  static const TextValue empty = TextValue();
}

/// 值 → 文本（占位替换与字符串插值共用；与 C++ 侧口径一致）
String stringifyValue(Object? value) {
  if (null == value) {
    return '';
  }
  if (value is String) {
    return value;
  }
  if (value is bool) {
    return value ? 'true' : 'false';
  }
  if (value is num) {
    return formatNumber(value.toDouble());
  }
  return value.toString();
}

/// 数值格式化（两端一致）：整数不带小数点，小数最多两位并去掉尾随 0
String formatNumber(double value) {
  if (value.isNaN || value.isInfinite) {
    return '0';
  }
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  String text = value.toStringAsFixed(2);
  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) {
    text = text.substring(0, text.length - 1);
  }
  return text == '-0' ? '0' : text;
}

/// 动作类型
enum ActionKind {
  none,
  dispatch,
  route,
  command,
}

/// 动作：`dispatch`（交回内容归属方）/ `route`（跳转）/ `command`（客户端官方动作）
class UiAction {
  const UiAction({
    this.kind = ActionKind.none,
    this.name = '',
    this.route = '',
    this.args,
  });

  final ActionKind kind;
  final String name;
  final String route;
  final Object? args;

  bool get isEmpty => kind == ActionKind.none;
  bool get isNotEmpty => !isEmpty;

  static const UiAction none = UiAction();
}

/// 控件候选项（`buttons` / `select`）
class ControlOption {
  const ControlOption({required this.value, required this.label, this.tone = ''});

  final Object? value;
  final TextValue label;
  final String tone;
}

/// 阈值（达到该值起用对应语义色）
class Threshold {
  const Threshold({required this.at, required this.tone});

  final double at;
  final String tone;
}

/// 表格列
class TableColumn {
  const TableColumn({
    this.title = TextValue.empty,
    this.align = 'start',
    this.width = SizeValue.autoValue,
    this.tone = '',
  });

  final TextValue title;
  final String align;
  final SizeValue width;
  final String tone;
}

/// 表格单元格
class TableCell {
  const TableCell({this.text = TextValue.empty, this.tone = '', this.action});

  final TextValue text;
  final String tone;
  final UiAction? action;
}

/// 键值对
class KeyValuePair {
  const KeyValuePair({
    this.key = TextValue.empty,
    this.value = TextValue.empty,
    this.kTone = '',
    this.vTone = '',
  });

  final TextValue key;
  final TextValue value;
  final String kTone;
  final String vTone;
}

/// 树节点
class TreeNode {
  const TreeNode({
    this.label = TextValue.empty,
    this.tone = '',
    this.action,
    this.children = const <TreeNode>[],
  });

  final TextValue label;
  final String tone;
  final UiAction? action;
  final List<TreeNode> children;

  /// 展开后的节点总数（含自身）
  int get count =>
      1 + children.fold<int>(0, (int sum, TreeNode child) => sum + child.count);
}

/// 组件级别
enum BlockLevel {
  /// 两个渲染目标都必须实现
  core,

  /// 允许客户端不实现（按适配规则降级）
  optional,

  /// 客户端专属（`<client>.<Name>`）
  client,
}

/// 适配规则（客户端不支持某个块时怎么降级）
enum AdaptRule {
  /// 收敛终点（Text）
  terminal,

  /// 该节点的纯文本，包成 Text(mono=true)
  plainTextMono,

  /// 展开子节点
  flatten,

  /// 跳过
  skip,

  /// 保留最后一个子节点
  lastChild,

  /// Text(glyph)（无 glyph 则跳过）
  glyphText,

  /// Text(alt)（无 alt 则跳过）
  altText,
}

/// 组件的元信息
class BlockMeta {
  const BlockMeta(this.kind, this.level, this.client, this.rule);

  final String kind;
  final BlockLevel level;

  /// 客户端专属组件的归属（其余为空）
  final String client;
  final AdaptRule rule;
}

/// 一个组件项（各组件只使用与自己相关的字段）
class ItemData {
  ItemData({this.kind = 'Text'});

  /// 组件类型（规范名；解析时忽略大小写）
  String kind;

  /// 组件标识（控件必填；其它组件可选）
  String id = '';

  /// 解析结果是否被识别（false = 未知组件 → 走 fallback）
  bool known = true;

  // ---- 文本与排版 ----
  TextValue text = TextValue.empty;
  String textType = 'body';
  String tone = 'normal';
  bool bold = false;
  bool dim = false;
  bool mono = false;
  bool wrap = true;
  int maxLines = 0;
  String align = 'start';
  String vertical = 'center';
  String main = 'start';
  String cross = 'start';

  // ---- 尺寸与留白 ----
  SizeValue size = SizeValue.autoValue;
  SizeValue width = SizeValue.autoValue;
  SizeValue height = SizeValue.autoValue;
  SizeValue keyWidth = SizeValue.autoValue;
  double aspect = 0;
  double radius = 0;
  String fit = 'contain';
  int flex = 1;

  bool hasGap = false;
  SizeValue gap = SizeValue.autoValue;
  bool hasPadding = false;
  Edges padding = Edges.zero;
  bool hasMargin = false;
  Edges margin = Edges.zero;

  List<ItemData> children = <ItemData>[];

  // ---- 按钮 / 图标 ----
  TextValue label = TextValue.empty;
  String variant = '';
  String icon = '';
  String glyph = '';
  bool disabled = false;

  // ---- 内容块 / 折叠 ----
  TextValue title = TextValue.empty;
  bool expanded = true;

  // ---- 键值 / 表格 / 树 ----
  List<KeyValuePair> pairs = <KeyValuePair>[];
  String sep = ' : ';
  bool header = true;
  List<TableColumn> columns = <TableColumn>[];
  List<List<TableCell>> rows = <List<TableCell>>[];
  bool connector = true;
  List<TreeNode> nodes = <TreeNode>[];

  // ---- 进度 / 趋势 ----
  double value = 0;
  double total = 100;
  String unit = '';
  bool showValue = true;
  List<Threshold> thresholds = <Threshold>[];
  List<double> data = <double>[];
  int glyphHeight = 1;
  String glyphStyle = 'block';
  bool showLast = true;
  List<String> colors = <String>[];

  // ---- 控件 ----
  String control = '';
  TextValue help = TextValue.empty;
  List<ControlOption> options = <ControlOption>[];
  Object? controlValue;
  bool integer = false;
  bool multiline = false;
  bool hasMin = false;
  double minValue = 0;
  bool hasMax = false;
  double maxValue = 0;
  bool hasStep = false;
  double step = 0;

  // ---- Markdown / Diff / Diagram ----
  String markdown = '';
  String path = '';
  String oldStr = '';
  String newStr = '';
  String mermaid = '';

  // ---- 图片 ----
  String source = 'file';
  String src = '';
  TextValue alt = TextValue.empty;

  // ---- 客户端专属块：musicxx.Shader ----
  String bundle = '';
  Object? shaderArgs;
  double speed = 1;
  int maxFps = 0;
  bool animate = true;
  double resolutionScale = 1;

  // ---- 动作与兜底 ----
  UiAction? action;
  String fallback = '';

  /// 是否含可交互内容（控件 / 带动作的可点组件）
  bool get interactive => kind == 'Control' || (action?.isNotEmpty ?? false);

  /// 结构完全相同的副本（适配时不改动调用方给的原对象）
  ItemData clone() => ItemData(kind: kind)
    ..id = id
    ..known = known
    ..text = text
    ..textType = textType
    ..tone = tone
    ..bold = bold
    ..dim = dim
    ..mono = mono
    ..wrap = wrap
    ..maxLines = maxLines
    ..align = align
    ..vertical = vertical
    ..main = main
    ..cross = cross
    ..size = size
    ..width = width
    ..height = height
    ..keyWidth = keyWidth
    ..aspect = aspect
    ..radius = radius
    ..fit = fit
    ..flex = flex
    ..hasGap = hasGap
    ..gap = gap
    ..hasPadding = hasPadding
    ..padding = padding
    ..hasMargin = hasMargin
    ..margin = margin
    ..children = children
    ..label = label
    ..variant = variant
    ..icon = icon
    ..glyph = glyph
    ..disabled = disabled
    ..title = title
    ..expanded = expanded
    ..pairs = pairs
    ..sep = sep
    ..header = header
    ..columns = columns
    ..rows = rows
    ..connector = connector
    ..nodes = nodes
    ..value = value
    ..total = total
    ..unit = unit
    ..showValue = showValue
    ..thresholds = thresholds
    ..data = data
    ..glyphHeight = glyphHeight
    ..glyphStyle = glyphStyle
    ..showLast = showLast
    ..colors = colors
    ..control = control
    ..help = help
    ..options = options
    ..controlValue = controlValue
    ..integer = integer
    ..multiline = multiline
    ..hasMin = hasMin
    ..minValue = minValue
    ..hasMax = hasMax
    ..maxValue = maxValue
    ..hasStep = hasStep
    ..step = step
    ..markdown = markdown
    ..path = path
    ..oldStr = oldStr
    ..newStr = newStr
    ..mermaid = mermaid
    ..source = source
    ..src = src
    ..alt = alt
    ..bundle = bundle
    ..shaderArgs = shaderArgs
    ..speed = speed
    ..maxFps = maxFps
    ..animate = animate
    ..resolutionScale = resolutionScale
    ..action = action
    ..fallback = fallback;
}

/// 一份界面内容：可选包装 + 块数组
class UiDocument {
  UiDocument({this.title = TextValue.empty, this.subtitle = TextValue.empty});

  TextValue title;
  TextValue subtitle;
  List<ItemData> blocks = <ItemData>[];

  bool get isEmpty => blocks.isEmpty && title.isEmpty && subtitle.isEmpty;
}
