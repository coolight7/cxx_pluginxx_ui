// 变量绑定（`{"var": …}` 与字符串里的 `{变量 id}`）
//
// 绑定是**纯 JSON 变换**：在解析（parse）之前做一次，解析 / 适配 / 纯文本 / 检查
// 都不需要认识变量。每帧才变的值不走这里，用值表达式（value_runtime.dart）。
import 'model.dart' show TextValue, stringifyValue;
import 'value_runtime.dart' show UiValueKinds;

/// 绑定的结果
class BindResult {
  const BindResult({required this.value, required this.missing});

  /// 绑定后的 JSON（需要删掉的键已经删掉）
  final Object? value;

  /// 取不到值的变量 id（同一份内容里去重，顺序按出现顺序）
  final List<String> missing;

  bool get hasMissing => missing.isNotEmpty;
}

/// 是不是一个变量 id（三种前缀之一）
///
/// - `musicxx.*`：主程序状态；
/// - `scope:musicxx.*`：槽位作用域内的状态；
/// - `plugin.<插件id>.*`：插件广播频道。
bool isVariableName(String name) =>
    name.startsWith('musicxx.') ||
    name.startsWith('scope:musicxx.') ||
    name.startsWith('plugin.');

/// 绑定值的来源
class BindValues {
  const BindValues([this.values = const <String, Object?>{}]);

  final Map<String, Object?> values;

  bool has(String name) => values.containsKey(name);

  Object? read(String name) => values[name];
}

/// 删掉这个键 / 这一项的标记（内部用）
class _Drop {
  const _Drop();
}

const _Drop _drop = _Drop();

/// 把 `{"var": …}` 与字符串里的 `{变量 id}` 换成值
///
/// 规则（与插件文档一致）：
/// - "只含 `var` / `default` / `unit` 的对象" → 取值替换；取不到时用 `default`，
///   没有 `default` 就把这个键（数组里的这一项）删掉，并记一条 `missing`；
/// - `unit = "percent"` 且值是数字 → `{"percent": 值}`；`unit = "u"`（或没写）→ 原值；
/// - 字符串里的 `{…}`：`{…}` 里是变量 id 就替换；否则看 [args] 里有没有同名参数
///   （`{n}` 这类旧写法继续可用）；都没有时换成空串并记 `missing`。
///   转义 `\{` → 字面量 `{`，`\\` → 字面量 `\`；
/// - 值表达式节点（带 `kind` 的对象）原样保留：它们的 `source` 每帧自己读变量；
/// - `musicxx.Shader.args` 不绑定（着色器参数每帧求值，不参与构建期的变量替换）。
BindResult bindVariables(
  Object? raw,
  Map<String, Object?> values, {
  Map<String, Object?>? args,
}) {
  final List<String> missing = <String>[];
  final Object? bound = _bind(raw, BindValues(values), args, missing);
  return BindResult(
    value: identical(bound, _drop) ? null : bound,
    missing: missing,
  );
}

/// 绑定一段文本里的 `{…}`（[bindVariables] 的字符串部分，单独导出便于复用）
String bindText(
  String text,
  Map<String, Object?> values, {
  Map<String, Object?>? args,
  List<String>? missing,
  bool keepUnknown = false,
}) => _bindString(
  text,
  BindValues(values),
  args,
  missing ?? <String>[],
  keepUnknown: keepUnknown,
);

bool _isPureVariable(Map<Object?, Object?> map) {
  if (!map.containsKey('var') || map['var'] is! String) {
    return false;
  }
  for (final Object? key in map.keys) {
    if (key != 'var' && key != 'default' && key != 'unit') {
      return false;
    }
  }
  return true;
}

Object? _bind(
  Object? raw,
  BindValues values,
  Map<String, Object?>? args,
  List<String> missing,
) {
  if (raw is String) {
    return _bindString(raw, values, args, missing);
  }
  if (raw is List) {
    final List<Object?> out = <Object?>[];
    for (final Object? item in raw) {
      final Object? bound = _bind(item, values, args, missing);
      if (!identical(bound, _drop)) {
        out.add(bound);
      }
    }
    return out;
  }
  if (raw is! Map) {
    return raw;
  }

  // 变量绑定：只含 var / default / unit 的对象
  if (_isPureVariable(raw)) {
    final String name = raw['var']! as String;
    final bool percent = raw['unit'] == 'percent';
    if (!values.has(name)) {
      final Object? fallback = raw['default'];
      if (null == fallback) {
        _noteMissing(missing, name);
        return _drop;
      }
      return _unit(fallback, percent);
    }
    return _unit(values.read(name), percent);
  }

  // 值表达式节点（含 `kind`）：原样保留，不做绑定
  final Object? kind = raw['kind'];
  if (kind is String && UiValueKinds.all.contains(kind)) {
    return raw;
  }
  // 着色器参数：每帧求值，不参与构建期的变量替换
  final bool keepShaderArgs = raw['kind'] == 'musicxx.Shader';

  final Map<String, Object?> out = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in raw.entries) {
    final String key = '${entry.key}';
    if (keepShaderArgs && key == 'args') {
      out[key] = entry.value;
      continue;
    }
    final Object? bound = _bind(entry.value, values, args, missing);
    if (!identical(bound, _drop)) {
      out[key] = bound;
    }
  }
  return out;
}

Object? _unit(Object? value, bool percent) {
  if (!percent || value is! num) {
    return value;
  }
  return <String, Object?>{
    'percent': value is int ? value : value.toDouble(),
  };
}

void _noteMissing(List<String> missing, String name) {
  if (!missing.contains(name)) {
    missing.add(name);
  }
}

String _bindString(
  String text,
  BindValues values,
  Map<String, Object?>? args,
  List<String> missing, {
  bool keepUnknown = false,
}) {
  if (!text.contains('{') && !text.contains('\\')) {
    return text;
  }
  final StringBuffer out = StringBuffer();
  int index = 0;
  while (index < text.length) {
    final String ch = text[index];
    if (ch == '\\' && index + 1 < text.length) {
      final String next = text[index + 1];
      if (next == '{' || next == '\\') {
        out.write(next);
        index += 2;
        continue;
      }
      out.write(ch);
      index += 1;
      continue;
    }
    if (ch != '{') {
      out.write(ch);
      index += 1;
      continue;
    }
    final int close = text.indexOf('}', index + 1);
    if (close < 0) {
      out.write(text.substring(index));
      break;
    }
    final String name = text.substring(index + 1, close);
    if (isVariableName(name)) {
      if (values.has(name)) {
        out.write(stringifyValue(values.read(name)));
      } else {
        // 变量取不到：换成空串，并记一条
        _noteMissing(missing, name);
      }
      index = close + 1;
      continue;
    }
    if (null != args && args.containsKey(name)) {
      out.write(stringifyValue(args[name]));
      index = close + 1;
      continue;
    }
    if (keepUnknown) {
      // 留给 `TextValue` 自己的占位替换（`{n}` 这种写法）
      out.write(text.substring(index, close + 1));
    } else {
      _noteMissing(missing, name);
    }
    index = close + 1;
  }
  return out.toString();
}

/// 绑定一个文本取值（`TextValue` 的 key / fallback / args 都可能带变量）
///
/// [keepUnknown] 为真时，既不是变量也不是参数、又不在 [args] 里的 `{…}` 原样保留，
/// 留给 `TextValue` 自己的占位替换（`{n}` 这种写法）。
TextValue bindTextValue(
  TextValue value,
  Map<String, Object?> values, {
  Map<String, Object?>? args,
  List<String>? missing,
}) {
  if (value.isEmpty && null == value.expr) {
    return value;
  }
  final List<String> sink = missing ?? <String>[];
  final Map<String, Object?>? rawArgs = switch (args ?? value.args) {
    final Map<Object?, Object?> map => map.cast<String, Object?>(),
    _ => null,
  };
  Map<String, Object?>? boundArgs;
  if (null != rawArgs) {
    final BindResult result = bindVariables(rawArgs, values);
    boundArgs = switch (result.value) {
      final Map<Object?, Object?> map => map.cast<String, Object?>(),
      _ => <String, Object?>{},
    };
  }
  return TextValue(
    key: _bindString(
      value.key,
      BindValues(values),
      boundArgs,
      sink,
      keepUnknown: true,
    ),
    fallback: _bindString(
      value.fallback,
      BindValues(values),
      boundArgs,
      sink,
      keepUnknown: true,
    ),
    args: boundArgs ?? value.args,
    expr: value.expr,
  );
}
