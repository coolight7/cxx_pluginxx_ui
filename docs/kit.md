# 基础 kit（v1）

> 本文件由 `tools/gen_ui.dart` 生成。

纪律：① 只写数值单位 u（8 / 12 / 20 这类）；② 不引用客户端专属块；③ 不含逻辑（只装配）。
需要项目特有的间距规则时，由扩展 kit 覆盖同名组件实现。

| 组件 | 参数 | 说明 |
|---|---|---|
| `title` | `text`* | 标题行 |
| `hint` | `text`* | 次要说明行 |
| `text` | `text`* `tone`=normal `mono`=false | 正文行 |
| `badge` | `text`* `tone`=accent | 状态小标签 |
| `icon` | `name` `glyph` `size` `tone`=normal | 图标（目标不支持 Icon 时退化成 glyph 文本） |
| `gap` | `size`=gap | 竖直留白（缺省用客户端默认行距） |
| `divider` | — | 分隔线 |
| `button` | `label`* `variant`=secondary `icon` `disabled`=false `action` | 按钮 |
| `actionsRow` | `buttons`* | 一排等宽按钮（按钮列表里的每一项占一等份） |
| `card` | `title` `variant`=card `padding` `margin` `children` | 内容块（卡片） |
| `listRow` | `title`* `subtitle` `trailing` `action` | 卡片里的一行（标题 + 可选副标题 + 可选右侧文字） |
| `section` | `title`* `rows`* | 小节标题 + 若干行 |
| `kv` | `pairs`* `sep` | 键值块（键列按最长键自适应） |
| `table` | `columns`* `rows` `header`=true | 表格（未指定的列宽由客户端自动分配） |
| `tree` | `nodes`* `connector`=true | 层级列表 |
| `sparkline` | `data`* `height`=1 `glyphStyle`=block `showLast`=true `tone`=accent | 迷你趋势图 |
| `progressRow` | `label` `value`* `total`=100 `unit` | 一行进度（左侧标签 + 进度条） |

按格换算的辅助函数（用客户端 `cell`，缺省取 `defaults.cell`）：

- `cols(n, env)`：n 列对应的 u 值（按客户端 cell 换算，缺省用 defaults.cell）
- `rows(n, env)`：n 行对应的 u 值（按客户端 cell 换算，缺省用 defaults.cell）
