// cxx_pluginxx_ui 定义生成器
//
// 一处定义（schema/*.def.json）→ 三份绑定（C++ / Dart / JS）的生成物 + 文档 + fixture。
//
// 用法（在库根目录）：
//   dart run tools/gen_ui.dart --check                # 校验生成物与定义一致（提交前/CI）
//   dart run tools/gen_ui.dart                        # 生成到 gen/、docs/、fixtures/
//   dart run tools/gen_ui.dart --ext-kit <扩展 kit> --prefix musicxx \
//       --namespace musicxx::ui::kit --targets cpp,js --out <目录> \
//       --source-note 'schema/musicxx-ui-kit.def.json'
//       # 扩展 kit：把基础 kit 与扩展 kit 合并后各自成篇（自包含，不引用基础 kit 头文件）
//       # --source-note 可选：写进生成物头部的"扩展 kit 定义"注释（用仓库内相对路径，
//       # 不要用绝对路径；缺省取定义文件名）
//
// 生成物：
//   gen/blocks.g.h / gen/blocks.g.dart            组件表、枚举表、默认值、上限
//   gen/adapt_rules.g.h / gen/adapt_rules.g.dart  适配规则表
//   gen/kit.g.h / gen/kit.g.dart / gen/pluginxx_ui_kit.js   基础 kit
//   docs/ui-schema.md / docs/kit.md               文档
//   fixtures/schema_samples.json                  组件样例（两端解析/降级测试共用）
//
// 校验（任何一项不通过则退出码 1）：枚举取值、level 合法、客户端专属块必须声明归属、
// adapt 覆盖全部组件、kit 模板只引用已声明组件与参数、尺寸取值非负、sample 结构自洽。

import 'dart:convert';
import 'dart:io';

const String _genHeader = '// 本文件由 tools/gen_ui.dart 生成，请勿手工修改。\n'
    '// 定义来源：schema/ui.def.json / schema/kit.def.json';

/// 生成物头部"定义来源"那一行（扩展 kit 要在它后面补上扩展定义文件）
const String _genHeaderSourceLine = '// 定义来源：schema/ui.def.json / schema/kit.def.json';

/// markdown 生成物的"本文件由…生成"那一行
const String _genDocSourceLine = '> 本文件由 `tools/gen_ui.dart` 生成。';

/// 允许的字段类型
const Set<String> _fieldTypes = <String>{
  'text',
  'string',
  'bool',
  'int',
  'float',
  'size',
  'edges',
  'tone',
  'action',
  'items',
  'pairs',
  'columns',
  'rows',
  'nodes',
  'options',
  'thresholds',
  'numbers',
  'tones',
  'json',
};

/// 允许的适配规则（只允许"降级到更简单的块或文本"，不做样式级微调）
const Map<String, String> _adaptRuleDoc = <String, String>{
  'terminal': '收敛终点（Text）：任何客户端都必须支持',
  'plainTextMono': '该节点的纯文本，包成 Text(mono=true)',
  'flatten': '展开子节点（容器不再成立，子节点各自降级）',
  'skip': '跳过（无降级形态）',
  'lastChild': '保留最后一个子节点',
  'glyphText': 'Text(glyph)（无 glyph 则跳过）',
  'altText': 'Text(alt)（无 alt 则跳过）',
};

const Set<String> _levels = <String>{'core', 'optional', 'client'};
const Set<String> _allTargets = <String>{'cpp', 'dart', 'js'};

class DefProblem implements Exception {
  DefProblem(this.message);
  final String message;
  @override
  String toString() => '定义校验失败：$message';
}

Never _fail(String message) => throw DefProblem(message);

Map<String, Object?> _readJson(String path) {
  final File file = File(path);
  if (!file.existsSync()) {
    _fail('找不到文件 $path');
  }
  final Object? value = jsonDecode(file.readAsStringSync());
  if (value is! Map) {
    _fail('$path 的根节点必须是对象');
  }
  return value.cast<String, Object?>();
}

List<Object?> _list(Object? value, String what) {
  if (value is! List) {
    _fail('$what 必须是数组');
  }
  return value;
}

Map<String, Object?> _map(Object? value, String what) {
  if (value is! Map) {
    _fail('$what 必须是对象');
  }
  return value.cast<String, Object?>();
}

String _str(Object? value, String what) {
  if (value is! String || value.isEmpty) {
    _fail('$what 必须是非空字符串');
  }
  return value;
}

String _pascal(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

String _num(num value) =>
    value == value.roundToDouble() ? value.toInt().toString() : value.toString();

/// 字段/参数类型：基本类型或 `enum:<枚举名>`
bool _isKnownType(String type) => _fieldTypes.contains(type) || type.startsWith('enum:');

/// 组件定义（schema/ui.def.json）
class UiDef {
  UiDef(this.raw);

  final Map<String, Object?> raw;

  late final int schemaVersion = raw['schemaVersion'] as int? ?? _fail('缺少 schemaVersion');
  late final int uiApiVersion = raw['uiApiVersion'] as int? ?? _fail('缺少 uiApiVersion');
  late final Map<String, Object?> defaults = _map(raw['defaults'], 'defaults');
  late final Map<String, List<String>> enums = <String, List<String>>{
    for (final MapEntry<String, Object?> entry in _map(raw['enums'], 'enums').entries)
      entry.key: _list(entry.value, 'enums.${entry.key}').cast<String>().toList(),
  };
  late final Map<String, String> adapt = <String, String>{
    for (final MapEntry<String, Object?> entry in _map(raw['adapt'], 'adapt').entries)
      entry.key: entry.value! as String,
  };
  late final List<Map<String, Object?>> blocks =
      _list(raw['blocks'], 'blocks').map((Object? v) => _map(v, 'blocks[]')).toList();

  late final Map<String, Map<String, Object?>> blockByName = <String, Map<String, Object?>>{
    for (final Map<String, Object?> b in blocks) b['kind']! as String: b,
  };

  /// 组件名 → （字段名 → 字段类型）
  late final Map<String, Map<String, String>> blockFieldTypes = <String, Map<String, String>>{
    for (final Map<String, Object?> b in blocks)
      b['kind']! as String: <String, String>{
        for (final Object? f in _list(b['fields'] ?? <Object?>[], 'blocks[].fields'))
          _map(f, 'field')['name']! as String: _map(f, 'field')['type']! as String,
      },
  };

  late final Map<String, Set<String>> blockFields = <String, Set<String>>{
    for (final MapEntry<String, Map<String, String>> entry in blockFieldTypes.entries)
      entry.key: entry.value.keys.toSet(),
  };

  double get defaultGap => (defaults['gap']! as num).toDouble();
  double get defaultCellWidth => ((defaults['cell']! as Map)['width']! as num).toDouble();
  double get defaultCellHeight => ((defaults['cell']! as Map)['height']! as num).toDouble();

  late final List<String> controlKinds = enums['controlKind']!;

  void validate() {
    if (defaults['gap'] == null || defaults['cell'] == null) {
      _fail('defaults 必须包含 gap 与 cell');
    }
    if (defaultGap < 0 || defaultCellWidth <= 0 || defaultCellHeight <= 0) {
      _fail('defaults 取值非法（gap >= 0，cell 的宽高必须为正）');
    }
    for (final MapEntry<String, List<String>> entry in enums.entries) {
      if (entry.value.isEmpty) {
        _fail('枚举 ${entry.key} 不能为空');
      }
      if (entry.value.toSet().length != entry.value.length) {
        _fail('枚举 ${entry.key} 有重复取值');
      }
      for (final String v in entry.value) {
        if (v.isEmpty || v[0] != v[0].toLowerCase() || v.contains(RegExp(r'[^A-Za-z0-9]'))) {
          _fail('枚举 ${entry.key} 的取值 `$v` 必须是小驼峰（首字母小写、只含字母数字）');
        }
      }
    }
    final Set<String> kinds = <String>{};
    for (final Map<String, Object?> block in blocks) {
      final String kind = _str(block['kind'], 'blocks[].kind');
      if (!kinds.add(kind)) {
        _fail('组件 `$kind` 重复定义');
      }
      final String level = _str(block['level'], '$kind.level');
      if (!_levels.contains(level)) {
        _fail('$kind.level 非法：$level');
      }
      if (level == 'client' && (block['client'] as String?)?.isNotEmpty != true) {
        _fail('客户端专属组件 $kind 必须声明 client');
      }
      final String? rule = adapt[kind];
      if (null == rule) {
        _fail('组件 $kind 缺少适配规则（adapt 段）');
      }
      if (!_adaptRuleDoc.containsKey(rule)) {
        _fail('$kind 的适配规则 `$rule` 未定义');
      }
      if (kind == 'Text' && rule != 'terminal') {
        _fail('Text 必须是 terminal（降级收敛终点）');
      }
      if (kind != 'Text' && rule == 'terminal') {
        _fail('$kind 不是收敛终点，不能使用 terminal');
      }
      for (final MapEntry<String, String> field in blockFieldTypes[kind]!.entries) {
        final String type = field.value;
        if (!_isKnownType(type)) {
          _fail('$kind.${field.key} 的字段类型 `$type` 未定义');
        }
        if (type.startsWith('enum:') && !enums.containsKey(type.substring(5))) {
          _fail('$kind.${field.key} 引用了未声明的枚举 ${type.substring(5)}');
        }
      }
      for (final Object? f in _list(block['fields'] ?? <Object?>[], '$kind.fields')) {
        final Map<String, Object?> field = _map(f, '$kind.field');
        if (field['type'] == 'size') {
          _checkSize(field['default'], '$kind.${field['name']}.default');
        } else if (field['type'] == 'edges') {
          _checkEdges(field['default'], '$kind.${field['name']}.default');
        }
      }
      final Object? sample = block['sample'];
      if (sample == null) {
        _fail('组件 $kind 缺少 sample');
      }
      _checkNode(sample, '$kind.sample', 0);
    }
    for (final String kind in adapt.keys) {
      if (!blockByName.containsKey(kind)) {
        _fail('适配规则引用了未声明的组件 $kind');
      }
    }
    if (adapt.length != blocks.length) {
      _fail('适配规则数量与组件数量不一致（每个组件都要有降级路径）');
    }
  }

  /// 校验尺寸取值（size 字段）：数字（u）/ "auto" / "gap" / {"percent": n} / 值表达式（{"kind": …}）
  void _checkSize(Object? value, String what) {
    if (value == null) {
      return;
    }
    if (value is num) {
      if (value < 0) {
        _fail('$what 不允许负值：$value');
      }
      return;
    }
    if (value is String) {
      if (value != 'auto' && value != 'gap') {
        _fail('$what 的取值只能是数字 / "auto" / "gap" / {"percent":n} / {"kind":…}');
      }
      return;
    }
    if (value is Map) {
      // 值表达式：具体的节点校验在客户端（GUI）侧做，这里只认形状
      if (value['kind'] is String) {
        return;
      }
      final Object? percent = value['percent'];
      if (percent is! num || percent < 0) {
        _fail('$what 的 percent 必须是非负数');
      }
      return;
    }
    _fail('$what 的取值类型非法：$value');
  }

  /// 校验四边数值（edges 字段）：数字（四边相同）或 {all/horizontal/vertical/left/right/top/bottom}
  void _checkEdges(Object? value, String what) {
    if (value == null) {
      return;
    }
    if (value is num) {
      if (value < 0) {
        _fail('$what 不允许负值：$value');
      }
      return;
    }
    if (value is! Map) {
      _fail('$what 必须是数字或四边对象');
    }
    for (final MapEntry<Object?, Object?> entry in value.entries) {
      const Set<String> keys = <String>{
        'all',
        'horizontal',
        'vertical',
        'left',
        'right',
        'top',
        'bottom',
      };
      if (!keys.contains(entry.key)) {
        _fail('$what 里的 `${entry.key}` 不是合法的边名');
      }
      if (entry.value is! num || (entry.value! as num) < 0) {
        _fail('$what.${entry.key} 必须是非负数');
      }
    }
  }

  /// 校验一个样例节点：组件存在、字段已声明、枚举取值合法、尺寸非负
  void _checkNode(Object? value, String what, int depth) {
    if (depth > 12) {
      _fail('$what 嵌套过深（样例不应超过 12 层）');
    }
    final Map<String, Object?> node = _map(value, what);
    final String kind = _str(node['kind'], '$what.kind');
    final Map<String, String>? fieldTypes = blockFieldTypes[kind];
    if (null == fieldTypes) {
      _fail('$what 引用了未声明的组件 $kind');
    }
    for (final MapEntry<String, Object?> entry in node.entries) {
      final String name = entry.key;
      if (name == 'kind' || name.startsWith(r'$')) {
        continue;
      }
      final String? type = fieldTypes[name];
      if (null == type) {
        _fail('$what（$kind）使用了未声明的字段 `$name`');
      }
      if (type.startsWith('enum:') && entry.value is String) {
        final String enumName = type.substring(5);
        if (!enums[enumName]!.contains(entry.value)) {
          _fail('$what.$name 的取值 `${entry.value}` 不在枚举 $enumName 中');
        }
      }
      if (type == 'size') {
        _checkSize(entry.value, '$what.$name');
      } else if (type == 'edges') {
        _checkEdges(entry.value, '$what.$name');
      }
      if (type == 'items') {
        for (final Object? child in _list(entry.value, '$what.$name')) {
          _checkNode(child, '$what.$name[]', depth + 1);
        }
      }
    }
  }
}

/// kit 定义（schema/kit.def.json 或扩展 kit）
/// 组件参数默认值表（默认值是 `"gap"` 表示"用客户端默认行距" → 缺省为空）
///
/// 传组件定义本身，而不是"kit + 名字"：扩展 kit 用的是**合并后**的组件列表，
/// 其中既有扩展新增的组件，也有基础 kit 的组件。
Map<String, Object?> defaultsOfComponent(Map<String, Object?> component) {
  final String name = component['name']! as String;
  final Map<String, Object?> out = <String, Object?>{};
  for (final Object? p in _list(component['params'] ?? <Object?>[], '$name.params')) {
    final Map<String, Object?> param = _map(p, '$name.param');
    final Object? def = param['default'];
    out[param['name']! as String] = def == 'gap' ? null : def;
  }
  return out;
}

class KitDef {
  KitDef(this.raw, this.ui);

  final Map<String, Object?> raw;
  final UiDef ui;

  late final int kitVersion = raw['kitVersion'] as int? ?? 1;
  late final List<Map<String, Object?>> components =
      _list(raw['components'], 'kit.components')
          .map((Object? v) => _map(v, 'kit.components[]'))
          .toList();
  late final List<Map<String, Object?>> runtime =
      _list(raw['runtime'] ?? <Object?>[], 'kit.runtime')
          .map((Object? v) => _map(v, 'kit.runtime[]'))
          .toList();

  late final Map<String, Map<String, Object?>> byName = <String, Map<String, Object?>>{
    for (final Map<String, Object?> c in components) _str(c['name'], 'kit.name'): c,
  };

  void validate() {
    final Set<String> names = <String>{};
    for (final Map<String, Object?> c in components) {
      final String name = _str(c['name'], 'kit.components[].name');
      if (!names.add(name)) {
        _fail('kit 组件 $name 重复定义');
      }
      final Set<String> params = paramNamesOf(name);
      for (final Object? p in _list(c['params'] ?? <Object?>[], '$name.params')) {
        final Map<String, Object?> param = _map(p, '$name.param');
        _str(param['name'], '$name.param.name');
        final String type = _str(param['type'], '$name.${param['name']}.type');
        if (!_isKnownType(type)) {
          _fail('$name 的参数 ${param['name']} 类型 `$type` 未声明');
        }
      }
      final List<Object?> variants = _list(c['variants'], '$name.variants');
      if (variants.isEmpty) {
        _fail('$name 至少需要一个变体');
      }
      bool hasFallback = false;
      for (final Object? v in variants) {
        final Map<String, Object?> variant = _map(v, '$name.variants[]');
        final List<Object?> requires =
            _list(variant['requires'] ?? <Object?>[], '$name.requires');
        for (final Object? need in requires) {
          if (!ui.blockByName.containsKey(need)) {
            _fail('$name 的变体要求了未声明的组件 $need');
          }
        }
        hasFallback = hasFallback || requires.isEmpty;
        _checkTemplate(variant['template'], name, params, 0);
      }
      if (!hasFallback) {
        _fail('$name 缺少无条件的兜底变体');
      }
    }
    final Set<String> runtimeNames = <String>{};
    for (final Map<String, Object?> r in runtime) {
      final String name = _str(r['name'], 'kit.runtime[].name');
      if (!runtimeNames.add(name)) {
        _fail('kit 运行时辅助 $name 重复定义');
      }
    }
  }

  Set<String> paramNamesOf(String name) => <String>{
        for (final Object? p in _list(byName[name]!['params'] ?? <Object?>[], '$name.params'))
          _map(p, '$name.param')['name']! as String,
      };

  /// 参数默认值表（默认值是 `"gap"` 表示"用客户端默认行距" → 缺省为空）
  Map<String, Object?> defaultsOf(String name) =>
      defaultsOfComponent(byName[name]!);

  void _checkTemplate(Object? value, String name, Set<String> params, int depth) {
    if (depth > 12) {
      _fail('kit 组件 $name 的模板嵌套过深');
    }
    if (value is List) {
      for (final Object? item in value) {
        _checkTemplate(item, name, params, depth + 1);
      }
      return;
    }
    if (value is! Map) {
      return;
    }
    final Map<String, Object?> node = value.cast<String, Object?>();
    final Object? mapParam = node[r'$map'];
    if (null != mapParam) {
      if (mapParam is! String || !params.contains(mapParam)) {
        _fail('$name 的 \$map 引用了未声明的参数 `$mapParam`');
      }
      if (null == node['wrap']) {
        _fail('$name 的 \$map 缺少 wrap（每一项要展开成的节点）');
      }
      _checkTemplate(node['wrap'], name, <String>{...params, 'item'}, depth + 1);
      return;
    }
    final Object? require = node[r'$require'];
    if (null != require && (require is! String || !params.contains(require))) {
      _fail('$name 的 \$require 引用了未声明的参数 `$require`');
    }
    final Object? kind = node['kind'];
    if (null != kind && kind is! String) {
      _fail('$name 的模板里 kind 必须是字符串');
    }
    if (kind is String) {
      final Set<String>? fields = ui.blockFields[kind];
      if (null == fields) {
        _fail('$name 的模板引用了未声明的组件 $kind');
      }
      for (final String key in node.keys) {
        if (key == 'kind' || key == r'$require' || fields.contains(key)) {
          continue;
        }
        _fail('$name 的模板里 $kind 使用了未声明的字段 `$key`');
      }
    }
    for (final MapEntry<String, Object?> entry in node.entries) {
      if (entry.key == 'kind' || entry.key == r'$require') {
        continue;
      }
      _checkParamRefs(entry.value, name, params);
      _checkTemplate(entry.value, name, params, depth + 1);
    }
  }

  void _checkParamRefs(Object? value, String name, Set<String> params) {
    if (value is! String) {
      return;
    }
    if (value.startsWith(r'$') && !value.contains('{')) {
      final String param = value.substring(1);
      if (!params.contains(param)) {
        _fail('$name 的模板引用了未声明的参数 `$param`');
      }
      return;
    }
    for (final RegExpMatch match in RegExp(r'\$\{([A-Za-z0-9_]+)\}').allMatches(value)) {
      final String param = match.group(1)!;
      if (!params.contains(param)) {
        _fail('$name 的模板引用了未声明的参数 `$param`');
      }
    }
  }
}

/// 生成器
class Generator {
  Generator({required this.ui, this.extKit});

  final UiDef ui;
  final KitDef? extKit;
  String namespace = 'pluginxx::ui::kit';
  String prefix = '';
  Set<String> targets = _allTargets;

  /// 扩展 kit 定义文件在生成物头部注释里的写法（`--source-note`；空 = 不改头部）
  ///
  /// 用仓库内相对路径，生成物因此在任何机器上重新生成都一致（绝对路径会带来
  /// "换台机器重新生成就整文件 diff"的麻烦）。
  String sourceNote = '';

  late final KitDef baseKit = KitDef(_readJson('schema/kit.def.json'), ui);

  /// 扩展 kit 与基础 kit 合并后的组件列表（同名覆盖，扩展新增的追加在后面）
  List<Map<String, Object?>> mergedComponents(KitDef kit) {
    if (identical(kit, baseKit)) {
      return baseKit.components;
    }
    final List<Map<String, Object?>> out = <Map<String, Object?>>[];
    final Set<String> replaced = <String>{};
    for (final Map<String, Object?> c in baseKit.components) {
      final String name = c['name']! as String;
      final Map<String, Object?>? replacement = kit.byName[name];
      out.add(replacement ?? c);
      if (null != replacement) {
        replaced.add(name);
      }
    }
    for (final Map<String, Object?> c in kit.components) {
      final String name = c['name']! as String;
      if (!replaced.contains(name) && !baseKit.byName.containsKey(name)) {
        out.add(c);
      }
    }
    return out;
  }

  void run({required bool check, bool extOnly = false, String? outDir}) {
    ui.validate();
    baseKit.validate();
    extKit?.validate();

    final KitDef kit = extKit ?? baseKit;
    final String base = prefix.isEmpty ? 'kit' : '${prefix}_ui_kit';
    final Map<String, String> files = <String, String>{};
    if (extOnly) {
      final String dir = outDir ?? '.';
      // 扩展 kit 的生成物头部补上"由哪份定义产出"（`--source-note`）
      if (targets.contains('cpp')) {
        files['$dir/$base.g.h'] = _withSourceNote(_kitH(kit, mergedComponents(kit)));
      }
      if (targets.contains('dart')) {
        files['$dir/$base.g.dart'] = _withSourceNote(_kitDart(kit, mergedComponents(kit)));
      }
      if (targets.contains('js')) {
        files['$dir/$base.js'] = _withSourceNote(_kitJs(kit, mergedComponents(kit)));
      }
      files['$dir/$base.md']
          = _withSourceNote(_kitDoc(kit, mergedComponents(kit), '扩展 kit（$prefix）'));
    } else {
      files['include/pluginxx/ui/gen/blocks.g.h'] = _blocksH();
      files['dart/lib/src/gen/blocks.g.dart'] = _blocksDart();
      files['include/pluginxx/ui/gen/adapt_rules.g.h'] = _adaptH();
      files['dart/lib/src/gen/adapt_rules.g.dart'] = _adaptDart();
      files['include/pluginxx/ui/gen/kit.g.h'] = _kitH(baseKit, baseKit.components);
      files['dart/lib/src/gen/kit.g.dart'] = _kitDart(baseKit, baseKit.components);
      files['js/pluginxx_ui_kit.js'] = _kitJs(baseKit, baseKit.components);
      files['docs/ui-schema.md'] = _schemaDoc();
      files['docs/kit.md'] = _kitDoc(baseKit, baseKit.components, '基础 kit');
      files['fixtures/schema_samples.json'] = _samplesFixture();
    }

    if (check) {
      int failed = 0;
      for (final MapEntry<String, String> entry in files.entries) {
        final File file = File(entry.key);
        if (!file.existsSync()) {
          stdout.writeln('缺失生成物：${entry.key}');
          failed++;
          continue;
        }
        if (file.readAsStringSync() != entry.value) {
          stdout.writeln('生成物与定义不一致：${entry.key}');
          failed++;
        }
      }
      if (failed > 0) {
        stderr.writeln('生成物校验失败（重跑 `dart run tools/gen_ui.dart` 后提交）');
        exitCode = 1;
      } else {
        stdout.writeln('生成物与定义一致（${files.length} 个文件）');
      }
      return;
    }

    for (final MapEntry<String, String> entry in files.entries) {
      final File file = File(entry.key);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
      stdout.writeln('写入 ${entry.key}');
    }
  }

  // ---------- C++ ----------

  String _blocksH() {
    final StringBuffer out = StringBuffer()
      ..writeln(_genHeader)
      ..writeln('#pragma once')
      ..writeln()
      ..writeln('// 组件表（kind / 级别 / 归属客户端 / 适配规则）、枚举取值、默认值与解析上限。')
      ..writeln()
      ..writeln('#include <pluginxx/ui/item.h>')
      ..writeln()
      ..writeln('#include <cstddef>')
      ..writeln('#include <string_view>')
      ..writeln()
      ..writeln('namespace pluginxx {')
      ..writeln('namespace ui {')
      ..writeln('namespace gen {')
      ..writeln()
      ..writeln('/// 定义文件结构版本（字段/组件结构变化时递增）')
      ..writeln('inline constexpr int kSchemaVersion = ${ui.schemaVersion};')
      ..writeln('/// 组件词汇版本（新增 kind / 字段 / 枚举值时递增，只增不改）')
      ..writeln('inline constexpr int kUiApiVersion = ${ui.uiApiVersion};')
      ..writeln()
      ..writeln('/// 默认留白（u）：Gap.size 的缺省值与基础 kit 的默认行距')
      ..writeln('inline constexpr double kDefaultGap = ${_num(ui.defaultGap)};')
      ..writeln('/// 终端"每个字符格相当于多少 u"的默认值（横向）')
      ..writeln('inline constexpr double kDefaultCellWidth = ${_num(ui.defaultCellWidth)};')
      ..writeln('/// 终端"每个字符格相当于多少 u"的默认值（纵向）')
      ..writeln('inline constexpr double kDefaultCellHeight = ${_num(ui.defaultCellHeight)};')
      ..writeln()
      ..writeln('/// 组件表（顺序与定义文件一致）')
      ..writeln('inline constexpr BlockMeta kBlockTable[] = {');
    for (final Map<String, Object?> block in ui.blocks) {
      final String kind = block['kind']! as String;
      out
        ..writeln('    {"$kind", BlockLevel::${_pascal(block['level']! as String)},')
        ..writeln('     "${_pascal((block['client'] as String?) ?? '')}", AdaptRule::${_pascal(ui.adapt[kind]!)},')
        ..writeln('     "${_escapeCpp((block['doc'] as String?) ?? '')}"},');
    }
    out
      ..writeln('};')
      ..writeln('inline constexpr std::size_t kBlockCount = sizeof(kBlockTable) / sizeof(kBlockTable[0]);')
      ..writeln()
      ..writeln('/// 支持的控制形态（第一版）')
      ..writeln('inline constexpr std::string_view kControlKinds[] = {');
    for (final String control in ui.controlKinds) {
      out.writeln('    "$control",');
    }
    out
      ..writeln('};')
      ..writeln()
      ..writeln('/// 枚举取值表（解析时校验，未知取值退到默认值）');
    for (final MapEntry<String, List<String>> entry in ui.enums.entries) {
      out.writeln('inline constexpr std::string_view ${_enumIdent(entry.key)}[] = {');
      for (final String value in entry.value) {
        out.writeln('    "$value",');
      }
      out.writeln('};');
    }
    out
      ..writeln()
      ..writeln('} // namespace gen')
      ..writeln('} // namespace ui')
      ..writeln('} // namespace pluginxx');
    return out.toString();
  }

  String _adaptH() {
    final StringBuffer out = StringBuffer()
      ..writeln(_genHeader)
      ..writeln('#pragma once')
      ..writeln()
      ..writeln('// 适配规则表：客户端不支持某个块时怎么降级（规则实现在 adapt.cpp）。')
      ..writeln()
      ..writeln('#include <pluginxx/ui/item.h>')
      ..writeln()
      ..writeln('#include <cstddef>')
      ..writeln('#include <string_view>')
      ..writeln()
      ..writeln('namespace pluginxx {')
      ..writeln('namespace ui {')
      ..writeln('namespace gen {')
      ..writeln()
      ..writeln('struct AdaptRuleEntry {')
      ..writeln('    std::string_view kind;')
      ..writeln('    AdaptRule        rule;')
      ..writeln('};')
      ..writeln()
      ..writeln('/// 适配规则表（见 schema/ui.def.json 的 adapt 段）')
      ..writeln('inline constexpr AdaptRuleEntry kAdaptRules[] = {');
    for (final MapEntry<String, String> entry in ui.adapt.entries) {
      out.writeln('    {"${entry.key}", AdaptRule::${_pascal(entry.value)}},');
    }
    out
      ..writeln('};')
      ..writeln('inline constexpr std::size_t kAdaptRuleCount =')
      ..writeln('    sizeof(kAdaptRules) / sizeof(kAdaptRules[0]);')
      ..writeln()
      ..writeln('} // namespace gen')
      ..writeln('} // namespace ui')
      ..writeln('} // namespace pluginxx');
    return out.toString();
  }

  // ---------- Dart ----------

  String _blocksDart() {
    final StringBuffer out = StringBuffer()
      ..writeln(_genHeader)
      ..writeln('// 组件表、枚举取值、默认值与解析上限（Dart 绑定）。')
      ..writeln()
      ..writeln("import '../model.dart';")
      ..writeln()
      ..writeln('/// 定义文件结构版本')
      ..writeln('const int kSchemaVersion = ${ui.schemaVersion};')
      ..writeln('/// 组件词汇版本（新增 kind / 字段 / 枚举值时递增，只增不改）')
      ..writeln('const int kUiApiVersion = ${ui.uiApiVersion};')
      ..writeln()
      ..writeln('/// 默认留白（u）：Gap.size 的缺省值与基础 kit 的默认行距')
      ..writeln('const double kDefaultGap = ${_num(ui.defaultGap)};')
      ..writeln('/// 终端"每个字符格相当于多少 u"的默认值（横向）')
      ..writeln('const double kDefaultCellWidth = ${_num(ui.defaultCellWidth)};')
      ..writeln('/// 终端"每个字符格相当于多少 u"的默认值（纵向）')
      ..writeln('const double kDefaultCellHeight = ${_num(ui.defaultCellHeight)};')
      ..writeln()
      ..writeln('/// 组件表（组件名 / 级别 / 归属客户端 / 适配规则）')
      ..writeln('const List<BlockMeta> kBlockTable = <BlockMeta>[');
    for (final Map<String, Object?> block in ui.blocks) {
      final String kind = block['kind']! as String;
      final String level = block['level']! as String;
      final String client = (block['client'] as String?) ?? '';
      out.writeln("  BlockMeta('$kind', BlockLevel.$level, '$client', AdaptRule.${ui.adapt[kind]}),");
    }
    out
      ..writeln('];')
      ..writeln()
      ..writeln('/// 全部组件的名字（顺序与定义文件一致）')
      ..writeln('const List<String> kBlockNames = <String>[');
    for (final Map<String, Object?> block in ui.blocks) {
      out.writeln("  '${block['kind']}',");
    }
    out
      ..writeln('];')
      ..writeln()
      ..writeln('/// 支持的控制形态（第一版）')
      ..writeln('const List<String> kControlKinds = <String>[');
    for (final String control in ui.controlKinds) {
      out.writeln("  '$control',");
    }
    out.writeln('];');
    for (final MapEntry<String, List<String>> entry in ui.enums.entries) {
      out
        ..writeln()
        ..writeln('/// 枚举 ${entry.key} 的取值')
        ..writeln('const List<String> ${_enumIdent(entry.key)} = <String>[');
      for (final String value in entry.value) {
        out.writeln("  '$value',");
      }
      out.writeln('];');
    }
    out
      ..writeln()
      ..writeln('/// 枚举名 → 取值列表')
      ..writeln('const Map<String, List<String>> kEnums = <String, List<String>>{');
    for (final String name in ui.enums.keys) {
      out.writeln("  '$name': ${_enumIdent(name)},");
    }
    out.writeln('};');
    return out.toString();
  }

  String _adaptDart() {
    final StringBuffer out = StringBuffer()
      ..writeln(_genHeader)
      ..writeln('// 适配规则表：客户端不支持某个块时怎么降级（规则实现在 adapt.dart）。')
      ..writeln("import '../model.dart';")
      ..writeln()
      ..writeln('/// 适配规则表（组件名 → 规则）')
      ..writeln('const Map<String, AdaptRule> kAdaptRules = <String, AdaptRule>{');
    for (final MapEntry<String, String> entry in ui.adapt.entries) {
      out.writeln("  '${entry.key}': AdaptRule.${entry.value},");
    }
    out.writeln('};');
    return out.toString();
  }

  // ---------- kit ----------

  /// 把扩展 kit 的定义文件写进生成物头部（`--source-note` 为空时原样返回）
  ///
  /// 代码产物改写"定义来源"那一行；markdown 产物在引用行里补一句（两者本来是
  /// 不同的头部格式）。
  String _withSourceNote(String text) {
    if (sourceNote.isEmpty) {
      return text;
    }
    if (text.contains(_genHeaderSourceLine)) {
      return text.replaceFirst(
        _genHeaderSourceLine,
        '$_genHeaderSourceLine；扩展 kit 定义：$sourceNote',
      );
    }
    return text.replaceFirst(
      _genDocSourceLine,
      '$_genDocSourceLine定义来源：`schema/ui.def.json` / `schema/kit.def.json`；'
          '扩展 kit 定义：`$sourceNote`。',
    );
  }

  String _kitH(KitDef kit, List<Map<String, Object?>> components) {
    // 扩展 kit 用客户端自己的命名空间（默认 pluginxx::ui::kit）：同名组件不会与
    // 基础 kit 冲突，插件可以同时包含两个头文件。库里的名字一律写全限定名，
    // 因此在任何命名空间深度下都能编译。
    final List<String> ns = namespace
        .split('::')
        .map((String v) => v.trim())
        .where((String v) => v.isNotEmpty)
        .toList();
    final StringBuffer out = StringBuffer()
      ..writeln(_genHeader)
      ..writeln('#pragma once')
      ..writeln()
      ..writeln('// kit：共享便捷组件。只装配、不含逻辑，也不引用客户端专属块。')
      ..writeln('// 参数用 utilxx_base::Json 传（对象），键即组件参数名：')
      ..writeln('//   $namespace::listRow({{"title", "切歌次数"}, {"trailing", "3"}})')
      ..writeln('// 传 env（客户端能力摘要）时按目标选择更合适的变体；不传 env 时产出中立描述，')
      ..writeln('// 由客户端的 adapt() 收口。')
      ..writeln()
      ..writeln('#include <pluginxx/ui/item.h>')
      ..writeln('#include <pluginxx/ui/kit_runtime.h>')
      ..writeln()
      ..writeln('#include <utilxx_base/json.h>')
      ..writeln()
      ..writeln('#include <cstddef>')
      ..writeln('#include <map>')
      ..writeln('#include <string>')
      ..writeln('#include <string_view>')
      ..writeln();
    for (final String part in ns) {
      out.writeln('namespace $part {');
    }
    out
      ..writeln()
      ..writeln('/// kit 版本')
      ..writeln('inline constexpr int kKitVersion = ${kit.kitVersion};')
      ..writeln()
      ..writeln('/// 组件模板（键 = 组件名，值是 {variants, params} 的 JSON 文本）')
      ..writeln('inline pluginxx::ui::Json kitTemplate(const std::string_view name) {')
      ..writeln('    static const std::map<std::string_view, std::string_view> kTable = {');
    for (final Map<String, Object?> c in components) {
      final String cname = c['name']! as String;
      final Map<String, Object?> payload = <String, Object?>{
        'variants': c['variants'],
        'params': defaultsOfComponent(c),
      };
      out
        ..writeln('        {"$cname",')
        ..writeln('         R"KIT(${jsonEncode(payload)})KIT"},');
    }
    out
      ..writeln('    };')
      ..writeln('    const auto it = kTable.find(name);')
      ..writeln('    if (it == kTable.end()) {')
      ..writeln('        return pluginxx::ui::Json::object();')
      ..writeln('    }')
      ..writeln('    return pluginxx::ui::Json::parse(it->second);')
      ..writeln('}')
      ..writeln()
      ..writeln('/// 按格换算成 u（count 列），env 为空时用库默认格大小')
      ..writeln('inline double cols(const int count,'
          ' const pluginxx::ui::Capabilities* env = nullptr) {')
      ..writeln('    return static_cast<double>(count) *')
      ..writeln('           (env != nullptr ? env->cell.width'
          ' : pluginxx::ui::gen::kDefaultCellWidth);')
      ..writeln('}')
      ..writeln('/// 按格换算成 u（count 行），env 为空时用库默认格大小')
      ..writeln('inline double rows(const int count,'
          ' const pluginxx::ui::Capabilities* env = nullptr) {')
      ..writeln('    return static_cast<double>(count) *')
      ..writeln('           (env != nullptr ? env->cell.height'
          ' : pluginxx::ui::gen::kDefaultCellHeight);')
      ..writeln('}')
      ..writeln()
      ..writeln('/// kit 组件（参数说明见生成的 docs/kit.md）');
    for (final Map<String, Object?> c in components) {
      final String cname = c['name']! as String;
      out
        ..writeln()
        ..writeln('/// ${c['doc'] as String? ?? ''}')
        ..writeln('/// 参数：${_paramDoc(c)}')
        ..writeln('inline pluginxx::ui::Item $cname(')
        ..writeln('    const pluginxx::ui::Json& params = pluginxx::ui::Json::object(),')
        ..writeln('    const pluginxx::ui::Capabilities* env = nullptr')
        ..writeln(') {')
        ..writeln('    return pluginxx::ui::detail::expandKit('
            '"$cname", params, env, &kitTemplate);')
        ..writeln('}');
    }
    out.writeln();
    for (final String part in ns.reversed) {
      out.writeln('} // namespace $part');
    }
    return out.toString();
  }

  String _kitDart(KitDef kit, List<Map<String, Object?>> components) {
    final StringBuffer out = StringBuffer()
      ..writeln(_genHeader)
      ..writeln('// kit：共享便捷组件。只装配、不含逻辑，也不引用客户端专属块。')
      ..writeln('// 每个组件返回一个节点（Map），交给解析层的 parseBlock() 使用；')
      ..writeln('// 传 env（客户端能力摘要）时按目标选择更合适的变体。')
      ..writeln()
      ..writeln("import '../capabilities.dart';")
      ..writeln("import '../kit_runtime.dart';")
      ..writeln("import 'blocks.g.dart';")
      ..writeln()
      ..writeln('/// kit 版本')
      ..writeln('const int kKitVersion = ${kit.kitVersion};')
      ..writeln()
      ..writeln('/// 组件模板（组件名 → {variants, params}）')
      ..writeln('const Map<String, Map<String, Object?>> kKitTemplates = '
          '<String, Map<String, Object?>>{');
    for (final Map<String, Object?> c in components) {
      final String cname = c['name']! as String;
      out
        ..writeln("  '$cname': <String, Object?>{")
        ..writeln("    'params': ${_dartLiteral(defaultsOfComponent(c))},")
        ..writeln("    'variants': ${_dartLiteral(c['variants'])},")
        ..writeln('  },');
    }
    out
      ..writeln('};')
      ..writeln()
      ..writeln('/// 按格换算成 u（count 列），env 为空时用库默认格大小')
      ..writeln('double cols(int count, {PluginCapabilities? env}) =>')
      ..writeln('    count * (env?.cell.width ?? kDefaultCellWidth);')
      ..writeln('/// 按格换算成 u（count 行），env 为空时用库默认格大小')
      ..writeln('double rows(int count, {PluginCapabilities? env}) =>')
      ..writeln('    count * (env?.cell.height ?? kDefaultCellHeight);')
      ..writeln()
      ..writeln('/// kit 组件（参数说明见生成的 docs/kit.md）');
    for (final Map<String, Object?> c in components) {
      final String cname = c['name']! as String;
      out
        ..writeln()
        ..writeln('/// ${c['doc'] as String? ?? ''}')
        ..writeln('/// 参数：${_paramDoc(c)}')
        ..writeln('Map<String, Object?> $cname({${_dartParams(c)}PluginCapabilities? env}) =>')
        ..writeln("    KitRuntime.expand('$cname', <String, Object?>{${_dartArgs(c)}}, env, kKitTemplates) ??")
        ..writeln('        <String, Object?>{};');
    }
    out.writeln();
    return out.toString();
  }

  String _kitJs(KitDef kit, List<Map<String, Object?>> components) {
    final StringBuffer out = StringBuffer()
      ..writeln(_genHeader)
      ..writeln('// kit（JS 插件用）：随插件目录分发，脚本里直接用全局 pluginxx.ui.kit。')
      ..writeln('//   const kit = pluginxx.ui.kit;')
      ..writeln("//   const row = kit.listRow({ title: '切歌次数', trailing: '3' }, env);")
      ..writeln('(function (global) {')
      ..writeln("  'use strict';")
      ..writeln('  var root = global.pluginxx || (global.pluginxx = {});')
      ..writeln('  var ui = root.ui || (root.ui = {});')
      ..writeln('  var kit = ui.kit || (ui.kit = {});')
      ..writeln('  kit.kitVersion = ${kit.kitVersion};')
      ..writeln('  kit.apiVersion = ${ui.uiApiVersion};')
      ..writeln('  kit.defaultGap = ${_num(ui.defaultGap)};')
      ..writeln('  kit.cell = { width: ${_num(ui.defaultCellWidth)}, '
          'height: ${_num(ui.defaultCellHeight)} };')
      ..writeln()
      ..writeln('  // 组件模板：变体数组 + 参数默认值')
      ..writeln('  var TEMPLATES = ${jsonEncode(<String, Object?>{
        for (final Map<String, Object?> c in components)
          c['name']! as String: <String, Object?>{
            'variants': c['variants'],
            'params': defaultsOfComponent(c),
          },
      })};')
      ..writeln()
      ..writeln(_jsExpander)
      ..writeln()
      ..writeln('  // 按格换算成 u（n 列）')
      ..writeln('  kit.cols = function (count, env) {')
      ..writeln('    return count * ((env && env.cell && env.cell.width) || kit.cell.width);')
      ..writeln('  };')
      ..writeln('  // 按格换算成 u（n 行）')
      ..writeln('  kit.rows = function (count, env) {')
      ..writeln('    return count * ((env && env.cell && env.cell.height) || kit.cell.height);')
      ..writeln('  };');
    for (final Map<String, Object?> c in components) {
      final String cname = c['name']! as String;
      out
        ..writeln()
        ..writeln('  // ${c['doc'] as String? ?? ''}')
        ..writeln('  // 参数：${_paramDoc(c)}')
        ..writeln('  kit.$cname = function (params, env) { return expand("$cname", params || {}, env); };');
    }
    out
      ..writeln('})(')
      ..writeln("  typeof globalThis !== 'undefined' ? globalThis : this")
      ..writeln(');');
    return out.toString();
  }

  // ---------- 文档与 fixture ----------

  String _schemaDoc() {
    final StringBuffer out = StringBuffer()
      ..writeln('# 组件描述 schema v${ui.uiApiVersion}')
      ..writeln()
      ..writeln('> 本文件由 `tools/gen_ui.dart` 生成，源是 `schema/ui.def.json`。')
      ..writeln()
      ..writeln('一份界面内容 = 可选包装（`title` / `subtitle`）+ 块数组（也可以直接给块数组）：')
      ..writeln()
      ..writeln('```jsonc')
      ..writeln('{')
      ..writeln('  "title": "我的插件设置",')
      ..writeln('  "subtitle": { "key": "demo.subtitle", "fallback": "值保存在 config.json" },')
      ..writeln('  "blocks": [ { "kind": "Text", "text": "一段文字" } ]')
      ..writeln('}')
      ..writeln('```')
      ..writeln()
      ..writeln('解析规则：kind 忽略大小写；未知 kind 走 `fallback` 或跳过；未知字段忽略；未知枚举值取默认值。')
      ..writeln()
      ..writeln('## 尺寸（长度单位 u）')
      ..writeln()
      ..writeln('| 形态 | 写法 | 含义 |')
      ..writeln('|---|---|---|')
      ..writeln('| 数值（u） | `12`、`8.5` | 逻辑长度：GUI 1u = 1 逻辑像素；终端按 `caps.cell` 换算成列/行 |')
      ..writeln('| percent | `{ "percent": 50 }` | 占**直接父容器**可分配空间的比例 |')
      ..writeln('| auto | `"auto"` 或省略 | 由内容决定 |')
      ..writeln('| 值表达式 | `{ "kind": "lfo", "periodMs": 1600, "from": 40, "to": 72 }` | GUI 侧每帧求值（节点表见 `plugin-shader-bundle.md` §7）；终端侧按 auto 忽略 |')
      ..writeln()
      ..writeln('相对关系用节点表达：`Expanded{flex}` / `Spacer{flex}` / `Row.main` / `Align`。')
      ..writeln('数值不允许为负（解析时负数按 0 处理并记一条日志）。')
      ..writeln()
      ..writeln('尺寸字段（以及 `Progress.value`）除了字面量还能写**值表达式**：'
          '一个带 `kind` 的对象，GUI 用与着色器参数同一套引擎求值'
          '（来源、过渡、动画、组合都在一份声明里，见 `plugin-shader-bundle.md` §7）。'
          '求值结果按 u 解释；写 `unit: "percent"` 就是"父容器比例"。')
      ..writeln()
      ..writeln('复数字段用 `Edges`：`12` / `{ "horizontal": 20, "vertical": 8 }` / `{ "left": 20, "top": 8 }`。')
      ..writeln()
      ..writeln('默认值（生成到三份绑定）：`defaults.gap = ${_num(ui.defaultGap)}`、'
          '`defaults.cell = { width: ${_num(ui.defaultCellWidth)}, height: ${_num(ui.defaultCellHeight)} }`。')
      ..writeln()
      ..writeln('## 文本（TextValue）')
      ..writeln()
      ..writeln('字符串，或 `{ "key": "i18n.key", "fallback": "缺键时的文本", "args": { "n": 3 } }`。')
      ..writeln('客户端优先按 `key` 取自己的语言表，取不到用 `fallback`；`args` 用于 `{n}` 这类命名占位替换。')
      ..writeln()
      ..writeln('## 动作')
      ..writeln()
      ..writeln('```jsonc')
      ..writeln('"action": "openSettings"                                  // 短写 = dispatch')
      ..writeln('"action": { "kind": "dispatch", "name": "openSettings", "args": {} }')
      ..writeln('"action": { "kind": "route",    "route": "ext://demo/settings" }')
      ..writeln('"action": { "kind": "command",  "name": "musicxx.player.play" }')
      ..writeln('"action": { "kind": "none" }')
      ..writeln('```')
      ..writeln()
      ..writeln('控件只在**值变化时立即派发**自己的动作，客户端把 `{"id":…,"value":…}` 合并进参数')
      ..writeln('（冲突时以客户端补的为准）；库不提供表单提交层，需要"保存"就自己放一个 `Button`。')
      ..writeln()
      ..writeln('## 组件全集')
      ..writeln()
      ..writeln('级别：**core** = 两个渲染目标都必须实现；**optional** = 允许客户端不实现（按适配规则降级）；')
      ..writeln('**client** = 客户端专属（`<client>.<Name>` 命名空间）。')
      ..writeln()
      ..writeln('| kind | 级别 | 归属 | 字段 | 说明 |')
      ..writeln('|---|---|---|---|---|');
    for (final Map<String, Object?> block in ui.blocks) {
      final StringBuffer fields = StringBuffer();
      for (final Object? f in _list(block['fields'] ?? <Object?>[], 'fields')) {
        final Map<String, Object?> field = _map(f, 'field');
        fields.write('`${field['name']}`');
        if (field['required'] == true) {
          fields.write('*');
        }
        fields.write(' ');
      }
      final String fieldText = fields.toString().trim();
      out.writeln('| `${block['kind']}` | ${block['level']} | ${(block['client'] as String?) ?? '—'} '
          '| ${fieldText.isEmpty ? '—' : fieldText} | ${block['doc'] ?? ''} |');
    }
    out
      ..writeln()
      ..writeln('`*` = 必填。字段类型：`size` = 上面三种尺寸形态；`edges` = 四边数值；`text` = TextValue；')
      ..writeln('`action` = 上面四种动作；`items` = 子块数组；其余同名。')
      ..writeln()
      ..writeln('## 适配规则（客户端不支持的块怎么降级）')
      ..writeln()
      ..writeln('| kind | 规则 | 含义 |')
      ..writeln('|---|---|---|');
    for (final MapEntry<String, String> entry in ui.adapt.entries) {
      out.writeln('| `${entry.key}` | `${entry.value}` | ${_adaptRuleDoc[entry.value]} |');
    }
    out
      ..writeln()
      ..writeln('适配保证收敛：降级结果只包含客户端声明支持的块，最多降到 `Text`（`terminal` 规则）。')
      ..writeln()
      ..writeln('## 能力段（客户端如实上报）')
      ..writeln()
      ..writeln('```jsonc')
      ..writeln('{')
      ..writeln('  "apiVersion": ${ui.uiApiVersion},')
      ..writeln('  "kind": "gui",                       // tui / gui，只用于粗判断')
      ..writeln('  "blocks": ["Text", "Divider", "…"],  // 实际支持的块')
      ..writeln('  "controls": ["buttons", "select", "…"],')
      ..writeln('  "cell": { "width": ${_num(ui.defaultCellWidth)}, height: ${_num(ui.defaultCellHeight)} },'
          '  // 终端才有；GUI 省略（1u = 1 逻辑像素）')
      ..writeln('  "gap": ${_num(ui.defaultGap)},                          // 本客户端的默认行距')
      ..writeln('  "icons": ["play", "pause"],          // 可选：认识的图标名')
      ..writeln('  "percent": true, "aspect": true,     // 尺寸形态支持')
      ..writeln('}')
      ..writeln('```')
      ..writeln()
      ..writeln('> 解析规模不设上限（早期版本的层级 / 数量 / 文本字节 / 表格行列等限制已移除）。')
      ..writeln()
      ..writeln('## 越界处理')
      ..writeln()
      ..writeln('没有"按上限截断"这回事了：整份描述按原样解析，只有结构性错误（JSON 非法、')
      ..writeln('字段类型不符、组件不认识）才按规则跳过或降级。')
      ..writeln()
      ..writeln('---')
      ..writeln()
      ..writeln('本文件由 `tools/gen_ui.dart` 生成，请勿手改。');
    return out.toString();
  }

  String _kitDoc(KitDef kit, List<Map<String, Object?>> components, String title) {
    final StringBuffer out = StringBuffer()
      ..writeln('# $title（v${kit.kitVersion}）')
      ..writeln()
      ..writeln('> 本文件由 `tools/gen_ui.dart` 生成。')
      ..writeln()
      ..writeln('纪律：① 只写数值单位 u（8 / 12 / 20 这类）；② 不引用客户端专属块；③ 不含逻辑（只装配）。')
      ..writeln('需要项目特有的间距口径时，由扩展 kit 覆盖同名组件实现。')
      ..writeln()
      ..writeln('| 组件 | 参数 | 说明 |')
      ..writeln('|---|---|---|');
    for (final Map<String, Object?> c in components) {
      final StringBuffer params = StringBuffer();
      for (final Object? p in _list(c['params'] ?? <Object?>[], 'params')) {
        final Map<String, Object?> param = _map(p, 'param');
        params.write('`${param['name']}`');
        if (param['required'] == true) {
          params.write('*');
        }
        if (param.containsKey('default')) {
          params.write('=${param['default']}');
        }
        params.write(' ');
      }
      final String paramText = params.toString().trim();
      out.writeln('| `${c['name']}` | ${paramText.isEmpty ? '—' : paramText} | ${c['doc'] ?? ''} |');
    }
    out
      ..writeln()
      ..writeln('按格换算的辅助函数（用客户端 `cell`，缺省取 `defaults.cell`）：')
      ..writeln();
    for (final Map<String, Object?> r in kit.runtime) {
      out.writeln('- `${r['name']}(n, env)`：${r['doc'] ?? ''}');
    }
    return out.toString();
  }

  String _samplesFixture() =>
      '${jsonEncode(<String, Object?>{
        'title': 'schema samples',
        'blocks': <Object?>[
          for (final Map<String, Object?> block in ui.blocks) block['sample'],
        ],
      })}\n';

  String _paramDoc(Map<String, Object?> component) {
    final List<String> out = <String>[];
    for (final Object? p in _list(component['params'] ?? <Object?>[], 'params')) {
      final Map<String, Object?> param = _map(p, 'param');
      final StringBuffer item = StringBuffer('${param['name']}(${param['type']}');
      if (param['required'] == true) {
        item.write(', 必填');
      } else if (param.containsKey('default')) {
        item.write(', 默认 ${param['default']}');
      }
      item.write(')');
      out.add(item.toString());
    }
    return out.join('、');
  }

  String _dartParams(Map<String, Object?> component) {
    final List<String> out = <String>[];
    for (final Object? p in _list(component['params'] ?? <Object?>[], 'params')) {
      final Map<String, Object?> param = _map(p, 'param');
      final String name = param['name']! as String;
      final String dartType = switch (param['type']! as String) {
        'bool' => 'bool',
        'int' => 'int',
        'float' => 'num',
        'items' => 'List<Object?>',
        'numbers' => 'List<num>',
        'tone' => 'String',
        'string' => 'String',
        _ => 'Object',
      };
      if (param['required'] == true) {
        out.add('required $dartType $name, ');
      } else if (dartType == 'Object') {
        out.add('Object? $name, ');
      } else {
        out.add('$dartType? $name, ');
      }
    }
    return out.join();
  }

  String _dartArgs(Map<String, Object?> component) {
    final List<String> out = <String>[];
    for (final Object? p in _list(component['params'] ?? <Object?>[], 'params')) {
      out.add("'${_map(p, 'param')['name']}': ${_map(p, 'param')['name']}");
    }
    return out.join(', ');
  }

  String _dartLiteral(Object? value) {
    if (value == null) {
      return 'null';
    }
    if (value is bool || value is num) {
      return '$value';
    }
    if (value is String) {
      // Dart 字符串里 `$` 是插值起头：模板里的 `$param` 必须转义
      return "'${value
          .replaceAll(r'\', r'\\')
          .replaceAll("'", r"\'")
          .replaceAll('\n', r'\n')
          .replaceAll(r'$', r'\$')}'";
    }
    if (value is List) {
      return '<Object?>[${value.map(_dartLiteral).join(', ')}]';
    }
    if (value is Map) {
      final List<String> entries = <String>[];
      for (final MapEntry<Object?, Object?> entry in value.entries) {
        entries.add("'${_escapeDollar(entry.key.toString())}': ${_dartLiteral(entry.value)}");
      }
      return '<String, Object?>{${entries.join(', ')}}';
    }
    return 'null';
  }

  /// Dart 字符串里的 `$` 是插值起头，模板键名里的 `$map` / `$require` 要转义
  static String _escapeDollar(String text) => text.replaceAll(r'$', r'\$');

  static String _enumIdent(String name) => 'kEnum${_pascal(name)}';

  static String _escapeCpp(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}

/// JS 展开器（三个绑定语义一致：整值替换 `$p`、字符串插值 `${p}`、
/// 条件节点 `$require`、列表映射 `$map` / `$item`）
const String _jsExpander = r'''
  function present(v) {
    if (v === undefined || v === null) return false;
    if (typeof v === 'string') return v.length > 0;
    return true;
  }

  function isEmpty(v) {
    if (!present(v)) return true;
    return Array.isArray(v) && v.length === 0;
  }

  function pickVariant(name, env) {
    var t = TEMPLATES[name];
    if (!t) return null;
    var variants = t.variants;
    // 目标未知（没有 env）：用第一个变体（插件作者认为最合适的那一个）
    if (!env) return variants.length ? variants[0].template : null;
    var fallback = null;
    for (var i = 0; i < variants.length; i++) {
      var need = variants[i].requires || [];
      if (need.length === 0) {
        if (fallback === null) fallback = variants[i];
        continue;
      }
      var ok = true;
      for (var j = 0; j < need.length; j++) {
        if (!env.blocks || env.blocks.indexOf(need[j]) < 0) { ok = false; break; }
      }
      if (ok) return variants[i].template;
    }
    var chosen = fallback !== null ? fallback : variants[0];
    return chosen ? chosen.template : null;
  }

  function stringify(v) {
    if (v === undefined || v === null) return '';
    if (typeof v === 'string') return v;
    if (typeof v === 'number' || typeof v === 'boolean') return String(v);
    return JSON.stringify(v);
  }

  function interpolate(text, values) {
    return text.replace(/\$\{([A-Za-z0-9_]+)\}/g, function (_, name) {
      return stringify(values[name]);
    });
  }

  function expandMap(node, values) {
    var out = [];
    if (node === null || typeof node !== 'object' || Array.isArray(node) || node.$map === undefined) {
      var single = expandNode(node, values);
      if (single !== undefined) out.push(single);
      return out;
    }
    var list = values[node.$map];
    if (!Array.isArray(list)) return out;
    for (var i = 0; i < list.length; i++) {
      var scope = {};
      for (var key in values) scope[key] = values[key];
      scope.item = list[i];
      var item = expandNode(node.wrap, scope);
      if (item !== undefined) out.push(item);
    }
    return out;
  }

  function expandNode(node, values) {
    if (typeof node === 'string') {
      if (node.length > 1 && node.charAt(0) === '$' && node.indexOf('{') < 0) {
        var value = values[node.substring(1)];
        return value === undefined ? null : value;
      }
      return node.indexOf('${') >= 0 ? interpolate(node, values) : node;
    }
    if (Array.isArray(node)) {
      var list = [];
      for (var i = 0; i < node.length; i++) list = list.concat(expandMap(node[i], values));
      return list;
    }
    if (node === null || typeof node !== 'object') return node;
    if (node.$map !== undefined) return expandMap(node, values);
    if (node.$require !== undefined && isEmpty(values[node.$require])) return undefined;
    var obj = {};
    for (var key in node) {
      if (key === '$require') continue;
      var child = expandNode(node[key], values);
      if (child === undefined || child === null) continue;
      obj[key] = child;
    }
    return obj;
  }

  function expand(name, params, env) {
    var template = pickVariant(name, env);
    if (template === null) return null;
    var declared = (TEMPLATES[name] || {}).params || {};
    var values = {};
    for (var key in declared) {
      values[key] = params[key] === undefined ? declared[key] : params[key];
    }
    for (var given in params) {
      if (values[given] === undefined) values[given] = params[given];
    }
    var result = expandNode(template, values);
    return result === undefined ? null : result;
  }

  kit.expand = expand;
''';

void main(List<String> args) {
  bool check = false;
  String? extKitPath;
  String prefix = '';
  String? outDir;
  String namespace = 'pluginxx::ui::kit';
  String sourceNote = '';
  Set<String> targets = _allTargets;
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--check':
        check = true;
      case '--ext-kit':
        extKitPath = args[++i];
      case '--source-note':
        sourceNote = args[++i];
      case '--prefix':
        prefix = args[++i];
      case '--out':
        outDir = args[++i];
      case '--namespace':
        namespace = args[++i];
      case '--targets':
        targets = args[++i]
            .split(',')
            .map((String v) => v.trim())
            .where((String v) => v.isNotEmpty)
            .toSet();
      default:
        stderr.writeln('未知参数：${args[i]}');
        exitCode = 2;
        return;
    }
  }
  for (final String target in targets) {
    if (!_allTargets.contains(target)) {
      stderr.writeln('未知的生成目标：$target');
      exitCode = 2;
      return;
    }
  }
  try {
    final UiDef ui = UiDef(_readJson('schema/ui.def.json'));
    final KitDef? ext = extKitPath == null ? null : KitDef(_readJson(extKitPath), ui);
    // 没给 --source-note 时退回定义文件名（不带目录，避免把本机绝对路径写进生成物）
    final String note = sourceNote.isNotEmpty
        ? sourceNote
        : (extKitPath == null ? '' : Uri.file(extKitPath).pathSegments.last);
    Generator(ui: ui, extKit: ext)
      ..namespace = namespace
      ..prefix = prefix
      ..targets = targets
      ..sourceNote = note
      ..run(check: check, extOnly: null != ext, outDir: outDir);
  } on DefProblem catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  }
}
