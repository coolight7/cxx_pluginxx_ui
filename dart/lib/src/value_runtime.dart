import 'dart:math' as math;
import 'dart:typed_data';

import 'model.dart' as model;

/// 值表达式（插件声明"某个值每帧取什么"的唯一写法）
///
/// 一份声明里，每个"值位置"的值都是一个**节点**：`{"kind": "<类型>", ...参数}`。
/// 节点可以像 widget 一样互相嵌套（`smooth(of: mul(of: [source, lfo]))`），主程序每帧
/// 从根节点求值一次，结果交给消费者（着色器 uniform、UI 块的尺寸/文本/开关…）：
///
/// ```jsonc
/// "uLevel": { "kind": "smooth", "attackMs": 20, "releaseMs": 260,
///             "of": { "kind": "source", "name": "musicxx.spectrum.level" } }
/// ```
///
/// 设计约定：
/// - **唯一语法**：值位置只有两种形态 —— 字面量（数字 / 字符串 / 布尔 / 数组 / 颜色串 /
///   无 `kind` 的字面量对象如 `{"percent":40}`）与带 `kind` 的节点；不存在第三种裸形状；
/// - **类型**：值只有两类 —— `vec4`（数值 / 颜色 / 向量，标量位置取 `.x`）与 `string`（文本）；
///   开关用 `vec4` 的 0/1；尺寸位置可用 `unit = "u"`（缺省）或 `"percent"`；
/// - **名字空间**：`musicxx.*` 是框架/应用保留的**派生来源**（主题色 / 封面取色 / 频谱 / 环境量）
///   与官方变量；**其它名字（允许含 `.`）是自定义的**（局部通道或插件/应用登记的变量）。
///   解析顺序：局部作用域 → 变量 → 派生来源；可用可选字段 `scope` 显式指定；
/// - **节点不可变**，状态（`smooth` 的上一次输出）存在节点里 → 状态生命周期跟表达式树一致；
/// - 非法节点（未知 `kind`、参数类型不对、超过上限）会让**这一项**被忽略并记一条日志，
///   同一份声明里的其它项照常工作；没写值的位置主程序不写（消费者按缺省处理）。
///
/// 节点表见 [UiValueKinds]；客户端文档见 `docs/ui-schema.md` 的「值表达式」一节。

/// 一个值：`vec4`（4 个 float）或一段文本
///
/// 两者只可能有一个非空；[unit] 只在尺寸位置有意义（`u` = 逻辑像素，`percent` = 父容器比例）。
class UiValue {
  const UiValue.vec(Float32List this.vec, {this.unit}) : text = null;

  const UiValue.text(this.text, {this.unit}) : vec = null;

  /// 4 个 float（数值 / 颜色 / 向量）
  final Float32List? vec;

  /// 文本
  final String? text;

  /// 尺寸单位：`u`（缺省）或 `percent`；其它消费者忽略它
  final String? unit;

  static final UiValue zero = UiValue.vec(
    Float32List.fromList(<double>[0, 0, 0, 0]),
  );

  static const UiValue emptyText = UiValue.text('');

  /// 数字 → vec4（4 个分量都写这个数字，方便直接当标量或向量用）
  factory UiValue.number(double value, {String? unit}) {
    return UiValue.vec(
      Float32List.fromList(<double>[value, value, value, value]),
      unit: unit,
    );
  }

  bool get isText => null != text;

  bool get isPercent => unit == 'percent';

  /// 数值：vec4 取 `.x`；文本按数字解析（解析不出按 0）
  double get number {
    final Float32List? v = vec;
    if (null != v) {
      return v[0];
    }
    return double.tryParse(text?.trim() ?? '') ?? 0;
  }

  /// 开关：非 0 / 非空文本且不是 `false`/`0` 即真
  bool get flag {
    final Float32List? v = vec;
    if (null != v) {
      return v[0] != 0;
    }
    final String t = (text ?? '').trim().toLowerCase();
    return t.isNotEmpty && t != '0' && t != 'false';
  }

  /// 文本化：数字去掉多余的小数（12.0 → "12"，1.5 → "1.5"）
  String asText() {
    if (null != text) {
      return text!;
    }
    return formatNumber(number);
  }

  /// 只取 vec4（文本按"数字解析后的广播"给出，保证消费者拿得到 4 个分量）
  Float32List asVec4() {
    final Float32List? v = vec;
    if (null != v) {
      return v;
    }
    final double n = number;
    return Float32List.fromList(<double>[n, n, n, n]);
  }

  /// 是否与 [other] 相等（用于"值有没有变化"的判断）
  bool sameAs(UiValue other) {
    if (null != vec && null != other.vec) {
      for (int i = 0; i < 4; ++i) {
        if (vec![i] != other.vec![i]) {
          return false;
        }
      }
      return unit == other.unit;
    }
    return text == other.text && unit == other.unit;
  }

  /// 数字 → 文本（整数不带小数点，小数去掉尾随 0）
  static String formatNumber(double value) => model.formatNumber(value);
}

/// 局部作用域链（`AnimatedBuilder.values` 构成；内层覆盖外层）
class UiValueScope {
  const UiValueScope({
    this.values = const <String, UiValueNode>{},
    this.parent,
  });

  final Map<String, UiValueNode> values;
  final UiValueScope? parent;

  UiValueNode? lookup(String name) {
    for (
      UiValueScope? scope = this;
      null != scope;
      scope = scope.parent
    ) {
      final UiValueNode? node = scope.values[name];
      if (null != node) {
        return node;
      }
    }
    return null;
  }

  /// 这个作用域链上登记的所有名字（调试/自省用）
  Set<String> names() {
    final Set<String> out = <String>{};
    for (
      UiValueScope? scope = this;
      null != scope;
      scope = scope.parent
    ) {
      out.addAll(scope.values.keys);
    }
    return out;
  }
}

/// 求值上下文（主程序每帧构造一次，传给所有节点）
class UiValueCtx {
  const UiValueCtx({
    required this.timeSec,
    required this.dtSec,
    required this.night,
    required this.paletteValid,
    required this.spectrumAvailable,
    this.coverAvailable = false,
    required this.sources,
    this.scope,
    this.depth = 0,
  });

  /// 动画时间（秒）：与着色器里的 `uParams.z * uParams.w` 一致
  /// （插件设置页里的"动画速率"能一起带动 `tween` / `lfo`；`animate: false` 时恒为 0）
  final double timeSec;

  /// 距上一帧的秒数（首帧、不可见恢复后由主程序钳制，避免一步跳完）
  final double dtSec;

  /// 是否夜间
  final bool night;

  /// 是否有有效的封面配色（`<客户端>.icon.*` 之类的来源是否可用）
  final bool paletteValid;

  /// 现在是否有频谱数据（`<客户端>.spectrum.*` 之类的来源是否可用；没有数据时写 0）
  final bool spectrumAvailable;

  /// 现在有没有当前封面（客户端环境量；与有没有声明封面纹理无关）
  final bool coverAvailable;

  /// 具名来源的解析（主程序实现：派生来源 + 变量表）
  final UiValueSourceResolver sources;

  /// 局部作用域链（在哪个 `AnimatedBuilder` 里求值；没有则为空）
  final UiValueScope? scope;

  /// 当前求值深度（防局部通道互相引用转圈；超过 [UiValueLimits.maxDepth] 直接给 0）
  final int depth;

  /// 进入一层（求值局部通道时用）
  UiValueCtx descend() {
    return UiValueCtx(
      timeSec: timeSec,
      dtSec: dtSec,
      night: night,
      paletteValid: paletteValid,
      spectrumAvailable: spectrumAvailable,
      coverAvailable: coverAvailable,
      sources: sources,
      scope: scope,
      depth: depth + 1,
    );
  }
}

/// 具名来源的解析接口（客户端实现：派生来源 + 变量表）
///
/// 引擎只认 `name → 值`，不关心来源是什么，所以新增来源不用动引擎。
abstract class UiValueSourceResolver {
  /// 取一个具名来源的当前值；名字不认识或当前取不到返回 null（由 `source` 节点回落到 fallback 值）
  ///
  /// [convert] 只对封面提取色（`musicxx.icon.*`）有意义：是否套主程序的昼夜转换；
  /// [ctx] 里带着这一帧的时间与环境量（夜间、有没有封面配色、有没有频谱数据）。
  UiValue? resolveValue(
    String name,
    UiValueCtx ctx, {
    required bool convert,
  });
}

/// 一个值表达式节点
abstract class UiValueNode {
  /// 求值一次
  UiValue eval(UiValueCtx ctx);

  /// 收集用到的具名来源（主程序据此判断需不需要准备封面配色）
  void collectSources(Set<String> out);

  /// 节点数量（含自身；用于上限校验）
  int get nodeCount;

  /// 嵌套深度（叶子 = 1）
  int get depth;

  /// 规范化文本（判断"两棵树是不是同一份声明"，决定能不能复用状态）
  String get signature;

  /// 清掉内部状态（`smooth` 的上一次输出）
  void resetState();
}

/// 参数表的解析结果（一份 `args` / `values` 声明）
///
/// 键是成员名，值是根节点；[signature] 是整份声明的规范化文本
/// （渲染视图用它判断"插件重新声明了同一份参数"从而保留动画状态）。
class UiArgsTable {
  const UiArgsTable({
    required this.items,
    required this.signature,
    this.sources = const <String>{},
    this.problems = const <String>[],
  });

  static const UiArgsTable empty = UiArgsTable(
    items: <String, UiValueNode>{},
    signature: "",
  );

  /// 成员名 → 根节点
  final Map<String, UiValueNode> items;

  /// 规范化文本（同样的声明得到同样的字符串）
  final String signature;

  /// 用到的具名来源
  final Set<String> sources;

  /// 解析时被忽略的项（写给日志；每项一条）
  final List<String> problems;

  int get length => items.length;

  /// 声明里用到了某个前缀下的具名来源（客户端据此决定要不要准备那批数据）
  ///
  /// 判据由客户端自己定：例如用到了 `<客户端>.icon.*` 才去算封面配色、用到了
  /// `<客户端>.spectrum.*` 才去取频谱。没人用时客户端连读都不读。
  bool needsSourcePrefix(String prefix) {
    for (final String name in sources) {
      if (name.startsWith(prefix)) {
        return true;
      }
    }
    return false;
  }

  /// 求值一份参数表 → 成员名 → 值
  Map<String, UiValue> evaluate(UiValueCtx ctx) {
    final Map<String, UiValue> values = <String, UiValue>{};
    for (final MapEntry<String, UiValueNode> entry in items.entries) {
      values[entry.key] = entry.value.eval(ctx);
    }
    return values;
  }

  /// 求值并统一成 `vec4`（着色器 uniform 用；文本按数字解析后的广播给出）
  Map<String, Float32List> evaluateVec4(UiValueCtx ctx) {
    final Map<String, Float32List> values = <String, Float32List>{};
    for (final MapEntry<String, UiValueNode> entry in items.entries) {
      values[entry.key] = entry.value.eval(ctx).asVec4();
    }
    return values;
  }

  /// 成员名
  List<String> get memberNames => items.keys.toList(growable: false);

  /// 清掉所有节点的状态（切歌、换样式、表面重建时用）
  void resetState() {
    for (final UiValueNode node in items.values) {
      node.resetState();
    }
  }
}

/// 节点的 `kind` 名字表（解析与文档共用一份）
abstract final class UiValueKinds {
  static const String source = "source";
  static const String constValue = "const";
  static const String tween = "tween";
  static const String lfo = "lfo";
  static const String smooth = "smooth";
  static const String add = "add";
  static const String mul = "mul";
  static const String min = "min";
  static const String max = "max";
  static const String mix = "mix";
  static const String clamp = "clamp";
  static const String remap = "remap";
  static const String format = "format";
  static const String concat = "concat";
  static const String cmp = "cmp";
  static const String logicAnd = "logicAnd";
  static const String logicOr = "logicOr";
  static const String logicNot = "logicNot";
  static const String select = "select";

  static const List<String> all = <String>[
    source,
    constValue,
    tween,
    lfo,
    smooth,
    add,
    mul,
    min,
    max,
    mix,
    clamp,
    remap,
    format,
    concat,
    cmp,
    logicAnd,
    logicOr,
    logicNot,
    select,
  ];
}

/// `source` 的查找范围
abstract final class UiValueScopeKind {
  /// 先局部作用域、再广播频道当前值 / 派生来源（缺省）
  static const String auto = "auto";

  /// 只看局部作用域（`AnimatedBuilder.values`）
  static const String local = "local";

  /// 只看广播频道当前值 / 派生来源（跳过局部作用域；历史取值名仍叫 var）
  static const String varOnly = "var";

  static const Set<String> names = <String>{auto, local, varOnly};
}

/// 比较运算（`cmp` 的 `op`）
abstract final class UiValueCmpOp {
  static const String lt = "lt";
  static const String le = "le";
  static const String gt = "gt";
  static const String ge = "ge";
  static const String eq = "eq";
  static const String ne = "ne";

  static const Set<String> names = <String>{lt, le, gt, ge, eq, ne};
}

/// 缓动曲线表（`tween` 的 `ease`）
///
/// 输入 0..1，输出可以略微越界（`outBack` / `outElastic`），由使用方按需 clamp。
abstract final class UiEase {
  static const String linear = "linear";
  static const String inQuad = "inQuad";
  static const String outQuad = "outQuad";
  static const String inOutQuad = "inOutQuad";
  static const String inCubic = "inCubic";
  static const String outCubic = "outCubic";
  static const String inOutCubic = "inOutCubic";
  static const String inSine = "inSine";
  static const String outSine = "outSine";
  static const String inOutSine = "inOutSine";
  static const String outBack = "outBack";
  static const String outElastic = "outElastic";

  static const Set<String> names = <String>{
    linear,
    inQuad,
    outQuad,
    inOutQuad,
    inCubic,
    outCubic,
    inOutCubic,
    inSine,
    outSine,
    inOutSine,
    outBack,
    outElastic,
  };

  /// 求值：不认识的曲线按 `linear` 处理（解析阶段已经记过日志）
  static double apply(String name, double t) {
    final double x = t.clamp(0.0, 1.0).toDouble();
    switch (name) {
      case inQuad:
        return x * x;
      case outQuad:
        return 1 - (1 - x) * (1 - x);
      case inOutQuad:
        return x < 0.5 ? 2 * x * x : 1 - 2 * (1 - x) * (1 - x);
      case inCubic:
        return x * x * x;
      case outCubic:
        final double m = 1 - x;
        return 1 - m * m * m;
      case inOutCubic:
        return x < 0.5 ? 4 * x * x * x : 1 - 4 * (1 - x) * (1 - x) * (1 - x);
      case inSine:
        return 1 - math.cos(x * math.pi / 2);
      case outSine:
        return math.sin(x * math.pi / 2);
      case inOutSine:
        return -(math.cos(math.pi * x) - 1) / 2;
      case outBack:
        const double c1 = 1.70158;
        const double c3 = c1 + 1;
        final double m = x - 1;
        return 1 + c3 * m * m * m + c1 * m * m;
      case outElastic:
        if (x <= 0) {
          return 0;
        }
        if (x >= 1) {
          return 1;
        }
        const double c4 = (2 * math.pi) / 3;
        return math.pow(2, -10 * x).toDouble() *
                math.sin((x * 10 - 0.75) * c4) +
            1;
      case linear:
      default:
        return x;
    }
  }
}

/// `lfo` 的波形表
abstract final class UiLfoShape {
  static const String sine = "sine";
  static const String triangle = "triangle";
  static const String saw = "saw";
  static const String square = "square";

  static const Set<String> names = <String>{sine, triangle, saw, square};

  /// 求值：输入相位 0..1，输出 0..1
  static double apply(String shape, double phase) {
    final double t = phase - phase.floorToDouble();
    switch (shape) {
      case triangle:
        return t < 0.5 ? t * 2 : 2 - t * 2;
      case saw:
        return t;
      case square:
        return t < 0.5 ? 0 : 1;
      case sine:
      default:
        return 0.5 - 0.5 * math.cos(2 * math.pi * t);
    }
  }
}

/// `tween` 的重复方式
abstract final class UiRepeat {
  static const String once = "once";
  static const String loop = "loop";
  static const String pingpong = "pingpong";

  static const Set<String> names = <String>{once, loop, pingpong};
}

/// 表达式的上限（防止一份声明把每帧的时间用光）
abstract final class UiValueLimits {
  /// 单个成员最多多少节点
  static const int maxNodes = 32;

  /// 最多嵌套多少层（也是局部通道互相引用的深度上限）
  static const int maxDepth = 8;

  /// `tween.durationMs` / `lfo.periodMs` 的下限（毫秒）
  static const int minDurationMs = 16;

  /// `tween.durationMs` / `lfo.periodMs` 的上限（毫秒）
  static const int maxDurationMs = 3600000;
}

// ==================== 字面量解析 ====================

/// 字面量解析：数字 / 布尔 / 数字数组 / 颜色字符串 / 数字字符串 / `{"percent":n}`
///
/// 解析失败返回 null。`{"percent":n}` 是尺寸位置的糖（等价于 `const` + `unit: percent`）。
UiValue? parseUiValueLiteral(Object? raw) {
  if (raw is num) {
    return UiValue.number(raw.toDouble());
  }
  if (raw is bool) {
    return UiValue.number(raw ? 1 : 0);
  }
  if (raw is String) {
    final Float32List? color = parseUiColor(raw);
    if (null != color) {
      return UiValue.vec(color);
    }
    final double? number = double.tryParse(raw.trim());
    if (null != number) {
      return UiValue.number(number);
    }
    // 文本字面量（值位置是文本字段时才有意义）
    return UiValue.text(raw);
  }
  if (raw is List) {
    final List<double> values = <double>[0, 0, 0, 0];
    int index = 0;
    for (final Object? item in raw) {
      if (index >= 4) {
        break;
      }
      if (item is num) {
        values[index] = item.toDouble();
      }
      ++index;
    }
    return UiValue.vec(Float32List.fromList(values));
  }
  if (raw is Map) {
    // 无 kind 的字面量对象：目前只认 {"percent": n}
    final Object? percent = raw['percent'];
    if (percent is num) {
      return UiValue.number(percent.toDouble(), unit: 'percent');
    }
    return null;
  }
  return null;
}

/// 颜色字符串（`#rrggbb` / `#aarrggbb`，也接受不写 `#`）→ vec4；不是颜色返回 null
Float32List? parseUiColor(Object? raw) {
  if (raw is! String) {
    return null;
  }
  String text = raw.trim();
  if (text.startsWith("#")) {
    text = text.substring(1);
  }
  if (text.length != 6 && text.length != 8) {
    return null;
  }
  if (text.length == 6) {
    text = "ff$text";
  }
  final int? value = int.tryParse(text, radix: 16);
  if (null == value) {
    return null;
  }
  return Float32List.fromList(<double>[
    ((value >> 16) & 0xff) / 255,
    ((value >> 8) & 0xff) / 255,
    (value & 0xff) / 255,
    ((value >> 24) & 0xff) / 255,
  ]);
}

// ==================== 节点公共小工具 ====================

Float32List _vec4(double a, double b, double c, double d) =>
    Float32List.fromList(<double>[a, b, c, d]);

Float32List _ones() => Float32List.fromList(<double>[1, 1, 1, 1]);

Float32List _zeros() => Float32List.fromList(<double>[0, 0, 0, 0]);

/// 逐分量二元运算
Float32List _zip(
  Float32List a,
  Float32List b,
  double Function(double x, double y) op,
) {
  return _vec4(op(a[0], b[0]), op(a[1], b[1]), op(a[2], b[2]), op(a[3], b[3]));
}

/// 0/1 结果 → 4 个分量（开关位置取 `.x`，写满方便直接当向量用）
UiValue _flagValue(bool value) => UiValue.number(value ? 1 : 0);

// ==================== 节点实现 ====================

/// `source`：具名来源（派生来源 / 变量 / 局部通道）
///
/// 名字规则与解析顺序见文件头。`scope` 可选：`auto`（缺省，局部 → 变量/派生来源）、
/// `local`（只看局部）、`var`（跳过局部）。
class UiSourceNode extends UiValueNode {
  UiSourceNode({
    required this.name,
    this.convert = false,
    this.scope = UiValueScopeKind.auto,
    this.fallback,
    this.fallbackNight,
  });

  final String name;

  /// 只对封面提取色（`musicxx.icon.*`）有意义：取到的封面色是否套主程序昼夜转换
  final bool convert;

  /// 查找范围（见 [UiValueScopeKind]）
  final String scope;

  final UiValue? fallback;
  final UiValue? fallbackNight;

  @override
  UiValue eval(UiValueCtx ctx) {
    if (ctx.depth > UiValueLimits.maxDepth) {
      // 局部通道互相引用转圈：直接给 0，别把每帧卡死
      return UiValue.zero;
    }
    if (scope != UiValueScopeKind.varOnly) {
      final UiValueNode? local = ctx.scope?.lookup(name);
      if (null != local && !identical(local, this)) {
        return local.eval(ctx.descend());
      }
    }
    if (scope != UiValueScopeKind.local) {
      final UiValue? value = ctx.sources.resolveValue(
        name,
        ctx,
        convert: convert,
      );
      if (null != value) {
        return value;
      }
    }
    if (ctx.night && null != fallbackNight) {
      return fallbackNight!;
    }
    return fallback ?? UiValue.zero;
  }

  @override
  void collectSources(Set<String> out) => out.add(name);

  @override
  int get nodeCount => 1;

  @override
  int get depth => 1;

  @override
  String get signature =>
      "source($name${convert ? ",convert" : ""}"
      "${scope == UiValueScopeKind.auto ? "" : ",scope:$scope"}"
      "${null == fallback ? "" : ",fallback:${fallback!.asText()}"}"
      "${null == fallbackNight ? "" : ",fallbackNight:${fallbackNight!.asText()}"})";

  @override
  void resetState() {}
}

/// `const`：常量（数字 / 数组 / 颜色 / 文本；`night` 换夜间值，`unit` 指定尺寸单位）
class UiConstNode extends UiValueNode {
  UiConstNode({required this.value, this.night});

  final UiValue value;
  final UiValue? night;

  @override
  UiValue eval(UiValueCtx ctx) =>
      (ctx.night && null != night) ? night! : value;

  @override
  void collectSources(Set<String> out) {}

  @override
  int get nodeCount => 1;

  @override
  int get depth => 1;

  @override
  String get signature =>
      "const(${value.asText()}${null == value.unit ? "" : ":${value.unit}"}"
      "${null == night ? "" : "|${night!.asText()}"})";

  @override
  void resetState() {}
}

/// `smooth`：一阶过渡（起音 / 释音分开给，默认两者相同）
///
/// 音乐可视化常用"快起慢落"（`attackMs` 小、`releaseMs` 大）：跳变时立刻跟上、
/// 回落时平滑，既不打手也不顿。文本值不参与过渡（原样返回）。
class UiSmoothNode extends UiValueNode {
  UiSmoothNode({
    required this.of,
    required this.attackMs,
    required this.releaseMs,
  });

  final UiValueNode of;
  final double attackMs;
  final double releaseMs;

  Float32List? _state;

  @override
  UiValue eval(UiValueCtx ctx) {
    final UiValue target = of.eval(ctx);
    if (target.isText) {
      _state = null;
      return target;
    }
    final Float32List to = target.asVec4();
    final Float32List? state = _state;
    if (null == state) {
      // 第一次求值直接取目标值：不然画面会从 0 慢慢爬上来
      final Float32List initial = Float32List.fromList(to);
      _state = initial;
      return UiValue.vec(initial);
    }
    final double dt = ctx.dtSec <= 0 ? 0 : ctx.dtSec;
    for (int i = 0; i < 4; ++i) {
      final double target = to[i];
      final double from = state[i];
      if (target == from) {
        continue;
      }
      final double tauMs = (target > from ? attackMs : releaseMs).clamp(
        1.0,
        10000.0,
      );
      final double k = dt <= 0 ? 0 : 1 - math.exp(-dt * 1000 / tauMs);
      state[i] = from + (target - from) * k;
    }
    return UiValue.vec(state);
  }

  @override
  void collectSources(Set<String> out) => of.collectSources(out);

  @override
  int get nodeCount => 1 + of.nodeCount;

  @override
  int get depth => 1 + of.depth;

  @override
  String get signature => "smooth($attackMs,$releaseMs,${of.signature})";

  @override
  void resetState() {
    _state = null;
    of.resetState();
  }
}

/// `tween`：时间轴过渡（一次性 / 循环 / 往返）
class UiTweenNode extends UiValueNode {
  UiTweenNode({
    required this.from,
    required this.to,
    required this.durationMs,
    required this.delayMs,
    required this.ease,
    required this.repeat,
    required this.phase,
  });

  final Float32List from;
  final Float32List to;
  final double durationMs;
  final double delayMs;
  final String ease;
  final String repeat;
  final double phase;

  @override
  UiValue eval(UiValueCtx ctx) {
    final double durationSec = durationMs / 1000;
    double elapsed = (ctx.timeSec - delayMs / 1000) / durationSec;
    double t;
    switch (repeat) {
      case UiRepeat.loop:
        elapsed = elapsed + phase;
        t = elapsed - elapsed.floorToDouble();
      case UiRepeat.pingpong:
        elapsed = elapsed + phase;
        final double u = elapsed - (elapsed / 2).floorToDouble() * 2;
        t = u <= 1 ? u : 2 - u;
      case UiRepeat.once:
      default:
        t = elapsed.clamp(0.0, 1.0).toDouble();
    }
    final double eased = UiEase.apply(ease, t);
    return UiValue.vec(
      _vec4(
        from[0] + (to[0] - from[0]) * eased,
        from[1] + (to[1] - from[1]) * eased,
        from[2] + (to[2] - from[2]) * eased,
        from[3] + (to[3] - from[3]) * eased,
      ),
    );
  }

  @override
  void collectSources(Set<String> out) {}

  @override
  int get nodeCount => 1;

  @override
  int get depth => 1;

  @override
  String get signature =>
      "tween(${from.join(",")}|${to.join(",")},$durationMs,$delayMs,$ease,$repeat,$phase)";

  @override
  void resetState() {}
}

/// `lfo`：周期振荡（呼吸、扫光、循环摆动）
class UiLfoNode extends UiValueNode {
  UiLfoNode({
    required this.shape,
    required this.periodMs,
    required this.from,
    required this.to,
    required this.phase,
  });

  final String shape;
  final double periodMs;
  final Float32List from;
  final Float32List to;
  final double phase;

  @override
  UiValue eval(UiValueCtx ctx) {
    final double p = ctx.timeSec / (periodMs / 1000) + phase;
    final double s = UiLfoShape.apply(shape, p);
    return UiValue.vec(
      _vec4(
        from[0] + (to[0] - from[0]) * s,
        from[1] + (to[1] - from[1]) * s,
        from[2] + (to[2] - from[2]) * s,
        from[3] + (to[3] - from[3]) * s,
      ),
    );
  }

  @override
  void collectSources(Set<String> out) {}

  @override
  int get nodeCount => 1;

  @override
  int get depth => 1;

  @override
  String get signature =>
      "lfo($shape,$periodMs,${from.join(",")}|${to.join(",")},$phase)";

  @override
  void resetState() {}
}

/// `add` / `mul` / `min` / `max`：组合多个子节点（逐分量）
class UiCombineNode extends UiValueNode {
  UiCombineNode({required this.kind, required this.of});

  final String kind;
  final List<UiValueNode> of;

  @override
  UiValue eval(UiValueCtx ctx) {
    Float32List acc = of.first.eval(ctx).asVec4();
    for (int i = 1; i < of.length; ++i) {
      final Float32List next = of[i].eval(ctx).asVec4();
      switch (kind) {
        case UiValueKinds.add:
          acc = _zip(acc, next, (double a, double b) => a + b);
        case UiValueKinds.mul:
          acc = _zip(acc, next, (double a, double b) => a * b);
        case UiValueKinds.min:
          acc = _zip(acc, next, math.min);
        case UiValueKinds.max:
        default:
          acc = _zip(acc, next, math.max);
      }
    }
    return UiValue.vec(acc);
  }

  @override
  void collectSources(Set<String> out) {
    for (final UiValueNode node in of) {
      node.collectSources(out);
    }
  }

  @override
  int get nodeCount =>
      1 +
      of.fold<int>(
        0,
        (int sum, UiValueNode node) => sum + node.nodeCount,
      );

  @override
  int get depth =>
      1 +
      of.fold<int>(
        0,
        (int max, UiValueNode node) => math.max(max, node.depth),
      );

  @override
  String get signature =>
      "$kind(${of.map((UiValueNode node) => node.signature).join("|")})";

  @override
  void resetState() {
    for (final UiValueNode node in of) {
      node.resetState();
    }
  }
}

/// `mix`：按 `t` 混合 `a` 与 `b`（逐分量；`t` 是常量时就是普通 lerp）
class UiMixNode extends UiValueNode {
  UiMixNode({required this.a, required this.b, required this.t});

  final UiValueNode a;
  final UiValueNode b;
  final UiValueNode t;

  @override
  UiValue eval(UiValueCtx ctx) {
    final UiValue av = a.eval(ctx);
    final UiValue bv = b.eval(ctx);
    final UiValue tv = t.eval(ctx);
    if (av.isText || bv.isText || tv.isText) {
      // 文本：按 t 的开关选一边（t != 0 取 b）
      return tv.flag ? bv : av;
    }
    final Float32List avx = av.asVec4();
    final Float32List bvx = bv.asVec4();
    final Float32List tvx = tv.asVec4();
    return UiValue.vec(
      _vec4(
        avx[0] + (bvx[0] - avx[0]) * tvx[0],
        avx[1] + (bvx[1] - avx[1]) * tvx[1],
        avx[2] + (bvx[2] - avx[2]) * tvx[2],
        avx[3] + (bvx[3] - avx[3]) * tvx[3],
      ),
    );
  }

  @override
  void collectSources(Set<String> out) {
    a.collectSources(out);
    b.collectSources(out);
    t.collectSources(out);
  }

  @override
  int get nodeCount => 1 + a.nodeCount + b.nodeCount + t.nodeCount;

  @override
  int get depth => 1 + math.max(a.depth, math.max(b.depth, t.depth));

  @override
  String get signature => "mix(${a.signature},${b.signature},${t.signature})";

  @override
  void resetState() {
    a.resetState();
    b.resetState();
    t.resetState();
  }
}

/// `clamp`：把子节点的值钳制到 [min, max]（逐分量；文本原样返回）
class UiClampNode extends UiValueNode {
  UiClampNode({
    required this.of,
    required this.min,
    required this.max,
  });

  final UiValueNode of;
  final Float32List min;
  final Float32List max;

  @override
  UiValue eval(UiValueCtx ctx) {
    final UiValue value = of.eval(ctx);
    if (value.isText) {
      return value;
    }
    final Float32List v = value.asVec4();
    return UiValue.vec(
      _vec4(
        v[0].clamp(min[0], max[0]).toDouble(),
        v[1].clamp(min[1], max[1]).toDouble(),
        v[2].clamp(min[2], max[2]).toDouble(),
        v[3].clamp(min[3], max[3]).toDouble(),
      ),
    );
  }

  @override
  void collectSources(Set<String> out) => of.collectSources(out);

  @override
  int get nodeCount => 1 + of.nodeCount;

  @override
  int get depth => 1 + of.depth;

  @override
  String get signature =>
      "clamp(${of.signature},${min.join(",")},${max.join(",")})";

  @override
  void resetState() => of.resetState();
}

/// `remap`：线性重映射（`inMin..inMax` → `outMin..outMax`，逐分量；文本原样返回）
class UiRemapNode extends UiValueNode {
  UiRemapNode({
    required this.of,
    required this.inMin,
    required this.inMax,
    required this.outMin,
    required this.outMax,
  });

  final UiValueNode of;
  final Float32List inMin;
  final Float32List inMax;
  final Float32List outMin;
  final Float32List outMax;

  @override
  UiValue eval(UiValueCtx ctx) {
    final UiValue raw = of.eval(ctx);
    if (raw.isText) {
      return raw;
    }
    final Float32List value = raw.asVec4();
    final List<double> out = <double>[0, 0, 0, 0];
    for (int i = 0; i < 4; ++i) {
      final double span = inMax[i] - inMin[i];
      final double factor = span.abs() < 1e-9
          ? 0
          : (value[i] - inMin[i]) / span;
      out[i] = outMin[i] + (outMax[i] - outMin[i]) * factor;
    }
    return UiValue.vec(Float32List.fromList(out));
  }

  @override
  void collectSources(Set<String> out) => of.collectSources(out);

  @override
  int get nodeCount => 1 + of.nodeCount;

  @override
  int get depth => 1 + of.depth;

  @override
  String get signature =>
      "remap(${of.signature},${inMin.join(",")},${inMax.join(",")},"
      "${outMin.join(",")},${outMax.join(",")})";

  @override
  void resetState() => of.resetState();
}

/// `format`：把值写进文本模板（`{0}` 占位；数字按 [UiValue.asText] 的规则格式化）
///
/// 模板里可以出现多个 `{0}`（都指同一个值）；`{{` / `}}` 是字面大括号。
class UiFormatNode extends UiValueNode {
  UiFormatNode({required this.value, required this.text});

  final UiValueNode value;
  final String text;

  @override
  UiValue eval(UiValueCtx ctx) {
    final String raw = value.eval(ctx).asText();
    return UiValue.text(
      text
          .replaceAll('{{', '\u0000')
          .replaceAll('}}', '\u0001')
          .replaceAll('{0}', raw)
          .replaceAll('\u0000', '{')
          .replaceAll('\u0001', '}'),
    );
  }

  @override
  void collectSources(Set<String> out) => value.collectSources(out);

  @override
  int get nodeCount => 1 + value.nodeCount;

  @override
  int get depth => 1 + value.depth;

  @override
  String get signature =>
      "format(${value.signature},${text.replaceAll("\n", "\\n")})";

  @override
  void resetState() => value.resetState();
}

/// `concat`：把多个文本拼起来（子节点可以是文本节点，也可以直接写字符串）
class UiConcatNode extends UiValueNode {
  UiConcatNode({required this.of});

  final List<UiValueNode> of;

  @override
  UiValue eval(UiValueCtx ctx) {
    final StringBuffer buffer = StringBuffer();
    for (final UiValueNode node in of) {
      buffer.write(node.eval(ctx).asText());
    }
    return UiValue.text(buffer.toString());
  }

  @override
  void collectSources(Set<String> out) {
    for (final UiValueNode node in of) {
      node.collectSources(out);
    }
  }

  @override
  int get nodeCount =>
      1 +
      of.fold<int>(
        0,
        (int sum, UiValueNode node) => sum + node.nodeCount,
      );

  @override
  int get depth =>
      1 +
      of.fold<int>(
        0,
        (int max, UiValueNode node) => math.max(max, node.depth),
      );

  @override
  String get signature =>
      "concat(${of.map((UiValueNode node) => node.signature).join("|")})";

  @override
  void resetState() {
    for (final UiValueNode node in of) {
      node.resetState();
    }
  }
}

/// `cmp`：比较两个值 → 0/1
class UiCmpNode extends UiValueNode {
  UiCmpNode({required this.a, required this.b, required this.op});

  final UiValueNode a;
  final UiValueNode b;
  final String op;

  @override
  UiValue eval(UiValueCtx ctx) {
    final UiValue av = a.eval(ctx);
    final UiValue bv = b.eval(ctx);
    if (av.isText || bv.isText) {
      final String x = av.asText();
      final String y = bv.asText();
      final int order = x.compareTo(y);
      return _flagValue(switch (op) {
        UiValueCmpOp.lt => order < 0,
        UiValueCmpOp.le => order <= 0,
        UiValueCmpOp.gt => order > 0,
        UiValueCmpOp.ge => order >= 0,
        UiValueCmpOp.ne => order != 0,
        _ => order == 0,
      });
    }
    final double x = av.number;
    final double y = bv.number;
    return _flagValue(switch (op) {
      UiValueCmpOp.lt => x < y,
      UiValueCmpOp.le => x <= y,
      UiValueCmpOp.gt => x > y,
      UiValueCmpOp.ge => x >= y,
      UiValueCmpOp.ne => x != y,
      _ => x == y,
    });
  }

  @override
  void collectSources(Set<String> out) {
    a.collectSources(out);
    b.collectSources(out);
  }

  @override
  int get nodeCount => 1 + a.nodeCount + b.nodeCount;

  @override
  int get depth => 1 + math.max(a.depth, b.depth);

  @override
  String get signature => "cmp(${a.signature},${b.signature},$op)";

  @override
  void resetState() {
    a.resetState();
    b.resetState();
  }
}

/// `logicAnd` / `logicOr`：多个开关（0/1）的逻辑组合 → 0/1
class UiLogicNode extends UiValueNode {
  UiLogicNode({required this.kind, required this.of});

  final String kind;
  final List<UiValueNode> of;

  @override
  UiValue eval(UiValueCtx ctx) {
    bool acc = UiValueKinds.logicAnd == kind;
    for (final UiValueNode node in of) {
      final bool value = node.eval(ctx).flag;
      if (UiValueKinds.logicAnd == kind) {
        acc = acc && value;
      } else {
        acc = acc || value;
      }
    }
    return _flagValue(acc);
  }

  @override
  void collectSources(Set<String> out) {
    for (final UiValueNode node in of) {
      node.collectSources(out);
    }
  }

  @override
  int get nodeCount =>
      1 +
      of.fold<int>(
        0,
        (int sum, UiValueNode node) => sum + node.nodeCount,
      );

  @override
  int get depth =>
      1 +
      of.fold<int>(
        0,
        (int max, UiValueNode node) => math.max(max, node.depth),
      );

  @override
  String get signature =>
      "$kind(${of.map((UiValueNode node) => node.signature).join("|")})";

  @override
  void resetState() {
    for (final UiValueNode node in of) {
      node.resetState();
    }
  }
}

/// `logicNot`：取反 → 0/1
class UiLogicNotNode extends UiValueNode {
  UiLogicNotNode({required this.of});

  final UiValueNode of;

  @override
  UiValue eval(UiValueCtx ctx) => _flagValue(!of.eval(ctx).flag);

  @override
  void collectSources(Set<String> out) => of.collectSources(out);

  @override
  int get nodeCount => 1 + of.nodeCount;

  @override
  int get depth => 1 + of.depth;

  @override
  String get signature => "logicNot(${of.signature})";

  @override
  void resetState() => of.resetState();
}

/// `select`：按条件选值（`cond` 非 0 取 `then`，否则取 `else`；两边可以是数值或文本）
class UiSelectNode extends UiValueNode {
  UiSelectNode({
    required this.cond,
    required this.thenValue,
    required this.elseValue,
  });

  final UiValueNode cond;
  final UiValueNode thenValue;
  final UiValueNode elseValue;

  @override
  UiValue eval(UiValueCtx ctx) =>
      cond.eval(ctx).flag ? thenValue.eval(ctx) : elseValue.eval(ctx);

  @override
  void collectSources(Set<String> out) {
    cond.collectSources(out);
    thenValue.collectSources(out);
    elseValue.collectSources(out);
  }

  @override
  int get nodeCount =>
      1 + cond.nodeCount + thenValue.nodeCount + elseValue.nodeCount;

  @override
  int get depth =>
      1 + math.max(cond.depth, math.max(thenValue.depth, elseValue.depth));

  @override
  String get signature =>
      "select(${cond.signature},${thenValue.signature},${elseValue.signature})";

  @override
  void resetState() {
    cond.resetState();
    thenValue.resetState();
    elseValue.resetState();
  }
}

// ==================== 解析 ====================

/// 一份声明的解析结果（含被忽略项的原因，供日志使用）
class UiValueParseResult {
  const UiValueParseResult({required this.table, required this.problems});

  final UiArgsTable table;

  /// 每个被忽略的成员一条说明（"uLevel: 未知的 kind 'foo'"）
  final List<String> problems;
}

/// 解析一份声明（成员名 → 值表达式）
///
/// 写法只有一种：声明是**对象**，键是成员名，值是一个 `{"kind": ...}` 节点（或字面量）。
/// 解析失败的项被忽略并给出原因，不影响同一份声明里的其它项。
///
/// [maxMembers] 是成员数上限；`<= 0` = **不限制**（插件页面的动画通道用它）。
UiValueParseResult parseUiArgsTable(Object? raw, {int maxMembers = 16}) {
  final Map<String, UiValueNode> items = <String, UiValueNode>{};
  final List<String> problems = <String>[];
  final Set<String> sources = <String>{};
  if (raw is! Map) {
    if (null != raw) {
      problems.add("声明必须是对象（成员名 → 值），当前是 ${raw.runtimeType}");
    }
    return UiValueParseResult(
      table: UiArgsTable(items: items, signature: "", problems: problems),
      problems: problems,
    );
  }
  for (final MapEntry<Object?, Object?> entry in raw.entries) {
    final String name = "${entry.key}";
    if (maxMembers > 0 && items.length >= maxMembers) {
      problems.add("$name: 成员最多 $maxMembers 个，已忽略");
      continue;
    }
    if (false == _isMemberName(name)) {
      problems.add("$name: 成员名不合法（字母或下划线开头，最长 32 字符）");
      continue;
    }
    final UiValueNode? node = parseUiValueNode(
      entry.value,
      problems,
      name,
    );
    if (null == node) {
      continue;
    }
    if (node.nodeCount > UiValueLimits.maxNodes) {
      problems.add(
        "$name: 表达式太大（${node.nodeCount} 个节点，上限 ${UiValueLimits.maxNodes}）",
      );
      continue;
    }
    if (node.depth > UiValueLimits.maxDepth) {
      problems.add(
        "$name: 表达式嵌套太深（${node.depth} 层，上限 ${UiValueLimits.maxDepth}）",
      );
      continue;
    }
    node.collectSources(sources);
    items[name] = node;
  }
  final String signature = items.entries
      .map(
        (MapEntry<String, UiValueNode> e) =>
            "${e.key}=${e.value.signature}",
      )
      .join(";");
  return UiValueParseResult(
    table: UiArgsTable(
      items: items,
      signature: signature,
      sources: sources,
      problems: problems,
    ),
    problems: problems,
  );
}

/// 解析一个节点（`problems` 会追加被忽略的原因，`path` 是成员名/参数路径）
UiValueNode? parseUiValueNode(
  Object? raw,
  List<String> problems,
  String path,
) {
  if (raw is! Map) {
    // 字面量：数字 / 文本 / 数组 / 颜色 / {"percent":n}
    final UiValue? literal = parseUiValueLiteral(raw);
    if (null == literal) {
      problems.add(
        "$path: 值必须是字面量或带 kind 的节点（例如 {\"kind\":\"source\",\"name\":\"musicxx.spectrum.level\"}）",
      );
      return null;
    }
    return UiConstNode(value: literal);
  }
  final Object? kindRaw = raw["kind"];
  if (kindRaw is! String || kindRaw.isEmpty) {
    // 无 kind 的对象 = 该位置的字面量（{"percent":40} 这类）
    final UiValue? literal = parseUiValueLiteral(raw);
    if (null == literal) {
      problems.add("$path: 字面量对象不认识（目前支持 {\"percent\": n}）；要计算请写带 kind 的节点");
      return null;
    }
    return UiConstNode(value: literal);
  }
  final String kind = kindRaw;
  switch (kind) {
    case UiValueKinds.source:
      final Object? nameRaw = raw["name"];
      if (nameRaw is! String || nameRaw.isEmpty) {
        problems.add("$path: source 缺少 name");
        return null;
      }
      final String scope = (raw["scope"] is String)
          ? raw["scope"] as String
          : UiValueScopeKind.auto;
      if (false == UiValueScopeKind.names.contains(scope)) {
        problems.add("$path: 未知的 scope '$scope'（按 auto 处理）");
      }
      return UiSourceNode(
        name: nameRaw,
        convert: true == raw["convert"],
        scope: UiValueScopeKind.names.contains(scope)
            ? scope
            : UiValueScopeKind.auto,
        fallback: parseUiValueLiteral(raw["fallback"]),
        fallbackNight: parseUiValueLiteral(raw["fallbackNight"]),
      );
    case UiValueKinds.constValue:
      final UiValue? value = parseUiValueLiteral(raw["value"]);
      if (null == value) {
        problems.add("$path: const 缺少合法的 value（数字 / 数组 / 颜色 / 文本）");
        return null;
      }
      final String? unit = raw["unit"] is String ? raw["unit"] as String : null;
      return UiConstNode(
        value: null == unit ? value : _withUnit(value, unit),
        night: _withUnitOrNull(parseUiValueLiteral(raw["night"]), unit),
      );
    case UiValueKinds.tween:
      final String ease = _text(raw["ease"]) ?? UiEase.linear;
      final String repeat = _text(raw["repeat"]) ?? UiRepeat.once;
      if (false == UiEase.names.contains(ease)) {
        problems.add("$path: 未知的 ease '$ease'（按 linear 处理）");
      }
      if (false == UiRepeat.names.contains(repeat)) {
        problems.add("$path: 未知的 repeat '$repeat'（按 once 处理）");
      }
      return UiTweenNode(
        from: _vec4Of(raw["from"]) ?? _zeros(),
        to: _vec4Of(raw["to"]) ?? _ones(),
        durationMs: _millis(raw["durationMs"], 1000),
        delayMs: _millisOrZero(raw["delayMs"], 0),
        ease: UiEase.names.contains(ease) ? ease : UiEase.linear,
        repeat: UiRepeat.names.contains(repeat)
            ? repeat
            : UiRepeat.once,
        phase: _number(raw["phase"], 0),
      );
    case UiValueKinds.lfo:
      final String shape = _text(raw["shape"]) ?? UiLfoShape.sine;
      if (false == UiLfoShape.names.contains(shape)) {
        problems.add("$path: 未知的 shape '$shape'（按 sine 处理）");
      }
      return UiLfoNode(
        shape: UiLfoShape.names.contains(shape)
            ? shape
            : UiLfoShape.sine,
        periodMs: _millis(raw["periodMs"], 1000),
        from: _vec4Of(raw["from"]) ?? _zeros(),
        to: _vec4Of(raw["to"]) ?? _ones(),
        phase: _number(raw["phase"], 0),
      );
    case UiValueKinds.smooth:
      final UiValueNode? of = parseUiValueNode(
        raw["of"],
        problems,
        "$path.of",
      );
      if (null == of) {
        problems.add("$path: smooth 缺少子节点 of");
        return null;
      }
      final double? both = _numberOrNull(raw["ms"]);
      final double attack = _number(raw["attackMs"], both ?? 150);
      final double release = _number(raw["releaseMs"], both ?? 150);
      return UiSmoothNode(
        of: of,
        attackMs: attack,
        releaseMs: release,
      );
    case UiValueKinds.add:
    case UiValueKinds.mul:
    case UiValueKinds.min:
    case UiValueKinds.max:
      final List<UiValueNode> children = _children(
        raw["of"],
        problems,
        path,
      );
      if (children.isEmpty) {
        problems.add("$path: $kind 需要至少一个子节点（of: [...]）");
        return null;
      }
      if (children.length == 1) {
        return children.first;
      }
      return UiCombineNode(kind: kind, of: children);
    case UiValueKinds.mix:
      final UiValueNode? a = parseUiValueNode(
        raw["a"],
        problems,
        "$path.a",
      );
      final UiValueNode? b = parseUiValueNode(
        raw["b"],
        problems,
        "$path.b",
      );
      final UiValueNode? t = _nodeOrLiteral(raw["t"]);
      if (null == a || null == b || null == t) {
        problems.add("$path: mix 需要 a / b / t");
        return null;
      }
      return UiMixNode(a: a, b: b, t: t);
    case UiValueKinds.clamp:
      final UiValueNode? of = parseUiValueNode(
        raw["of"],
        problems,
        "$path.of",
      );
      if (null == of) {
        problems.add("$path: clamp 缺少子节点 of");
        return null;
      }
      return UiClampNode(
        of: of,
        min: _vec4Of(raw["min"]) ?? _zeros(),
        max: _vec4Of(raw["max"]) ?? _ones(),
      );
    case UiValueKinds.remap:
      final UiValueNode? of = parseUiValueNode(
        raw["of"],
        problems,
        "$path.of",
      );
      if (null == of) {
        problems.add("$path: remap 缺少子节点 of");
        return null;
      }
      return UiRemapNode(
        of: of,
        inMin: _vec4Of(raw["inMin"]) ?? _zeros(),
        inMax: _vec4Of(raw["inMax"]) ?? _ones(),
        outMin: _vec4Of(raw["outMin"]) ?? _zeros(),
        outMax: _vec4Of(raw["outMax"]) ?? _ones(),
      );
    case UiValueKinds.format:
      final UiValueNode? value = parseUiValueNode(
        raw["value"],
        problems,
        "$path.value",
      );
      final String? text = _text(raw["text"]);
      if (null == value || null == text) {
        problems.add("$path: format 需要 value 与 text（模板里用 {0} 占位）");
        return null;
      }
      return UiFormatNode(value: value, text: text);
    case UiValueKinds.concat:
      final List<UiValueNode> children = _children(
        raw["of"],
        problems,
        path,
      );
      if (children.isEmpty) {
        problems.add("$path: concat 需要至少一个子节点（of: [...]，可以直接写字符串）");
        return null;
      }
      return UiConcatNode(of: children);
    case UiValueKinds.cmp:
      final UiValueNode? a = parseUiValueNode(
        raw["a"],
        problems,
        "$path.a",
      );
      final UiValueNode? b = parseUiValueNode(
        raw["b"],
        problems,
        "$path.b",
      );
      final String op = _text(raw["op"]) ?? UiValueCmpOp.eq;
      if (false == UiValueCmpOp.names.contains(op)) {
        problems.add("$path: 未知的比较 op '$op'（按 eq 处理）");
      }
      if (null == a || null == b) {
        problems.add("$path: cmp 需要 a 与 b");
        return null;
      }
      return UiCmpNode(
        a: a,
        b: b,
        op: UiValueCmpOp.names.contains(op) ? op : UiValueCmpOp.eq,
      );
    case UiValueKinds.logicAnd:
    case UiValueKinds.logicOr:
      final List<UiValueNode> children = _children(
        raw["of"],
        problems,
        path,
      );
      if (children.isEmpty) {
        problems.add("$path: $kind 需要至少一个子节点（of: [...]）");
        return null;
      }
      return UiLogicNode(kind: kind, of: children);
    case UiValueKinds.logicNot:
      final UiValueNode? of = parseUiValueNode(
        raw["of"],
        problems,
        "$path.of",
      );
      if (null == of) {
        problems.add("$path: logicNot 缺少子节点 of");
        return null;
      }
      return UiLogicNotNode(of: of);
    case UiValueKinds.select:
      final UiValueNode? cond = parseUiValueNode(
        raw["cond"],
        problems,
        "$path.cond",
      );
      final UiValueNode? thenValue = parseUiValueNode(
        raw["then"],
        problems,
        "$path.then",
      );
      final UiValueNode? elseValue = parseUiValueNode(
        raw["else"],
        problems,
        "$path.else",
      );
      if (null == cond || null == thenValue || null == elseValue) {
        problems.add("$path: select 需要 cond / then / else");
        return null;
      }
      return UiSelectNode(
        cond: cond,
        thenValue: thenValue,
        elseValue: elseValue,
      );
    default:
      problems.add(
        "$path: 未知的 kind '$kind'（可用：${UiValueKinds.all.join(" / ")}）",
      );
      return null;
  }
}

/// 子节点列表（`of` 可以写数组，也可以直接写字面量）
List<UiValueNode> _children(
  Object? raw,
  List<String> problems,
  String path,
) {
  final List<UiValueNode> children = <UiValueNode>[];
  if (raw is List) {
    for (int i = 0; i < raw.length; ++i) {
      final UiValueNode? child = parseUiValueNode(
        raw[i],
        problems,
        "$path.of[$i]",
      );
      if (null != child) {
        children.add(child);
      }
    }
    return children;
  }
  final UiValueNode? single = parseUiValueNode(raw, problems, "$path.of");
  if (null != single) {
    children.add(single);
  }
  return children;
}

/// `t` 这类"可以写字面量"的参数：字面量直接包成 `const`
UiValueNode? _nodeOrLiteral(Object? raw) =>
    parseUiValueNode(raw, <String>[], '');

/// 取值的 4 个分量（`from` / `to` / `min` / `max` 这些参数用）
Float32List? _vec4Of(Object? raw) {
  final UiValue? value = parseUiValueLiteral(raw);
  return value?.asVec4();
}

UiValue _withUnit(UiValue value, String unit) => value.isText
    ? UiValue.text(value.text!, unit: unit)
    : UiValue.vec(value.asVec4(), unit: unit);

UiValue? _withUnitOrNull(UiValue? value, String? unit) =>
    (null == value || null == unit) ? value : _withUnit(value, unit);

final RegExp _memberNamePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,31}$');

bool _isMemberName(String name) => _memberNamePattern.hasMatch(name);

String? _text(Object? raw) {
  if (raw is String && raw.isNotEmpty) {
    return raw;
  }
  return null;
}

double _number(Object? raw, double def) => _numberOrNull(raw) ?? def;

double? _numberOrNull(Object? raw) {
  if (raw is num) {
    final double value = raw.toDouble();
    if (value.isNaN || value.isInfinite) {
      return null;
    }
    return value;
  }
  if (raw is String) {
    return double.tryParse(raw.trim());
  }
  return null;
}

/// 毫秒参数：钳制在可用区间（写错只会退化，不影响这一项）
double _millis(Object? raw, double def) {
  final double value = _number(raw, def);
  return value.clamp(
    UiValueLimits.minDurationMs.toDouble(),
    UiValueLimits.maxDurationMs.toDouble(),
  );
}

/// 毫秒参数（允许 0）：`delayMs` 这类"0 有意义"的字段用它
double _millisOrZero(Object? raw, double def) {
  final double value = _number(raw, def);
  return value.clamp(0.0, UiValueLimits.maxDurationMs.toDouble());
}


