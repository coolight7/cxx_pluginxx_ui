# 组件描述 schema v1

> 本文件由 `tools/gen_ui.dart` 生成，源是 `schema/ui.def.json`。

一份界面内容 = 可选包装（`title` / `subtitle`）+ 块数组（也可以直接给块数组）：

```jsonc
{
  "title": "我的插件设置",
  "subtitle": { "key": "demo.subtitle", "fallback": "值保存在 config.json" },
  "blocks": [ { "kind": "Text", "text": "一段文字" } ]
}
```

解析规则：kind 忽略大小写；未知 kind 走 `fallback` 或跳过；未知字段忽略；未知枚举值取默认值。

## 尺寸（长度单位 u）

| 形态 | 写法 | 含义 |
|---|---|---|
| 数值（u） | `12`、`8.5` | 逻辑长度：GUI 1u = 1 逻辑像素；终端按 `caps.cell` 换算成列/行 |
| percent | `{ "percent": 50 }` | 占**直接父容器**可分配空间的比例 |
| auto | `"auto"` 或省略 | 由内容决定 |

相对关系用节点表达：`Expanded{flex}` / `Spacer{flex}` / `Row.main` / `Align`。
数值不允许为负（解析时负数按 0 处理并记一条日志）。

复数字段用 `Edges`：`12` / `{ "horizontal": 20, "vertical": 8 }` / `{ "left": 20, "top": 8 }`。

默认值（生成到三份绑定）：`defaults.gap = 12`、`defaults.cell = { width: 8, height: 20 }`。

## 文本（TextValue）

字符串，或 `{ "key": "i18n.key", "fallback": "缺键时的文本", "args": { "n": 3 } }`。
客户端优先按 `key` 取自己的语言表，取不到用 `fallback`；`args` 用于 `{n}` 这类命名占位替换。

## 动作

```jsonc
"action": "openSettings"                                  // 短写 = dispatch
"action": { "kind": "dispatch", "name": "openSettings", "args": {} }
"action": { "kind": "route",    "route": "ext://demo/settings" }
"action": { "kind": "command",  "name": "musicxx.player.play" }
"action": { "kind": "none" }
```

控件只在**值变化时立即派发**自己的动作，客户端把 `{"id":…,"value":…}` 合并进参数
（冲突时以客户端补的为准）；库不提供表单提交层，需要"保存"就自己放一个 `Button`。

## 组件全集

级别：**core** = 两个渲染目标都必须实现；**optional** = 允许客户端不实现（按适配规则降级）；
**client** = 客户端专属（`<client>.<Name>` 命名空间）。

| kind | 级别 | 归属 | 字段 | 说明 |
|---|---|---|---|---|
| `Text` | core | — | `text`* `type` `tone` `bold` `dim` `mono` `wrap` `maxLines` `align` `action` | 一段文字 |
| `Divider` | core | — | — | 分隔线（样式由客户端主题决定） |
| `Gap` | core | — | `size` | 竖直留白（缺省取 defaults.gap） |
| `Button` | core | — | `label`* `variant` `icon` `disabled` `action` | 按钮（自己处理点击） |
| `Block` | core | — | `title` `variant` `padding` `margin` `action` `children` | 卡片/内容块 |
| `Row` | core | — | `gap` `main` `cross` `action` `children` | 横向排列 |
| `Column` | core | — | `gap` `main` `cross` `action` `children` | 纵向排列 |
| `Expanded` | core | — | `flex` `children` | 按比例分剩余空间 |
| `Spacer` | core | — | `flex` | 纯占位（撑开） |
| `SizedBox` | core | — | `width` `height` `aspect` `children` | 固定尺寸/占位 |
| `Padding` | core | — | `padding`* `children` | 内边距 |
| `Align` | core | — | `align` `vertical` `children` | 对齐（终端垂直分量尽力而为） |
| `Collapse` | core | — | `id`* `title`* `expanded` `children` | 折叠分组（展开状态由客户端按 id 维护） |
| `KV` | core | — | `pairs`* `keyWidth` `sep` | 键值两列 |
| `Table` | core | — | `header` `columns`* `rows` | 表格（未指定宽度的列按内容比例分剩余空间） |
| `Tree` | core | — | `connector` `nodes`* | 层级列表 |
| `Progress` | core | — | `value`* `total` `label` `unit` `showValue` `tone` `thresholds` `width` | 进度/计量 |
| `Badge` | core | — | `text`* `tone` | 状态小标签 |
| `Control` | core | — | `control`* `id`* `label` `help` `options` `value` `disabled` `integer` `min` `max` `step` `multiline` `action` | 交互控件（值变化即派发） |
| `Markdown` | core | — | `text`* | markdown 源码 |
| `Icon` | optional | — | `name` `glyph` `size` `tone` `alt` | 图标：GUI 用 name，终端用 glyph（都没有就跳过） |
| `Stack` | optional | — | `align` `vertical` `children` | 叠放（终端适配为取最后一个子节点） |
| `Image` | optional | — | `source` `src` `width` `height` `aspect` `radius` `fit` `alt` | 图片：source 不做限制（惯例 cover/file/asset/url），取不到用 alt 兜底 |
| `Diff` | optional | — | `path` `oldStr` `newStr` | 差异对比（未实现时适配为等宽文本） |
| `Sparkline` | optional | — | `data`* `height` `glyphStyle` `min` `max` `tone` `colors` `showLast` | 迷你趋势图（未实现时适配为末值文本） |
| `Diagram` | optional | — | `mermaid`* | 状态图（未实现时适配为等宽文本） |
| `musicxx.Shader` | client | musicxx | `bundle`* `args` `speed` `maxFps` `animate` `resolutionScale` | 插件着色器（字段集照搬 shader bundle 文档；其他客户端跳过） |

`*` = 必填。字段类型：`size` = 上面三种尺寸形态；`edges` = 四边数值；`text` = TextValue；
`action` = 上面四种动作；`items` = 子块数组；其余同名。

## 适配规则（客户端不支持的块怎么降级）

| kind | 规则 | 含义 |
|---|---|---|
| `Text` | `terminal` | 收敛终点（Text）：任何客户端都必须支持 |
| `Divider` | `plainTextMono` | 该节点的纯文本，包成 Text(mono=true) |
| `Gap` | `plainTextMono` | 该节点的纯文本，包成 Text(mono=true) |
| `Button` | `plainTextMono` | 该节点的纯文本，包成 Text(mono=true) |
| `Block` | `flatten` | 展开子节点（容器不再成立，子节点各自降级） |
| `Row` | `flatten` | 展开子节点（容器不再成立，子节点各自降级） |
| `Column` | `flatten` | 展开子节点（容器不再成立，子节点各自降级） |
| `Expanded` | `flatten` | 展开子节点（容器不再成立，子节点各自降级） |
| `Spacer` | `skip` | 跳过（无降级形态） |
| `SizedBox` | `flatten` | 展开子节点（容器不再成立，子节点各自降级） |
| `Padding` | `flatten` | 展开子节点（容器不再成立，子节点各自降级） |
| `Align` | `flatten` | 展开子节点（容器不再成立，子节点各自降级） |
| `Collapse` | `flatten` | 展开子节点（容器不再成立，子节点各自降级） |
| `KV` | `plainTextMono` | 该节点的纯文本，包成 Text(mono=true) |
| `Table` | `plainTextMono` | 该节点的纯文本，包成 Text(mono=true) |
| `Tree` | `plainTextMono` | 该节点的纯文本，包成 Text(mono=true) |
| `Progress` | `plainTextMono` | 该节点的纯文本，包成 Text(mono=true) |
| `Badge` | `plainTextMono` | 该节点的纯文本，包成 Text(mono=true) |
| `Control` | `plainTextMono` | 该节点的纯文本，包成 Text(mono=true) |
| `Markdown` | `plainTextMono` | 该节点的纯文本，包成 Text(mono=true) |
| `Icon` | `glyphText` | Text(glyph)（无 glyph 则跳过） |
| `Stack` | `lastChild` | 保留最后一个子节点 |
| `Image` | `altText` | Text(alt)（无 alt 则跳过） |
| `Diff` | `plainTextMono` | 该节点的纯文本，包成 Text(mono=true) |
| `Sparkline` | `plainTextMono` | 该节点的纯文本，包成 Text(mono=true) |
| `Diagram` | `plainTextMono` | 该节点的纯文本，包成 Text(mono=true) |
| `musicxx.Shader` | `skip` | 跳过（无降级形态） |

适配保证收敛：降级结果只包含客户端声明支持的块，最多降到 `Text`（`terminal` 规则）。

## 能力段（客户端如实上报）

```jsonc
{
  "apiVersion": 1,
  "kind": "gui",                       // tui / gui，只用于粗判断
  "blocks": ["Text", "Divider", "…"],  // 实际支持的块
  "controls": ["buttons", "select", "…"],
  "cell": { "width": 8, height: 20 },  // 终端才有；GUI 省略（1u = 1 逻辑像素）
  "gap": 12,                          // 本客户端的默认行距
  "icons": ["play", "pause"],          // 可选：认识的图标名
  "percent": true, "aspect": true,     // 尺寸形态支持
}
```

> 解析规模不设上限（早期版本的层级 / 数量 / 文本字节 / 表格行列等限制已移除）。

## 越界处理

没有"按上限截断"这回事了：整份描述按原样解析，只有结构性错误（JSON 非法、
字段类型不符、组件不认识）才按规则跳过或降级。

---

本文件由 `tools/gen_ui.dart` 生成，请勿手改。
