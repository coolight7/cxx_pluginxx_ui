// 本文件由 tools/gen_ui.dart 生成，请勿手工修改。
// 定义来源：schema/ui.def.json / schema/kit.def.json
// kit：共享便捷组件。只加载、不含逻辑，也不引用客户端专属块。
// 每个组件返回一个节点（Map），交给解析层的 parseBlock() 使用；
// 传 env（客户端能力摘要）时按目标选择更合适的变体。

import '../capabilities.dart';
import '../kit_runtime.dart';
import 'blocks.g.dart';

/// kit 版本
const int kKitVersion = 3;

/// 组件模板（组件名 → {variants, params}）
const Map<String, Map<String, Object?>> kKitTemplates = <String, Map<String, Object?>>{
  'title': <String, Object?>{
    'params': <String, Object?>{'text': null},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Text', 'text': '\$text', 'type': 'title'}}],
  },
  'hint': <String, Object?>{
    'params': <String, Object?>{'text': null},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Text', 'text': '\$text', 'type': 'caption', 'color': 'hint'}}],
  },
  'text': <String, Object?>{
    'params': <String, Object?>{'text': null, 'color': 'normal', 'mono': false},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Text', 'text': '\$text', 'color': '\$color', 'mono': '\$mono'}}],
  },
  'badge': <String, Object?>{
    'params': <String, Object?>{'text': null, 'color': 'accent'},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Badge', 'text': '\$text', 'color': '\$color'}}],
  },
  'icon': <String, Object?>{
    'params': <String, Object?>{'name': null, 'glyph': null, 'size': null, 'color': 'normal'},
    'variants': <Object?>[<String, Object?>{'requires': <Object?>['Icon'], 'template': <String, Object?>{'kind': 'Icon', 'name': '\$name', 'glyph': '\$glyph', 'size': '\$size', 'color': '\$color'}}, <String, Object?>{'template': <String, Object?>{'kind': 'Text', 'text': '\$glyph', 'mono': true, 'color': '\$color'}}],
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
    'params': <String, Object?>{'label': null, 'variant': 'normal', 'highlight': false, 'icon': null, 'glyph': null, 'color': null, 'size': null, 'disabled': false, 'action': null},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Button', 'label': '\$label', 'variant': '\$variant', 'highlight': '\$highlight', 'icon': '\$icon', 'glyph': '\$glyph', 'color': '\$color', 'size': '\$size', 'disabled': '\$disabled', 'action': '\$action'}}],
  },
  'themeScope': <String, Object?>{
    'params': <String, Object?>{'child': null, 'data': null},
    'variants': <Object?>[<String, Object?>{'requires': <Object?>['ThemeScope'], 'template': <String, Object?>{'kind': 'ThemeScope', 'data': '\$data', 'child': '\$child'}}, <String, Object?>{'template': '\$child'}],
  },
  'actionsRow': <String, Object?>{
    'params': <String, Object?>{'buttons': null},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Row', 'gap': 12, 'children': <String, Object?>{'\$map': 'buttons', 'wrap': <String, Object?>{'kind': 'Expanded', 'child': '\$item'}}}}],
  },
  'card': <String, Object?>{
    'params': <String, Object?>{'title': null, 'variant': 'card', 'padding': null, 'margin': null, 'child': null},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Block', 'title': '\$title', 'variant': '\$variant', 'padding': '\$padding', 'margin': '\$margin', 'child': '\$child'}}],
  },
  'listRow': <String, Object?>{
    'params': <String, Object?>{'title': null, 'subtitle': null, 'trailing': null, 'action': null},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Block', 'variant': 'inset', 'padding': <String, Object?>{'horizontal': 12, 'vertical': 8}, 'action': '\$action', 'child': <String, Object?>{'kind': 'Row', 'gap': 12, 'cross': 'center', 'children': <Object?>[<String, Object?>{'kind': 'Expanded', 'child': <String, Object?>{'kind': 'Column', 'gap': 4, 'children': <Object?>[<String, Object?>{'kind': 'Text', 'text': '\$title'}, <String, Object?>{'\$require': 'subtitle', 'kind': 'Text', 'text': '\$subtitle', 'type': 'caption', 'color': 'hint'}]}}, <String, Object?>{'\$require': 'trailing', 'kind': 'Text', 'text': '\$trailing', 'color': 'hint'}]}}}],
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
  'listItem': <String, Object?>{
    'params': <String, Object?>{'id': null, 'title': null, 'subtitle': null, 'trailing': null, 'image': null, 'icon': null, 'color': 'normal', 'selected': false, 'action': null},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'id': '\$id', 'title': '\$title', 'subtitle': '\$subtitle', 'trailing': '\$trailing', 'image': '\$image', 'icon': '\$icon', 'color': '\$color', 'selected': '\$selected', 'action': '\$action'}}],
  },
  'menuItem': <String, Object?>{
    'params': <String, Object?>{'title': null, 'icon': null, 'action': null},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'title': '\$title', 'icon': '\$icon', 'action': '\$action'}}],
  },
  'sparkline': <String, Object?>{
    'params': <String, Object?>{'data': null, 'height': 1, 'glyphStyle': 'block', 'showLast': true, 'color': 'accent'},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Sparkline', 'data': '\$data', 'height': '\$height', 'glyphStyle': '\$glyphStyle', 'showLast': '\$showLast', 'color': '\$color'}}],
  },
  'progressRow': <String, Object?>{
    'params': <String, Object?>{'label': null, 'value': null, 'total': 100, 'unit': null},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Row', 'gap': 12, 'cross': 'center', 'children': <Object?>[<String, Object?>{'\$require': 'label', 'kind': 'Text', 'text': '\$label'}, <String, Object?>{'kind': 'Expanded', 'child': <String, Object?>{'kind': 'Progress', 'value': '\$value', 'total': '\$total', 'unit': '\$unit'}}]}}],
  },
  'slot': <String, Object?>{
    'params': <String, Object?>{'slot': null, 'args': null, 'fallback': null},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'UISlot', 'slot': '\$slot', 'args': '\$args', 'fallback': '\$fallback'}}],
  },
  'textVar': <String, Object?>{
    'params': <String, Object?>{'text': null, 'color': 'normal'},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'kind': 'Text', 'text': '\$text', 'color': '\$color'}}],
  },
  'varValue': <String, Object?>{
    'params': <String, Object?>{'name': null, 'fallback': null, 'unit': null},
    'variants': <Object?>[<String, Object?>{'template': <String, Object?>{'var': '\$name', 'default': '\$fallback', 'unit': '\$unit'}}],
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
/// 参数：text(text, 必填)、color(color, 默认 normal)、mono(bool, 默认 false)
Map<String, Object?> text({required Object text, String? color, bool? mono, PluginCapabilities? env}) =>
    KitRuntime.expand('text', <String, Object?>{'text': text, 'color': color, 'mono': mono}, env, kKitTemplates) ??
        <String, Object?>{};

/// 状态小标签
/// 参数：text(text, 必填)、color(color, 默认 accent)
Map<String, Object?> badge({required Object text, String? color, PluginCapabilities? env}) =>
    KitRuntime.expand('badge', <String, Object?>{'text': text, 'color': color}, env, kKitTemplates) ??
        <String, Object?>{};

/// 图标（目标不支持 Icon 时退化成 glyph 文本）
/// 参数：name(string)、glyph(string)、size(size)、color(color, 默认 normal)
Map<String, Object?> icon({String? name, String? glyph, Object? size, String? color, PluginCapabilities? env}) =>
    KitRuntime.expand('icon', <String, Object?>{'name': name, 'glyph': glyph, 'size': size, 'color': color}, env, kKitTemplates) ??
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

/// 按钮（不写 label 就是纯图标按钮，图标与文字都没有时用 glyph 当文字；color 定内容色，会盖住选中 / 禁用态）
/// 参数：label(text)、variant(enum:buttonVariant, 默认 normal)、highlight(bool, 默认 false)、icon(string)、glyph(string)、color(color)、size(size)、disabled(bool, 默认 false)、action(action)
Map<String, Object?> button({Object? label, Object? variant, bool? highlight, String? icon, String? glyph, String? color, Object? size, bool? disabled, Object? action, PluginCapabilities? env}) =>
    KitRuntime.expand('button', <String, Object?>{'label': label, 'variant': variant, 'highlight': highlight, 'icon': icon, 'glyph': glyph, 'color': color, 'size': size, 'disabled': disabled, 'action': action}, env, kKitTemplates) ??
        <String, Object?>{};

/// 子树样式作用域：包住一块内容，data 由客户端定义（musicxx 用 text / surface / button / mask / shimmer 五组颜色）；客户端不支持时只给内容，样式不生效
/// 参数：child(item, 必填)、data(json, 必填)
Map<String, Object?> themeScope({required Map<String, Object?> child, required Object data, PluginCapabilities? env}) =>
    KitRuntime.expand('themeScope', <String, Object?>{'child': child, 'data': data}, env, kKitTemplates) ??
        <String, Object?>{};

/// 一排等宽按钮（按钮列表里的每一项占一等份）
/// 参数：buttons(items, 必填)
Map<String, Object?> actionsRow({required List<Object?> buttons, PluginCapabilities? env}) =>
    KitRuntime.expand('actionsRow', <String, Object?>{'buttons': buttons}, env, kKitTemplates) ??
        <String, Object?>{};

/// 内容块（卡片）
/// 参数：title(text)、variant(enum:blockVariant, 默认 card)、padding(edges)、margin(edges)、child(item)
Map<String, Object?> card({Object? title, Object? variant, Object? padding, Object? margin, Map<String, Object?>? child, PluginCapabilities? env}) =>
    KitRuntime.expand('card', <String, Object?>{'title': title, 'variant': variant, 'padding': padding, 'margin': margin, 'child': child}, env, kKitTemplates) ??
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

/// 列表项（数据对象，给 ListViewBase / ListView 的 items 用）
/// 参数：id(string)、title(text, 必填)、subtitle(text)、trailing(text)、image(string)、icon(string)、color(color, 默认 normal)、selected(bool, 默认 false)、action(action)
Map<String, Object?> listItem({String? id, required Object title, Object? subtitle, Object? trailing, String? image, String? icon, String? color, bool? selected, Object? action, PluginCapabilities? env}) =>
    KitRuntime.expand('listItem', <String, Object?>{'id': id, 'title': title, 'subtitle': subtitle, 'trailing': trailing, 'image': image, 'icon': icon, 'color': color, 'selected': selected, 'action': action}, env, kKitTemplates) ??
        <String, Object?>{};

/// 菜单项（数据对象，给 ListView 的 menu / itemMenu 用）
/// 参数：title(text, 必填)、icon(string)、action(action)
Map<String, Object?> menuItem({required Object title, String? icon, Object? action, PluginCapabilities? env}) =>
    KitRuntime.expand('menuItem', <String, Object?>{'title': title, 'icon': icon, 'action': action}, env, kKitTemplates) ??
        <String, Object?>{};

/// 迷你趋势图
/// 参数：data(numbers, 必填)、height(int, 默认 1)、glyphStyle(enum:sparkStyle, 默认 block)、showLast(bool, 默认 true)、color(color, 默认 accent)
Map<String, Object?> sparkline({required List<num> data, int? height, Object? glyphStyle, bool? showLast, String? color, PluginCapabilities? env}) =>
    KitRuntime.expand('sparkline', <String, Object?>{'data': data, 'height': height, 'glyphStyle': glyphStyle, 'showLast': showLast, 'color': color}, env, kKitTemplates) ??
        <String, Object?>{};

/// 一行进度（左侧标签 + 进度条）
/// 参数：label(text)、value(float, 必填)、total(float, 默认 100)、unit(string)
Map<String, Object?> progressRow({Object? label, required num value, num? total, String? unit, PluginCapabilities? env}) =>
    KitRuntime.expand('progressRow', <String, Object?>{'label': label, 'value': value, 'total': total, 'unit': unit}, env, kKitTemplates) ??
        <String, Object?>{};

/// 在这里渲染一个槽位的内容（应用预留的或插件声明的）；没写 fallback 时不占位
/// 参数：slot(string, 必填)、args(json)、fallback(item)
Map<String, Object?> slot({required String slot, Object? args, Map<String, Object?>? fallback, PluginCapabilities? env}) =>
    KitRuntime.expand('slot', <String, Object?>{'slot': slot, 'args': args, 'fallback': fallback}, env, kKitTemplates) ??
        <String, Object?>{};

/// 一段带变量的文本（字符串里的 {变量 id} 由客户端绑定）
/// 参数：text(text, 必填)、color(color, 默认 normal)
Map<String, Object?> textVar({required Object text, String? color, PluginCapabilities? env}) =>
    KitRuntime.expand('textVar', <String, Object?>{'text': text, 'color': color}, env, kKitTemplates) ??
        <String, Object?>{};

/// 把某个变量绑定成值（`{"var": …}`），可用在尺寸 / 进度 / 开关等值位置
/// 参数：name(string, 必填)、fallback(json)、unit(string)
Map<String, Object?> varValue({required String name, Object? fallback, String? unit, PluginCapabilities? env}) =>
    KitRuntime.expand('varValue', <String, Object?>{'name': name, 'fallback': fallback, 'unit': unit}, env, kKitTemplates) ??
        <String, Object?>{};

