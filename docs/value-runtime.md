# 值表达式（每帧求值的值）

> 与 `docs/ui-schema.md` 的「值位置」一节配合看：值位置接受字面量、变量绑定、字符串插值，
> 以及**本文件描述的值表达式**（带 `kind` 的对象）。

值表达式适合"每帧都可能变"的值：进度条跟着播放位置走、按钮随音量为 0/1、着色器参数跟着频谱。
它只负责**算出一个值**，不关心消费者是着色器参数、块尺寸还是文本。

用法（Dart）：

```dart
final UiValueParseResult parsed = parseUiArgsTable(pluginArgsJson);
final Map<String, UiValue> values = parsed.table.evaluate(ctx);
// values['uLevel'].number / .flag / .asText() / .asVec4()
```

- 同一份 JSON 只解析一次，结果（节点树）可以长期持有；`smooth` / `tween` / `lfo` 的状态存在节点里，
  所以**换歌 / 换样式时要 `table.resetState()`**，否则过渡会带着上一首的残留值。
- 解析失败的项被忽略并给出原因（`problems`），同一份声明里的其它项照常工作。
- 节点数 / 嵌套深度有上限（`UiValueLimits`），超过只影响这一项。

## 节点表

| kind | 参数 | 说明 |
|---|---|---|
| `source` | `name`*、`scope`、`fallback`、`fallbackNight`、`convert` | 读一个具名来源：先按变量表（`musicxx.*` / `scope:*` / `plugin.*`），再回落到客户端提供的派生来源（主题色 / 封面色 / 频谱 / 环境量） |
| `const` | `value`*、`night`、`unit` | 常量（颜色串、数字、数组、文本）；`night` 是夜间模式下的替值；`unit: "percent"` 表示尺寸位置按父容器比例 |
| `tween` | `from`、`to`、`durationMs`、`delayMs`、`ease`、`repeat`、`phase` | 按时间在 from→to 之间插值（`ease` = `linear` / `inQuad` / `outQuad` / `inOutQuad` / `inCubic` / `outCubic` / `inOutCubic` / `inSine` / `outSine` / `inOutSine` / `outBack` / `outElastic`；`repeat` = `once` / `loop` / `pingpong`） |
| `lfo` | `shape`、`periodMs`、`from`、`to`、`phase` | 周期振荡（`shape` = `sine` / `triangle` / `saw` / `square`） |
| `smooth` | `of`*、`attackMs`、`releaseMs`（或 `ms`） | 一阶过渡：目标跳变时按起音 / 释音时间追上去（音乐可视化常用"快起慢落"） || `add` `mul` `min` `max` | `of`*（数组） | 逐分量组合 |
| `mix` | `a`*、`b`*、`t`* | `a*(1-t) + b*t` |
| `clamp` | `of`*、`min`、`max` | 夹到区间 |
| `remap` | `of`*、`inMin`、`inMax`、`outMin`、`outMax` | 区间映射 |
| `format` | `value`*、`text`* | 按模板拼文本（`{0}` 是 value） |
| `concat` | `of`* | 拼接文本 |
| `cmp` | `a`*、`b`*、`op` | 比较（`eq` / `ne` / `lt` / `le` / `gt` / `ge`），结果是 0/1 |
| `logicAnd` `logicOr` | `of`* | 逻辑与 / 或 |
| `logicNot` | `of`* | 逻辑非 |
| `select` | `cond`*、`then`*、`else`* | 按条件取一个 |

`*` = 必填。所有节点都可以嵌其它节点；`of` 也可以直接写一个值（数字 / 字符串）。

## 求值上下文

```dart
class UiValueCtx {
  final double timeSec;      // 动画时间（秒）；animate 关闭时恒为 0
  final double dtSec;        // 距上一帧（客户端要钳制，避免不可见恢复后一步跳完）
  final bool night;          // 是否夜间
  final bool paletteValid;   // 封面配色是否可用
  final bool spectrumAvailable; // 频谱数据是否可用
  final bool coverAvailable;    // 当前有没有封面
  final UiValueSourceResolver sources; // 具名来源的解析（客户端实现）
  final UiValueScope? scope;            // 局部通道链（AnimatedBuilder.values）
}
```

客户端每帧构造一次；**不在逐帧区域里的值**用 `timeSec = dtSec = 0` 求值一次即可
（只有跟状态走的取值会生效）。

## 局部通道

`musicxx.AnimatedBuilder.values` 用名字定义通道，子树里的 `source` 先在这些名字里找
（内层覆盖外层），找不到才去问客户端：

```jsonc
{
  "kind": "musicxx.AnimatedBuilder",
  "values": {
    "h": { "kind": "lfo", "periodMs": 1600, "from": 40, "to": 72 },
    "level": { "kind": "smooth", "of": { "kind": "source", "name": "musicxx.spectrum.level" } }
  },
  "child": { "kind": "Text", "text": "高度" }
}
```

`source` 的 `scope` 可以显式指定 `local`（只看局部通道）/ `auto`（默认：局部 → 变量 → 派生来源）。

## 尺寸位置

尺寸字段（`SizeValue`）与 `Progress.value` 也接受节点；求值结果按 u 解释，
节点写 `unit: "percent"`（或 `const` 的 unit）时按父容器可分配空间的比例解释 ——
Dart 侧用 `resolveSize(size, available:, expr: ExprSize(...))` 换算。
