# 组件描述 schema v4

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
| 值表达式 | `{ "kind": "lfo", "periodMs": 1600, "from": 40, "to": 72 }` | GUI 侧每帧求值（节点表见 `plugin-shader-bundle.md` §7）；终端侧按 auto 忽略 |

相对关系用节点表达：`Expanded{flex}` / `Spacer{flex}` / `Row.main` / `Align`。
数值不允许为负（解析时负数按 0 处理并记一条日志）。

尺寸字段（以及 `Progress.value`）除了字面量还能写**值表达式**：一个带 `kind` 的对象，GUI 用与着色器参数同一套引擎求值（来源、过渡、动画、组合都在一份声明里，见 `plugin-shader-bundle.md` §7）。求值结果按 u 解释；写 `unit: "percent"` 就是"父容器比例"。

复数字段用 `Edges`：`12` / `{ "horizontal": 20, "vertical": 8 }` / `{ "left": 20, "top": 8 }`。

默认值（生成到三份绑定）：`defaults.gap = 12`、`defaults.cell = { width: 8, height: 20 }`。

## 文本（TextValue）

字符串，或 `{ "key": "i18n.key", "fallback": "缺键时的文本", "args": { "n": 3 } }`。
客户端优先按 `key` 取自己的语言表，取不到用 `fallback`；`args` 用于 `{n}` 这类命名占位替换。

## 值位置：字面量 / 变量 / 插值 / 表达式

尺寸、`visible`、`Progress.value`、文本、过渡块的 `value`、`AnimatedBuilder` 的通道、着色器参数这类"值位置"接受**四种写法**：

```jsonc
12                                       // 1. 字面量
{ "var": "musicxx.song.name" }            // 2. 变量绑定（渲染前算一次）
"当前歌曲 {musicxx.song.name}"             // 3. 字符串插值（渲染前算一次）
{ "kind": "smooth", "of": { "kind": "source", "name": "musicxx.spectrum.level" } }  // 4. 值表达式（可能每帧算）
```

| 写法 | 什么时候算 | 说明 |
|---|---|---|
| 字面量 | —— | 原值 |
| `{"var": id, "default"?, "unit"?}` | 每次构建前 | 取不到值时用 `default`，没有 `default` 就按"这个键没写"处理；`unit: "percent"` 把数字变成 `{"percent": n}` |
| 字符串里的 `{变量 id}` | 每次构建前 | 转义：`\{` → 字面量 `{`，`\\` → 字面量 `\`；不是变量 id 时按 `TextValue.args` 的同名参数替换（`{n}` 继续可用），都没有就换空串并记一条 `missing` |
| `{"kind": …}` | 每帧 / 每次构建 | 与着色器参数同一套引擎（节点表见 `docs/value-runtime.md`）；`source` 先按变量表解析，再回落到客户端提供的派生来源 |

变量 id 三种前缀：`musicxx.*`（客户端状态）、`scope:musicxx.*`（当前槽位作用域）、`plugin.<插件 id>.*`（插件广播频道，可跨插件）。声明用到的变量（内容的 `deps`）才会被订阅，也只有它们进 `context`。

## 动作

```jsonc
"action": "openSettings"                                  // 短写 = call（回自己）
"action": { "kind": "call", "name": "openSettings" }
"action": { "kind": "call", "name": "plugin.other.refresh", "args": {}, "timeoutMs": 800 }
"action": { "kind": "call", "name": "musicxx.player.play" }
"action": { "kind": "route", "route": "ext://demo/settings" }
"action": { "kind": "none" }
```

`call` 的能力名按前缀决定交给谁：短名回自己、`plugin.<插件 id>.<名字>` 找那个插件、`musicxx.*` 找客户端。`timeoutMs` 只收紧这一次的等待（不写 = 由客户端声明与实现者决定）。

动作**不返回界面**：要改画面就重新生成内容（`musicxx.ui.slot.update` 或 `push`）。

控件只在**值变化时立即派发**自己的动作，客户端把 `{"id":…,"value":…}` 合并进参数
（冲突时以客户端补的为准）；库不提供表单提交层，需要"保存"就自己放一个 `Button`。

## 公共字段

每个块都可以写这两个字段（不必在下面的组件表里逐个列出）：

| 字段 | 类型 | 说明 |
|---|---|---|
| `visible` | `value` | 是否渲染（字面量布尔或值表达式；求值为假时不画这一块） |
| `action` | `action` | 整块可点（写法见「动作」一节） |
`value` 类型 = 字面量（数字 / 布尔 / 字符串 / 数组 / 颜色串 / `{"percent":n}`）**或值表达式**（`{"kind": …}` 节点，见 `plugin-shader-bundle.md` §7）；
`visible` 求值为假时这一块**不渲染**（表达式每帧现算，配 `AnimatedBuilder` 就能做显隐动画）。

## 组件全集

级别：**core** = 两个渲染目标都必须实现；**optional** = 允许客户端不实现（按适配规则降级）；
**client** = 客户端专属（`<client>.<Name>` 命名空间）。

| kind | 级别 | 归属 | 字段 | 说明 |
|---|---|---|---|---|
| `Text` | core | — | `text`* `type` `color` `bold` `dim` `mono` `wrap` `maxLines` `align` | 一段文字 |
| `Divider` | core | — | — | 分隔线（样式由客户端主题决定） |
| `Gap` | core | — | `size` | 竖直留白（缺省取 defaults.gap） |
| `Button` | core | — | `label` `variant` `highlight` `icon` `glyph` `color` `size` `disabled` | 按钮（自己处理点击）：variant 定样式与宽度，highlight 定选中态，size 定高度；不写 label 就是纯图标按钮（图标与文字都没有时用 glyph 当文字），color 定内容色（会盖住选中 / 禁用态） |
| `Block` | core | — | `title` `variant` `padding` `margin` `child` | 卡片/内容块 |
| `Row` | core | — | `gap` `main` `cross` `children` | 横向排列 |
| `Column` | core | — | `gap` `main` `cross` `children` | 纵向排列 |
| `Expanded` | core | — | `flex` `child` | 按比例分剩余空间 |
| `Spacer` | core | — | `flex` | 纯占位（撑开） |
| `SizedBox` | core | — | `width` `height` `aspect` `child` | 固定尺寸/占位 |
| `Padding` | core | — | `padding`* `child` | 内边距 |
| `Align` | core | — | `align` `vertical` `child` | 对齐（终端垂直分量尽力而为） |
| `Collapse` | core | — | `id`* `title`* `expanded` `child` | 折叠分组（展开状态由客户端按 id 维护） |
| `ThemeScope` | optional | — | `data` `child` | 子树样式作用域：包住一块内容，子树按 data 里声明的配色取色；data 的含义由客户端定义（客户端不支持时展开 child，样式不生效，内容照常显示） |
| `KV` | core | — | `pairs`* `keyWidth` `sep` | 键值两列 |
| `Table` | core | — | `header` `columns`* `rows` | 表格（未指定宽度的列按内容比例分剩余空间） |
| `Tree` | core | — | `connector` `nodes`* | 层级列表 |
| `Progress` | core | — | `value`* `total` `label` `unit` `showValue` `color` `thresholds` `width` | 进度/计量 |
| `Badge` | core | — | `text`* `color` | 状态小标签 |
| `Control` | core | — | `control`* `id`* `label` `help` `options` `value` `disabled` `integer` `min` `max` `step` `multiline` | 交互控件（值变化即派发） |
| `Markdown` | core | — | `text`* | markdown 源码 |
| `Icon` | optional | — | `name` `glyph` `size` `color` `alt` | 图标：GUI 用 name，终端用 glyph（都没有就跳过） |
| `Stack` | optional | — | `align` `vertical` `children` | 叠放（终端适配为取最后一个子节点） |
| `Image` | optional | — | `source` `src` `width` `height` `aspect` `radius` `blur` `opacity` `fit` `alt` | 图片：source 不做限制（惯例 cover/file/asset/url），取不到用 alt 兜底；支持圆角、模糊与不透明度 |
| `Diff` | optional | — | `path` `oldStr` `newStr` | 差异对比（未实现时适配为等宽文本） |
| `Sparkline` | optional | — | `data`* `height` `glyphStyle` `min` `max` `color` `colors` `showLast` | 迷你趋势图（未实现时适配为末值文本） |
| `Diagram` | optional | — | `mermaid`* | 状态图（未实现时适配为等宽文本） |
| `ListViewBase` | optional | — | `id` `items`* `layout` `variant` `height` `padding` `header` `footer` `emptyText` `itemAction` | 按应用的列表组件显示多条数据（只显示，没有工具条与编辑）。列表项除了 title/subtitle/trailing/image/icon/color/selected/action，还可写 custom（任意块，写了就整项内容由它画，行内自动插入的编辑/多选/拖拽按钮不受影响）、path（路径/身份）、isDir（目录项）与 data（附加数据，任意 JSON：本库只当原文携带，由客户端自己解释） |
| `ListView` | optional | — | `id` `items`* `layout` `variant` `height` `padding` `header` `footer` `emptyText` `itemAction` `toolbar` `menu` `itemMenu` `editAction` `saveAction` `addAction` `removeAction` `removeCheckedAction` `removeTipTitle` `positionAction` `refreshAction` `loadMoreAction` `enableCheck` `enableDrop` `showCount` | 带工具条的列表（编辑 / 多选 / 加删 / 定位 / 菜单 / 下拉刷新 / 加载更多）。列表项除 title/subtitle/trailing/image/icon/color/selected/action 外还可写 custom（任意块，整项内容由它画；行内自动插入的编辑/多选/拖拽按钮保留）、path、isDir、data |
| `musicxx.DirListView` | client | musicxx | `id` `path` `items`* `multi` `showPath` `pathAction` `itemAction` `selectAction` `refreshAction` `loadMoreAction` `height` `padding` `variant` `emptyText` | 目录/文件列表（对应客户端内置的 DirList）：一层目录的条目，顶部路径栏（可带“上一级”动作）；写了 multi 才在行尾出勾选框（勾选态取条目的 selected，变化派发 selectAction）；给了 refreshAction / loadMoreAction 就能在列表内下拉刷新、滑到底加载更多；条目带 data（附加数据）时由本客户端自己解释（musicxx：data.song = 这一项是一首歌，画成歌曲样式；其他客户端按普通列表降级）；进入目录与选中态都由插件维护 |
| `musicxx.SongListView` | client | musicxx | `id` `items`* `layout` `variant` `height` `padding` `emptyText` `itemMenu` | 歌曲结果列表（对应客户端内置的歌曲列表）：条目只需要 data.song（type / src / artist / name / fileName / size / durationMs / cover，与 musicxx.DirListView 的歌曲项同一套写法）；行样式、点行播放（整份结果当作播放队列）、内置歌曲菜单、空列表提示都由客户端画；itemMenu 的项排在内置菜单之后，点了派发给插件（参数带 listId / index / itemId）；进播放页跟随客户端设置，其它客户端退成文本列表 |
| `musicxx.AdaptLayout` | client | musicxx | `columnBody`* `rowBody`* `columnSecondBody` `rowSecondBody` `rowBodyRatio` `columnBodyRatio` `enableAnimations` | 按窗口宽高比切换两套内容（对应客户端内置的 XXAdaptiveLayout）：宽高比 < 1 用 columnBody，否则用 rowBody；给了第二套就按比例分两栏（其他客户端用 rowBody） |
| `musicxx.Shader` | client | musicxx | `bundle`* `args` `speed` `maxFps` `animate` `resolutionScale` | 插件着色器（字段集照搬 shader bundle 文档；其他客户端跳过） |
| `musicxx.AnimatedBuilder` | client | musicxx | `values` `maxFps` `child` | 动画作用域：声明若干通道（each 是一条值表达式），子树每帧重建（其他客户端展开子节点） |
| `musicxx.SizeTransition` | client | musicxx | `axis` `axisAlignment` `value` `curve` `child` | 尺寸过渡：按 value（0~1）把子节点从 0 撑开 / 收拢（其他客户端展开子节点） |
| `musicxx.FadeTransition` | client | musicxx | `value` `curve` `child` | 透明度过渡：按 value（0~1）淡入淡出（其他客户端展开子节点） |
| `musicxx.SlideTransition` | client | musicxx | `from` `to` `value` `curve` `child` | 位移动画：按 value（0~1）从 from 移到 to（单位 = 自身尺寸的倍数；其他客户端展开子节点） |
| `musicxx.ScaleTransition` | client | musicxx | `from` `to` `value` `curve` `child` | 缩放动画：按 value（0~1）从 from 缩放到 to（其他客户端展开子节点） |
| `musicxx.RotationTransition` | client | musicxx | `from` `to` `value` `curve` `child` | 旋转动画：按 value（0~1）从 from 转到 to（单位 = 圈数；其他客户端展开子节点） |
| `UISlot` | optional | — | `slot`* `args` `fallback` | 在那位置渲染另一个槽位的内容：可以是应用预留的槽位，也可以是插件自己声明（musicxx.ui.slot.define）的槽位。作用域变量继续有效，并额外提供 scope:musicxx.slot.args（块上的 args）；没有注册内容、内容解析不出来、槽位被撤销或嵌套循环时画 fallback，没有 fallback 就不占位。只接受 insert / replace 两种槽位，嵌套深度最多 4 层 |

`*` = 必填。字段类型：`size` = 上面三种尺寸形态；`edges` = 四边数值；`text` = TextValue；
`action` = 上面四种动作；`item` = 一个子块（对象）；`items` = 子块数组；其余同名。

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
| `ThemeScope` | `flatten` | 展开子节点（容器不再成立，子节点各自降级） |
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
| `ListViewBase` | `plainTextMono` | 该节点的纯文本，包成 Text(mono=true) |
| `ListView` | `plainTextMono` | 该节点的纯文本，包成 Text(mono=true) |
| `musicxx.DirListView` | `plainTextMono` | 该节点的纯文本，包成 Text(mono=true) |
| `musicxx.SongListView` | `plainTextMono` | 该节点的纯文本，包成 Text(mono=true) |
| `musicxx.AdaptLayout` | `flatten` | 展开子节点（容器不再成立，子节点各自降级） |
| `musicxx.Shader` | `skip` | 跳过（无降级形态） |
| `musicxx.AnimatedBuilder` | `flatten` | 展开子节点（容器不再成立，子节点各自降级） |
| `musicxx.SizeTransition` | `flatten` | 展开子节点（容器不再成立，子节点各自降级） |
| `musicxx.FadeTransition` | `flatten` | 展开子节点（容器不再成立，子节点各自降级） |
| `musicxx.SlideTransition` | `flatten` | 展开子节点（容器不再成立，子节点各自降级） |
| `musicxx.ScaleTransition` | `flatten` | 展开子节点（容器不再成立，子节点各自降级） |
| `musicxx.RotationTransition` | `flatten` | 展开子节点（容器不再成立，子节点各自降级） |
| `UISlot` | `skip` | 跳过（无降级形态） |

适配保证收敛：降级结果只包含客户端声明支持的块，最多降到 `Text`（`terminal` 规则）。

## 能力段（客户端如实上报）

```jsonc
{
  "apiVersion": 4,
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
