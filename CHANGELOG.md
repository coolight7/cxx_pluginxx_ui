# 变更记录

## 0.2.0（未发布）

- 新增通用块 `UISlot`（`slot` / `args` / `fallback`）：在界面里嵌一个槽位，可以嵌应用预留的，
  也可以是插件自己声明、由别的插件填内容的位置；适配规则是 `skip`，纯文本降级画 `fallback`。
- 动作合并成 `call` / `route` / `none`：字符串短写等于 `call`；`call` 的能力名按前缀决定交给谁
  （短名回自己、`plugin.<插件 id>.<名字>` 找那个插件、`musicxx.*` 找应用）；`call` 可以带 `timeoutMs`。
- 值位置扩展为四种写法（字面量 / 变量绑定 / 字符串插值 / 值表达式），新增 Dart 运行时：
  `bind.dart`、`value_runtime.dart`、`text_runtime.dart`、`size_runtime.dart`。
- 新增槽位与内容运行时：`slot.dart`（`SlotSpec` / `SlotCatalogue` / `SlotChoice`）与
  `content_hub.dart`（`ContentHub`：缓存、激活、依赖订阅、串行刷新、记忆化、嵌套保护）。
- 能力段增加 `slots` / `values` 两段：客户端如实上报支持哪些槽位形态、是否支持 `args` / `fallback` /
  声明槽位、嵌套深度，以及三种值写法。
- kit 增加 `slot` / `textVar` / `varValue`。
- `uiApiVersion` 抬到 4。
