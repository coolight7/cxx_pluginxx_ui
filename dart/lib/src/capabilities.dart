// 客户端能力（能力段）与解析上限（Dart 绑定）
//
// 客户端如实上报自己能画什么；`adapt()` 按它把描述降级成客户端能渲染的样子。
// 库不写"if 终端"这类判断，只看能力。能力段的 JSON 形态见 capabilities.h / docs。
import 'gen/blocks.g.dart';

/// 每个字符格相当于多少 u（只有格子模型的客户端才有意义）
class CellSize {
  const CellSize({this.width = kDefaultCellWidth, this.height = kDefaultCellHeight});

  final double width;
  final double height;
}

/// 解析与渲染上限（**当前版本全部为 0 = 不限制**；保留结构只为能力段 JSON 兼容）
class Limits {
  const Limits({
    this.maxDepth = 0,
    this.maxItems = 0,
    this.maxTextBytes = 0,
    this.maxDocumentBytes = 0,
    this.maxTableRows = 0,
    this.maxTableColumns = 0,
    this.maxTreeNodes = 0,
    this.maxDataPoints = 0,
  });

  final int maxDepth;
  final int maxItems;
  final int maxTextBytes;
  final int maxDocumentBytes;
  final int maxTableRows;
  final int maxTableColumns;
  final int maxTreeNodes;
  final int maxDataPoints;
}

/// 客户端能力
class PluginCapabilities {
  PluginCapabilities({
    this.apiVersion = kUiApiVersion,
    this.kind = 'gui',
    List<String>? blocks,
    List<String>? controls,
    this.cell = const CellSize(),
    this.gap = kDefaultGap,
    List<String>? icons,
    this.percent = true,
    this.aspect = true,
    this.limits = const Limits(),
  })  : blocks = blocks ?? <String>[],
        controls = controls ?? <String>[],
        icons = icons ?? <String>[];

  int apiVersion;

  /// 渲染类型：tui / gui（只用于粗判断）
  String kind;

  /// 支持的组件（规范名；比较时忽略大小写）
  List<String> blocks;

  /// 支持的控件形态
  List<String> controls;

  /// 每个字符格相当于多少 u
  CellSize cell;

  /// 本客户端的默认行距（Gap.size 缺省时用它）
  double gap;

  /// 认识的图标名（可选）
  List<String> icons;

  bool percent;
  bool aspect;
  Limits limits;

  bool supportsBlock(String name) =>
      blocks.any((String item) => item.toLowerCase() == name.toLowerCase());

  bool supportsControl(String name) =>
      controls.any((String item) => item.toLowerCase() == name.toLowerCase());

  bool supportsIcon(String name) => icons.contains(name);

  /// 横向 u → 列数（四舍五入；[atLeastOne] 表示正数至少占 1 格）
  int colsOf(double u, {bool atLeastOne = false}) =>
      _cellsOf(u, cell.width, kDefaultCellWidth, atLeastOne);

  /// 纵向 u → 行数（四舍五入；[atLeastOne] 表示正数至少占 1 格）
  int rowsOf(double u, {bool atLeastOne = false}) =>
      _cellsOf(u, cell.height, kDefaultCellHeight, atLeastOne);

  static int _cellsOf(double u, double unit, double fallback, bool atLeastOne) {
    final double step = unit > 0 ? unit : fallback;
    final int n = (u / step + 0.5).floor();
    if (atLeastOne && u > 0 && n < 1) {
      return 1;
    }
    return n < 0 ? 0 : n;
  }

  /// 全部组件与控件都支持（GUI 客户端的默认能力）
  static PluginCapabilities full() => PluginCapabilities(
        blocks: kBlockNames,
        controls: kControlKinds,
      );

  /// 最小实现：只有 Text（适配的收敛终点）
  static PluginCapabilities minimal() => PluginCapabilities(
        blocks: <String>['Text'],
        controls: <String>[],
        percent: false,
        aspect: false,
      );
}
