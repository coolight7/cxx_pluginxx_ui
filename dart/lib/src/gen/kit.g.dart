// 本文件由 tools/gen_ui.dart 生成，请勿手工修改。
// 定义来源：schema/ui.def.json / schema/kit.def.json
// kit：共享便捷组件。只装配、不含逻辑，也不引用客户端专属块。
// 每个组件返回一个节点（Map），交给解析层的 parseBlock() 使用；
// 传 env（客户端能力摘要）时按目标选择更合适的变体。

import '../capabilities.dart';
import '../kit_runtime.dart';
import 'blocks.g.dart';

/// kit 版本
const int kKitVersion = 1;

/// 组件模板（组件名 → {variants, params}）
const Map<String, Map<String, Object?>> kKitTemplates = <String, Map<String, Object?>>{
  'title': <String, Object?>{
    'params': <String, Object?>{'text': null},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Text', 'text': '\$text', 'type': 'title'}}],
  },
  'hint': <String, Object?>{
    'params': <String, Object?>{'text': null},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Text', 'text': '\$text', 'type': 'caption', 'tone': 'hint'}}],
  },
  'text': <String, Object?>{
    'params': <String, Object?>{'text': null, 'tone': 'normal', 'mono': false},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Text', 'text': '\$text', 'tone': '\$tone', 'mono': '\$mono'}}],
  },
  'badge': <String, Object?>{
    'params': <String, Object?>{'text': null, 'tone': 'accent'},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Badge', 'text': '\$text', 'tone': '\$tone'}}],
  },
  'icon': <String, Object?>{
    'params': <String, Object?>{'name': null, 'glyph': null, 'size': null, 'tone': 'normal'},
    'variants': <Object?>[<String, Object?>{'requires': <Object?>['Icon'], 'template': <String, Object?>{'kind': 'Icon', 'name': '\$name', 'glyph': '\$glyph', 'size': '\$size', 'tone': '\$tone'}}, <String, Object?>{'template': <String, Object?>{'kind': 'Text', 'text': '\$glyph', 'mono': true, 'tone': '\$tone'}}],
  },
  'gap': <String, Object?>{
    'params': <String, Object?>{'size': null},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Gap', 'size': '\$size'}}],
  },
  'divider': <String, Object?>{
    'params': <String, Object?>{},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Divider'}}],
  },
  'button': <String, Object?>{
    'params': <String, Object?>{'label': null, 'variant': 'secondary', 'icon': null, 'disabled': false, 'action': null},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Button', 'label': '\$label', 'variant': '\$variant', 'icon': '\$icon', 'disabled': '\$disabled', 'action': '\$action'}}],
  },
  'actionsRow': <String, Object?>{
    'params': <String, Object?>{'buttons': null},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Row', 'gap': 12, 'children': <String, Object?>{'\$map': 'buttons', 'wrap': <String, Object?>{'kind': 'Expanded', 'children': <Object?>['\$item']}}}}],
  },
  'card': <String, Object?>{
    'params': <String, Object?>{'title': null, 'variant': 'card', 'padding': null, 'margin': null, 'children': null},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Block', 'title': '\$title', 'variant': '\$variant', 'padding': '\$padding', 'margin': '\$margin', 'children': '\$children'}}],
  },
  'listRow': <String, Object?>{
    'params': <String, Object?>{'title': null, 'subtitle': null, 'trailing': null, 'action': null},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Block', 'variant': 'inset', 'padding': <String, Object?>{'horizontal': 12, 'vertical': 8}, 'action': '\$action', 'children': <Object?>[<String, Object?>{'kind': 'Row', 'gap': 12, 'cross': 'center', 'children': <Object?>[<String, Object?>{'kind': 'Expanded', 'children': <Object?>[<String, Object?>{'kind': 'Column', 'gap': 4, 'children': <Object?>[<String, Object?>{'kind': 'Text', 'text': '\$title'}, <String, Object?>{'\$require': 'subtitle', 'kind': 'Text', 'text': '\$subtitle', 'type': 'caption', 'tone': 'hint'}]}]}, <String, Object?>{'\$require': 'trailing', 'kind': 'Text', 'text': '\$trailing', 'tone': 'hint'}]}]}}],
  },
  'section': <String, Object?>{
    'params': <String, Object?>{'title': null, 'rows': null},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Column', 'gap': 8, 'children': <Object?>[<String, Object?>{'kind': 'Text', 'text': '\$title', 'type': 'title'}, <String, Object?>{'kind': 'Column', 'children': '\$rows'}]}}],
  },
  'kv': <String, Object?>{
    'params': <String, Object?>{'pairs': null, 'sep': null},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'KV', 'pairs': '\$pairs', 'sep': '\$sep', 'keyWidth': 'auto'}}],
  },
  'table': <String, Object?>{
    'params': <String, Object?>{'columns': null, 'rows': null, 'header': true},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Table', 'header': '\$header', 'columns': '\$columns', 'rows': '\$rows'}}],
  },
  'tree': <String, Object?>{
    'params': <String, Object?>{'nodes': null, 'connector': true},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Tree', 'connector': '\$connector', 'nodes': '\$nodes'}}],
  },
  'sparkline': <String, Object?>{
    'params': <String, Object?>{'data': null, 'height': 1, 'glyphStyle': 'block', 'showLast': true, 'tone': 'accent'},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Sparkline', 'data': '\$data', 'height': '\$height', 'glyphStyle': '\$glyphStyle', 'showLast': '\$showLast', 'tone': '\$tone'}}],
  },
  'progressRow': <String, Object?>{
    'params': <String, Object?>{'label': null, 'value': null, 'total': 100, 'unit': null},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Row', 'gap': 12, 'cross': 'center', 'children': <Object?>[<String, Object?>{'\$require': 'label', 'kind': 'Text', 'text': '\$label'}, <String, Object?>{'kind': 'Expanded', 'children': <Object?>[<String, Object?>{'kind': 'Progress', 'value': '\$value', 'total': '\$total', 'unit': '\$unit'}]}]}}],
  },
};

/// 按格换算成 u（count 列），env 为空时用库默认格大小
double cols(int count, {PluginCapabilities? env}) =>
    count * (env?.cell.width ?? kDefaultCellWidth);
/// 按格换算成 u（count 行），env 为空时用库默认格大小
double rows(int count, {PluginCapabilities? env}) =>
    count * (env?.cell.height ?? kDefaultCellHeight);

/// kit 组件（参数说明见生成的 docs/kit.md）

/// 标题行
/// 参数：text(text, 必填)
Map<String, Object?> title({required Object text, PluginCapabilities? env}) =>
    KitRuntime.expand('title', <String, Object?>{'text': text}, env, kKitTemplates) ??
        <String, Object?>{};

/// 次要说明行
/// 参数：text(text, 必填)
Map<String, Object?> hint({required Object text, PluginCapabilities? env}) =>
    KitRuntime.expand('hint', <String, Object?>{'text': text}, env, kKitTemplates) ??
        <String, Object?>{};

/// 正文行
/// 参数：text(text, 必填)、tone(tone, 默认 normal)、mono(bool, 默认 false)
Map<String, Object?> text({required Object text, String? tone, bool? mono, PluginCapabilities? env}) =>
    KitRuntime.expand('text', <String, Object?>{'text': text, 'tone': tone, 'mono': mono}, env, kKitTemplates) ??
        <String, Object?>{};

/// 状态小标签
/// 参数：text(text, 必填)、tone(tone, 默认 accent)
Map<String, Object?> badge({required Object text, String? tone, PluginCapabilities? env}) =>
    KitRuntime.expand('badge', <String, Object?>{'text': text, 'tone': tone}, env, kKitTemplates) ??
        <String, Object?>{};

/// 图标（目标不支持 Icon 时退化成 glyph 文本）
/// 参数：name(string)、glyph(string)、size(size)、tone(tone, 默认 normal)
Map<String, Object?> icon({String? name, String? glyph, Object? size, String? tone, PluginCapabilities? env}) =>
    KitRuntime.expand('icon', <String, Object?>{'name': name, 'glyph': glyph, 'size': size, 'tone': tone}, env, kKitTemplates) ??
        <String, Object?>{};

/// 竖直留白（缺省用客户端默认行距）
/// 参数：size(size, 默认 gap)
Map<String, Object?> gap({Object? size, PluginCapabilities? env}) =>
    KitRuntime.expand('gap', <String, Object?>{'size': size}, env, kKitTemplates) ??
        <String, Object?>{};

/// 分隔线
/// 参数：
Map<String, Object?> divider({PluginCapabilities? env}) =>
    KitRuntime.expand('divider', <String, Object?>{}, env, kKitTemplates) ??
        <String, Object?>{};

/// 按钮
/// 参数：label(text, 必填)、variant(enum:buttonVariant, 默认 secondary)、icon(string)、disabled(bool, 默认 false)、action(action)
Map<String, Object?> button({required Object label, Object? variant, String? icon, bool? disabled, Object? action, PluginCapabilities? env}) =>
    KitRuntime.expand('button', <String, Object?>{'label': label, 'variant': variant, 'icon': icon, 'disabled': disabled, 'action': action}, env, kKitTemplates) ??
        <String, Object?>{};

/// 一排等宽按钮（按钮列表里的每一项占一等份）
/// 参数：buttons(items, 必填)
Map<String, Object?> actionsRow({required List<Object?> buttons, PluginCapabilities? env}) =>
    KitRuntime.expand('actionsRow', <String, Object?>{'buttons': buttons}, env, kKitTemplates) ??
        <String, Object?>{};

/// 内容块（卡片）
/// 参数：title(text)、variant(enum:blockVariant, 默认 card)、padding(edges)、margin(edges)、children(items)
Map<String, Object?> card({Object? title, Object? variant, Object? padding, Object? margin, List<Object?>? children, PluginCapabilities? env}) =>
    KitRuntime.expand('card', <String, Object?>{'title': title, 'variant': variant, 'padding': padding, 'margin': margin, 'children': children}, env, kKitTemplates) ??
        <String, Object?>{};

/// 卡片里的一行（标题 + 可选副标题 + 可选右侧文字）
/// 参数：title(text, 必填)、subtitle(text)、trailing(text)、action(action)
Map<String, Object?> listRow({required Object title, Object? subtitle, Object? trailing, Object? action, PluginCapabilities? env}) =>
    KitRuntime.expand('listRow', <String, Object?>{'title': title, 'subtitle': subtitle, 'trailing': trailing, 'action': action}, env, kKitTemplates) ??
        <String, Object?>{};

/// 小节标题 + 若干行
/// 参数：title(text, 必填)、rows(items, 必填)
Map<String, Object?> section({required Object title, required List<Object?> rows, PluginCapabilities? env}) =>
    KitRuntime.expand('section', <String, Object?>{'title': title, 'rows': rows}, env, kKitTemplates) ??
        <String, Object?>{};

/// 键值块（键列按最长键自适应）
/// 参数：pairs(pairs, 必填)、sep(string)
Map<String, Object?> kv({required Object pairs, String? sep, PluginCapabilities? env}) =>
    KitRuntime.expand('kv', <String, Object?>{'pairs': pairs, 'sep': sep}, env, kKitTemplates) ??
        <String, Object?>{};

/// 表格（未指定的列宽由客户端自动分配）
/// 参数：columns(columns, 必填)、rows(rows)、header(bool, 默认 true)
Map<String, Object?> table({required Object columns, Object? rows, bool? header, PluginCapabilities? env}) =>
    KitRuntime.expand('table', <String, Object?>{'columns': columns, 'rows': rows, 'header': header}, env, kKitTemplates) ??
        <String, Object?>{};

/// 层级列表
/// 参数：nodes(nodes, 必填)、connector(bool, 默认 true)
Map<String, Object?> tree({required Object nodes, bool? connector, PluginCapabilities? env}) =>
    KitRuntime.expand('tree', <String, Object?>{'nodes': nodes, 'connector': connector}, env, kKitTemplates) ??
        <String, Object?>{};

/// 迷你趋势图
/// 参数：data(numbers, 必填)、height(int, 默认 1)、glyphStyle(enum:sparkStyle, 默认 block)、showLast(bool, 默认 true)、tone(tone, 默认 accent)
Map<String, Object?> sparkline({required List<num> data, int? height, Object? glyphStyle, bool? showLast, String? tone, PluginCapabilities? env}) =>
    KitRuntime.expand('sparkline', <String, Object?>{'data': data, 'height': height, 'glyphStyle': glyphStyle, 'showLast': showLast, 'tone': tone}, env, kKitTemplates) ??
        <String, Object?>{};

/// 一行进度（左侧标签 + 进度条）
/// 参数：label(text)、value(float, 必填)、total(float, 默认 100)、unit(string)
Map<String, Object?> progressRow({Object? label, required num value, num? total, String? unit, PluginCapabilities? env}) =>
    KitRuntime.expand('progressRow', <String, Object?>{'label': label, 'value': value, 'total': total, 'unit': unit}, env, kKitTemplates) ??
        <String, Object?>{};

