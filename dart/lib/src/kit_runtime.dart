// kit 运行时：把 kit 模板 + 参数展开成组件项（Dart 绑定）
//
// 与 C++（src/kit_runtime.cpp）和 JS（js/pluginxx_ui_kit.js）语义一致：
//
// | 写法 | 含义 |
// |---|---|
// | `"$name"` | 整值替换：字段/元素换成该参数的值（缺省或空 → 字段省略、元素跳过） |
// | `"${name}"` | 字符串插值：把参数值拼进字面文本 |
// | `{"$require": "name", …}` | 该参数缺省或为空时整个节点跳过 |
// | `{"$map": "name", "wrap": {…"$item"…}}` | 把列表参数逐项展开（`$item` 是当前项） |
import 'capabilities.dart';
import 'model.dart';

/// kit 组件模板（组件名 → {variants, params}）；由生成的 kit 文件提供
typedef KitTemplates = Map<String, Map<String, Object?>>;

/// kit 模板展开
class KitRuntime {
  KitRuntime._();

  /// 展开一个 kit 组件
  ///
  /// - [params] 是参数表（缺的参数用模板里的默认值）
  /// - [env] 为空 = 目标未知（产出中立描述，由客户端的 adapt() 收口）
  /// - [templates] 是生成的模板表（如 gen/kit.g.dart 的 `kKitTemplates`）
  static Map<String, Object?>? expand(
    String name,
    Map<String, Object?> params,
    PluginCapabilities? env,
    KitTemplates templates,
  ) {
    final Map<String, Object?>? definition = templates[name];
    if (null == definition) {
      return null;
    }
    final Object? template = _pickVariant(definition, env);
    if (template is! Map) {
      return null;
    }
    final Map<String, Object?> declared = _asMap(definition['params']) ?? <String, Object?>{};
    final Map<String, Object?> values = <String, Object?>{};
    for (final MapEntry<String, Object?> entry in declared.entries) {
      values[entry.key] = params.containsKey(entry.key) && null != params[entry.key]
          ? params[entry.key]
          : entry.value;
    }
    for (final MapEntry<String, Object?> entry in params.entries) {
      values.putIfAbsent(entry.key, () => entry.value);
    }
    final Object? result = expandNode(template, values, env);
    return _asMap(result);
  }

  /// 展开模板节点（对外暴露，便于测试与自定义 kit）
  static Object? expandNode(
    Object? node,
    Map<String, Object?> values,
    PluginCapabilities? env,
  ) {
    if (node is String) {
      if (node.length > 1 && node.startsWith(r'$') && !node.contains('{')) {
        return values[node.substring(1)];
      }
      return node.contains(r'${') ? interpolate(node, values) : node;
    }
    if (node is List) {
      final List<Object?> out = <Object?>[];
      for (final Object? element in node) {
        out.addAll(_expandMap(element, values, env));
      }
      return out;
    }
    if (node is! Map) {
      return node;
    }
    if (node.containsKey(r'$map')) {
      return _expandMap(node, values, env);
    }
    final Object? require = node[r'$require'];
    if (require is String && _isEmpty(values[require])) {
      return null;
    }
    final Map<String, Object?> out = <String, Object?>{};
    final Map<String, Object?> nodeMap = node.cast<String, Object?>();
    for (final MapEntry<String, Object?> entry in nodeMap.entries) {
      if (entry.key == r'$require') {
        continue;
      }
      final Object? child = expandNode(entry.value, values, env);
      if (null == child) {
        continue;
      }
      out[entry.key] = child;
    }
    return out;
  }

  /// 字符串插值：把 `${name}` 换成参数值的文本形态
  static String interpolate(String text, Map<String, Object?> values) =>
      text.replaceAllMapped(RegExp(r'\$\{([A-Za-z0-9_]+)\}'), (Match match) {
        return stringifyValue(values[match.group(1)]);
      });

  static List<Object?> _expandMap(
    Object? node,
    Map<String, Object?> values,
    PluginCapabilities? env,
  ) {
    final List<Object?> out = <Object?>[];
    final Map<String, Object?>? map = _asMap(node);
    final Object? param = map?[r'$map'];
    if (null == map || param is! String) {
      final Object? single = expandNode(node, values, env);
      if (null != single) {
        out.add(single);
      }
      return out;
    }
    final Object? list = values[param];
    if (list is! List) {
      return out;
    }
    for (final Object? element in list) {
      final Map<String, Object?> scope = Map<String, Object?>.of(values)..['item'] = element;
      final Object? expanded = expandNode(map['wrap'], scope, env);
      if (null != expanded) {
        out.add(expanded);
      }
    }
    return out;
  }

  /// 变体选择：第一个 `requires` 全部被 env 支持的变体生效；
  /// env 为空时用第一个变体
  static Object? _pickVariant(Map<String, Object?> definition, PluginCapabilities? env) {
    final Object? variants = definition['variants'];
    if (variants is! List || variants.isEmpty) {
      return null;
    }
    if (null == env) {
      return _asMap(variants[0])?['template'];
    }
    Map<String, Object?>? fallback;
    for (final Object? raw in variants) {
      final Map<String, Object?>? variant = _asMap(raw);
      if (null == variant) {
        continue;
      }
      final Object? requires = variant['requires'];
      if (requires is! List || requires.isEmpty) {
        fallback ??= variant;
        continue;
      }
      bool ok = true;
      for (final Object? need in requires) {
        if (need is! String || !env.supportsBlock(need)) {
          ok = false;
          break;
        }
      }
      if (ok) {
        return variant['template'];
      }
    }
    return (fallback ?? _asMap(variants[0]))?['template'];
  }

  static bool _isEmpty(Object? value) {
    if (null == value) {
      return true;
    }
    if (value is String) {
      return value.isEmpty;
    }
    if (value is List) {
      return value.isEmpty;
    }
    return false;
  }

  static Map<String, Object?>? _asMap(Object? value) =>
      value is Map ? value.cast<String, Object?>() : null;
}
