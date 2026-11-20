// 文本取值 → 屏幕上的文本
//
// `TextValue` 有三种形态：语言表里的键、字面文本、值表达式。前两种在这里解析（键查找 +
// `fallback` + `{…}` 占位替换），第三种由客户端用值表达式引擎（value_runtime.dart）求值后
// 当文本用 —— 库不强制客户端怎么求值，留一个回调。
import 'bind.dart';
import 'model.dart';

/// 解析一个文本取值
///
/// - [lookup]：语言表查询（取不到返回空串）。不传 = 没有语言表，直接用 `fallback`；
/// - [values]：变量表（`musicxx.*` / `scope:musicxx.*` / `plugin.*`），用于把 `key` /
///   `fallback` / `args` 里的 `{变量 id}` 换成值；
/// - [args]：额外的占位参数（与 `TextValue.args` 合并，同名的以这里为准）；
/// - [evalExpr]：文本写成值表达式时的求值回调（返回要显示的文本）。不传时退回
///   `TextValue.resolve`（字面文本），保证"表达式求值不了也不会画空"；
/// - [missing]：取不到的变量 id 追加到这里（一份内容汇总后记一次日志）。
String resolveTextValue(
  TextValue value, {
  String Function(String key)? lookup,
  Map<String, Object?> values = const <String, Object?>{},
  Map<String, Object?>? args,
  String Function(Object? exprNode)? evalExpr,
  List<String>? missing,
}) {
  final List<String> sink = missing ?? <String>[];
  final Object? expr = value.expr;
  if (null != expr) {
    if (null != evalExpr) {
      try {
        return evalExpr(expr);
      } catch (_) {
        // 求值失败：退回字面量那套保证（fallback → key → 空串）
      }
    }
    return value.resolve(lookup: lookup);
  }
  final TextValue bound = bindTextValue(value, values, args: args, missing: sink);
  return bound.resolve(lookup: lookup);
}
