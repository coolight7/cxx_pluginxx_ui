// 尺寸与边距换算（纯数学，不依赖 Flutter）
//
// `SizeValue` 有四种形态：数值（u）、`auto`（由内容决定）、`{percent: n}`
// （直接父容器可分配空间的 n%）、值表达式（客户端每帧求值后传进来）。
// 终端类客户端还要把 u 换算成字符格，所以同时也给出格换算。
import 'gen/blocks.g.dart';
import 'model.dart';

/// 尺寸取值的解析结果
///
/// [value] 是算好的长度（`null` = 由内容决定）；[fromPercent] 为真表示它是
/// "父容器本轮可用尺寸的 n%"，已经换算成实际长度 —— 客户端不要再按设计尺寸缩放一次。
class ResolvedSize {
  const ResolvedSize(this.value, {this.fromPercent = false});

  /// 由内容决定
  static const ResolvedSize auto = ResolvedSize(null);

  final double? value;
  final bool fromPercent;

  bool get isAuto => null == value;

  @override
  String toString() =>
      'ResolvedSize(${value ?? 'auto'}${fromPercent ? ', percent' : ''})';
}

/// 值表达式求值出来的尺寸
class ExprSize {
  const ExprSize(this.value, {this.percent = false});

  /// 数值（`percent` 为真时是 0~100 的比例）
  final double value;

  /// 结果是不是"父容器可分配空间的百分比"（值表达式里写了 `unit: percent`）
  final bool percent;
}

/// 尺寸取值 → 实际长度
///
/// - 数值（u）：原值；
/// - `{percent: n}`：`available * n / 100`；[available] 为空（该方向无界）时用 [fallback]；
/// - 值表达式：用 [expr] 的结果（`percent` 为真时同样按 [available] 换算）；
/// - `auto`（以及表达式求值不出来时）：[fallback]。
ResolvedSize resolveSize(
  SizeValue size, {
  double? available,
  double? fallback,
  ExprSize? expr,
}) {
  if (size.isValue) {
    return ResolvedSize(size.value);
  }
  if (size.isExpr) {
    if (null == expr) {
      return ResolvedSize(fallback);
    }
    if (expr.percent) {
      if (null == available) {
        return ResolvedSize(fallback);
      }
      return ResolvedSize(available * expr.value / 100, fromPercent: true);
    }
    return ResolvedSize(expr.value);
  }
  if (size.isPercent) {
    if (null == available) {
      return ResolvedSize(fallback);
    }
    return ResolvedSize(available * size.value / 100, fromPercent: true);
  }
  return ResolvedSize(fallback);
}

/// 边距换算（四个方向各自可以换算，默认取整）
///
/// 有的客户端拿到的是"设计像素"，要按当前缩放换成逻辑像素再取整（传 [convert]）；
/// 不传就只做四舍五入。
Edges resolveEdges(
  Edges edges, {
  double Function(double value)? convert,
  bool round = true,
}) {
  double one(double value) {
    final double result = null == convert ? value : convert(value);
    return round ? result.roundToDouble() : result;
  }

  return Edges(
    left: one(edges.left),
    top: one(edges.top),
    right: one(edges.right),
    bottom: one(edges.bottom),
  );
}

/// 边距换成字符格（终端类客户端用；四舍五入到整格）
Edges resolveEdgesInCells(
  Edges edges, {
  double cellWidth = kDefaultCellWidth,
  double cellHeight = kDefaultCellHeight,
}) {
  int cells(double value, double cell) {
    if (value <= 0 || cell <= 0) {
      return 0;
    }
    return (value / cell + 0.5).floor().clamp(0, 1 << 20);
  }

  return Edges(
    left: cells(edges.left, cellWidth).toDouble(),
    top: cells(edges.top, cellHeight).toDouble(),
    right: cells(edges.right, cellWidth).toDouble(),
    bottom: cells(edges.bottom, cellHeight).toDouble(),
  );
}

/// 长度换成字符格（终端类客户端用）
///
/// [atLeastOne] 为真时，正数至少占 1 格（避免"写了 4u 却算成 0 列"）。
int sizeInCells(
  double u, {
  double cell = kDefaultCellWidth,
  bool atLeastOne = false,
}) {
  final double step = cell > 0 ? cell : kDefaultCellWidth;
  int n = (u / step + 0.5).floor();
  if (atLeastOne && u > 0 && n < 1) {
    n = 1;
  }
  return n < 0 ? 0 : n;
}
