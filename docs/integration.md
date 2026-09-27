# 接入指引（integration）

这份文档写给三类人：

| 角色 | 要做的事 | 看哪几节 |
|---|---|---|
| **客户端**（真正的渲染器：终端界面、Flutter 界面） | 声明并发布自己的能力，解析插件的描述、适配、渲染、把控件与动作接起来 | §2、§4（控件与动作）、§8（新增渲染器清单） |
| **宿主**（转发内容、不渲染，例如 musicxx 的原生宿主库） | 只把能力段与内容原样搬运，更新 C ABI 配置 | §3 |
| **插件作者** | 用构建器或 kit 组装描述，按能力协商选择组件 | §5、§6 |

组件的字段、枚举与适配规则见生成的 [`ui-schema.md`](ui-schema.md)，基础 kit 见
[`kit.md`](kit.md)。

---

## 1. 依赖接入

### 1.1 C++

```cmake
find_package(cxx_pluginxx_ui CONFIG REQUIRED)
target_link_libraries(<你的目标> PRIVATE cxx_pluginxx_ui_static)
```

- `cxx_pluginxx_ui`（INTERFACE，只有头）：只写构建器、只序列化 `<pluginxx/ui.h>` 里的模型时够用；
- `cxx_pluginxx_ui_static`（静态库）：用到 `parse*` / `adapt*` / `plainText*` / `lint*` /
  `capabilitiesToJson` 这些有实现的部分时必须链接它（宿主库与插件 SDK 都要链，插件才画得出描述）。

库本身依赖 `cxx_utilxx_base`（JSON）与 `fmt`，由 CMake 的 `find_dependency` 自动解析；
头文件部分零依赖（`item.h` 只用标准库）。

### 1.2 Dart

```yaml
dependencies:
  pluginxx_ui:
    path: <本库>/dart
```

客户端包建议再写一个**转发出口**（musicxx 的 `package_extend/musicxx_extern_plugin/lib/pluginxx_ui.dart`）：
应用层只从转发出口导入，就不必在自己的 `pubspec.yaml` 里再声明一次路径依赖。

导入后可直接用（与 C++ 绑定同名同义）：

```dart
import 'package:pluginxx_ui/pluginxx_ui.dart';

final ParseReport report = ParseReport();
final UiDocument doc = parseDocument(jsonFromPlugin, report: report);
final UiDocument renderable = adaptDocument(doc, myCapabilities);
for (final ItemData block in renderable.blocks) {
  // 按 block.kind 渲染
}
```

### 1.3 JS

把 `js/pluginxx_ui_kit.js`（或客户端扩展 kit）**随插件目录分发**，让插件清单按顺序装载它：

```yaml
# plugin.yaml
scripts: [pluginxx_ui_kit.js, <client>_ui_kit.js, plugin.js]
```

脚本执行后全局有 `pluginxx.ui.kit`（扩展 kit 与基础 kit 写的是同一个对象，后加载的覆盖同名组件）。
宿主**不要**内置预置 kit：改了 kit 就会影响已经装好的插件。

### 1.4 子模块与生成物

- 库通过 git submodule 接入（agentxx：`agent/third_party/cxx_pluginxx_ui`；
  musicxx：`package_extend/musicxx_extern_plugin/src/third_party/cxx_pluginxx_ui`）；
- `gen/*`、`dart/lib/src/gen/*`、`js/pluginxx_ui_kit.js`、生成的文档与 fixture **都提交入库**，
  日常开发不跑生成器；只有改 `schema/` 时才跑：

```bash
dart run tools/gen_ui.dart            # 重新生成
dart run tools/gen_ui.dart --check    # 提交前门禁：生成物与定义不一致时退出码 1
```

---

## 2. 客户端接入（渲染器）

### 2.1 声明能力段（第一步）

客户端**如实上报**自己能画什么。能力段既决定 `adapt()` 怎么降级，也是插件挑选组件的依据。

| 字段 | 说明 |
|---|---|
| `apiVersion` | 组件词汇版本（通常不用自己填） |
| `kind` | 渲染类型 `tui` / `gui`；**只用于粗判断**（"终端不给图片、不推着色器"），细判断一律用 `blocks` |
| `blocks` | 真正实现了的组件（少声明只会降级，多声明会画不出来） |
| `controls` | 真正实现了的控件形态（`buttons` / `select` / `checkbox` / `switch` / `text` / `number`） |
| `cell` | 只有格子模型的客户端才有：每个字符格相当于多少 u（默认 `{8, 20}`）；GUI 省略 = 1u 就是 1 逻辑像素 |
| `gap` | 本客户端的默认行距（`Gap.size` 缺省时用它，默认 12） |
| `icons` | 可选：认识的图标名清单（各客户端各自定义，插件据此选 `Icon.name`，不认识就用 `glyph`） |
| `percent` / `aspect` | 是否支持这两种尺寸形态（支持就照实写，不支持由 `adapt` 换掉） |
| `limits` | 解析与渲染上限（层级/数量/文本长度/表格行列…）；不填取库默认值 |

C++ 侧最省事的写法（musicxx 与 agentxx 都是这么做的）：

```cpp
pluginxx::ui::Capabilities caps = pluginxx::ui::fullCapabilities();  // 先取全集
caps.kind   = "tui";
caps.cell   = {8, 20};                                             // 终端才写
caps.blocks = {"Text", "Divider", /* … */};                        // 再按实际实现裁掉不支持的可选块
```

Dart 侧：

```dart
final PluginCapabilities caps = PluginCapabilities(
  kind: 'gui',
  blocks: ExternPluginUiCaps_c.blocks,
  controls: ExternPluginUiCaps_c.controls,
  icons: ExternPluginUiCaps_c.icons,
);
```

**纪律**：能力段里的每一项都要与渲染分支对得上。声明了却画不出来，插件就会拿到一份
"看起来支持"的能力，最终用户看到的是空白块。

### 2.2 发布能力段

内容由库生成（`capabilitiesToJson(caps)`），通道沿用各客户端既有机制：

| 客户端 | 通道 | 插件侧读法 |
|---|---|---|
| agentxx（TUI） | 客户端状态快照 `get_client_state()` 的 `ui` 段：由 `PluginUiAdapter::uiCapabilitiesJson()` 提供（TUI 适配器直接返回 `capabilitiesToJson(tuiUiCapabilities())`，与渲染前 `adaptItems` 用的是同一份能力，不会分叉） | `ClientPluginBase::uiCapabilities()` / `supportsBlock()` |
| musicxx（Flutter） | ① 宿主配置 `MusicxxPluginRuntimeConfig.uiCapabilities` → `musicxx.host.info().ui`；② 调用插件能力取页面时作为参数传（`{"view":"…","ui":{…}}`）；③ 管理页「调试」分页展示 | JS `musicxx.host.info().ui` / `musicxx.ui.support(name)`；原生 `host.get_info` |

能力段在客户端生命周期内不变，插件侧按实例缓存解析结果即可。

### 2.3 解析

```cpp
pluginxx::ui::ParseReport report;
auto doc = pluginxx::ui::parseDocument(json, limits, &report);   // 也接受 {"blocks":[…]} / {"items":[…]} / 裸数组
for (const auto& w : report.warnings) { log(w); }
```

解析不会让整份描述失效：未知组件（`known == false`，客户端显示 `fallback` 或跳过）、未知字段、
未知枚举值、超限内容都各自降级处理。**不要因为一条 warning 就把整页丢掉。**

### 2.4 适配

```cpp
pluginxx::ui::AdaptReport adaptReport;
auto renderable = pluginxx::ui::adaptDocument(doc, myCaps(), &adaptReport);
```

- 纯函数：同一输入 + 同一能力 → 同一输出；
- **保证收敛**：结果只包含 `caps.blocks` 里声明的组件，最多降到 `Text`（`Icon` → `glyph` 文本、
  `Image` → `alt` 文本、`Stack` → 最后一个子节点、`Sparkline`/`Diff`/`Diagram`/`Markdown` 不支持时
  降成等宽文本、尺寸形态不支持时换内容尺寸…）；
- 规则表在 `schema/ui.def.json` 的 `adapt` 段，由生成器产出（`gen/adapt_rules.g.h` /
  `gen/adapt_rules.g.dart`）。

**渲染层不要再写"我不支持谁"的分支**：那是两套实现，早晚与规则表分叉。渲染层只需要处理
"`caps.blocks` 里的组件"，其余情况在 `adapt` 那一步已经解决。

### 2.5 渲染要点

**尺寸**（`SizeValue` / `Edges`）

| 形态 | 客户端怎么做 |
|---|---|
| 数值（u，可小数） | GUI：1u = 1 设计像素，交给现有尺寸换算工具。终端：`caps.colsOf(u)` / `caps.rowsOf(u)` 换算成列/行（四舍五入；**留白换算成 0 就消失**；固定尺寸给正数时至少占 1 格） |
| `{"percent": n}` | 基准是**直接父容器本轮可分配的宽度**（已扣掉同级固定尺寸与间距）；高度基准是父容器可用高度，父容器高度无界时退化成内容尺寸 |
| `"auto"` / 省略 | 内容决定（文字长度、表格列内容、图标默认尺寸） |
| `Edges` | 一个字段（`padding` / `margin`）：数值 = 四边相同，`{horizontal, vertical}` = 两轴，`{left, top, …}` = 单边 |

**文本**：`TextValue` 是字符串或 `{key, fallback, args}`。按 `key` 查客户端词表 → 取不到用
`fallback` → 再取不到用 `key` 原文；`args` 做 `{n}` 命名占位替换。`type`（`body`/`caption`/`title`）
+ `bold` / `dim` / `mono` 映射到客户端自己的排版（终端没有字号，映射到主题色与加粗）。

**色调**：`tone` 是语义色（`normal`/`hint`/`accent`/`success`/`warning`/`error` 等），由客户端
主题解释，不要当成具体颜色值。

**终端额外注意**：`aspect` 只能按字符格的宽高比近似（`rows = ceil(cols × cell.width / (aspect × cell.height))`），
文档与插件指南都要写清这一点；`Table` 列宽自动分配 = 先量各列自然宽度，再把剩余空间按比例分给
未指定宽度的列（只剩一列未指定时它吃掉全部剩余）；总宽超出可用宽度时按比例压缩（终端可截断，不报错）。

**布局**：`Row`/`Column` 的 `main`（含 `spaceBetween`）与 `cross`、`Expanded`/`Spacer` 的 `flex`
是相对布局的主力，优先用它们，别用固定尺寸硬撑。

### 2.6 控件与动作

**库不提供"表单 + 提交"这一层**。控件只在**值变化时**立即派发自己的动作：

| 项 | 规定 |
|---|---|
| 动作 kind | `dispatch`（交回内容归属方，插件能力属于这一类；字符串短写等于它）/ `route`（跳转，可跳范围由客户端决定）/ `command`（客户端官方动作）/ `none` |
| 控件派发 | 值变化（勾选、输入完成、候选项点击）即派发：客户端把 `{"id":…,"value":…}` 合并进参数（插件自己写的 `args` 保留，冲突时以客户端补的为准） |
| 控件值类型 | `checkbox`/`switch` → 布尔；`text` → 字符串；`number` → 数值；`buttons`/`select` → 候选项 `value` 原值 |
| 控件状态 | 客户端维护（焦点、编辑中的文本、选中项、**本地覆盖值**），不属于描述；`value` 只在没有状态时作初值。**新视图到达时清空本地覆盖值**，否则插件改过配置后界面还显示旧值 |
| 校验 | 客户端做能立刻判断的校验（`number` 的 `min`/`max`/`step`、`select` 无候选项），失败在控件附近提示；插件自己仍要兜底 |
| 未知 `control` 形态 | 退化成只读展示（`label` + 当前值），不影响页面其余部分 |

需要"一组值一起提交"时，**由客户端域内实现**（收自己维护的控件状态 + 自定义提交动作 id），
不要指望描述层有提交语义。agentxx 的中断确认就是这么做的（`kInterruptSubmitActionId` = `"__submit"`，
客户端侧 `kFormSubmitActionId` 与之同源）。

### 2.7 排障与降级输出

- `lintWithCaps(items, caps)`：开发期检查（u 值不是格的整数倍、同一行里固定宽度与 flex 混用、
  `percent` 出现在高度无界的父容器里、表格列宽合计超出、`wrap:false` 与 `maxLines` 互相抵消）。
  在 debug 构建里调用并记日志即可，不参与渲染。
- `plainText*`：模型 → 纯文本，用于日志、CLI、FFI 输出与"画不出来时的兜底"。客户端把内容同时
  降级成纯文本后，排障时不用开图形界面也能看到插件给了什么。
- `ParseReport` / `AdaptReport` 的提示要落日志（`--debug` 或文件日志），它们是"插件为什么没显示"
  的第一手线索。

---

## 3. 宿主接入（转发方，不渲染）

宿主不需要理解组件：它只搬运 JSON。

- 把客户端的能力段原样放进宿主信息（例如 C ABI 配置结构体加一个字符串字段
  `ui_capabilities`），宿主只校验"是不是 JSON 对象"，不解析内容；
- 取内容时把能力段作为参数传给插件（`{"view":"…","ui":{…}}`），插件在生成内容的那一刻就能
  按目标挑选组件；
- **宿主不做适配、不读组件表**：内容由客户端解析与降级。宿主里再放一份组件清单只会多一处要同步；
- 改了 C ABI 结构体（加字段）后：重新生成 Dart 绑定（ffigen）、宿主与 Dart 侧一起更新
  （`struct_size` 会校验，混用新旧版本会直接报错）。

---

## 4. 插件作者接入

### 4.1 C++

```cpp
#include <pluginxx/ui.h>          // 模型 + 解析 + 适配 + 文本降级 + 构建器
#include <pluginxx/ui/kit.h>      // 基础 kit（生成的组件组合）

using namespace pluginxx::ui;
std::vector<Item> items;
items.push_back(build::title("系统"));
items.push_back(kit::progressRow({{"label", "CPU"}, {"value", 42}, {"total", 100}}, env));
items.push_back(build::button("刷新", Action::dispatch("refresh")));
```

- 构建器（`pluginxx::ui::build`）：`title` / `text` / `button` / `card` / `row` / `column` / `kv` /
  `progress` / `table` / `tree` / `control` …（见 `docs/kit.md` 与头文件）；
- 客户端扩展 kit：`<client>::ui::kit`（如 musicxx 的 `musicxx::ui::kit`、agentxx 的
  `agentxx::ui::kit`），提供本客户端常用组合与更贴合的默认留白；扩展 kit 是**自包含**的
  （合并了基础 kit 的全部组件），可以只包含它。

### 4.2 JS

```js
const kit = pluginxx.ui.kit;
const items = [
  kit.title({ text: '系统' }),
  kit.settingRow({ id: 'rate', title: '速率', value: '1×', action: 'setRate' }),
];
```

- `env`（第二个参数，可选）：能力摘要（`kind` / `blocks` / `cell` / `limits`）。传了它，kit 会挑
  更合适的变体（例如目标不支持 `Image` 时用文字行）；不传就是中立描述，由客户端 `adapt` 收口；
- 判断能力：`env.hasBlock('Table')`、`env.kind === 'tui'`（**不推荐**按 kind 写两套内容，
  优先按组件问）。

### 4.3 能力协商与 i18n

- 默认交给客户端适配（插件不用关心目标）；只有当"某个组件缺失时想要更好的排法"时才用 `env`
  或 `host.info().ui` 分支；
- 文案用 `TextValue`：插件自己的文案通常只有一种语言，直接给字符串；需要多语言时写
  `{key, fallback, args}`，客户端按自己的语言表解析。

### 4.4 纪律

- 只写一个数值单位 u（GUI 的 dp 口径）；终端会按自己的能力换算，别写"多少列"；
- 相对布局优先：能 `Expanded` 就不要固定宽度，能 `auto` 就不要写高度；
- 不认识的字段与组件会被忽略，不要把内容塞在兜底字段里指望客户端读。

---

## 5. 扩展 kit（各客户端自己）

基础 kit 在库里（`schema/kit.def.json`），**客户端自己的留白口径与常用组合放各自仓库**：

```bash
cd <本库>            # 生成器按相对路径读 schema/ui.def.json，必须在库根目录执行
dart run tools/gen_ui.dart --ext-kit <客户端 kit 定义> \
    --prefix <前缀> --namespace <C++ 命名空间> --targets cpp,js --out <客户端目录>
```

| 参数 | 说明 |
|---|---|
| `--ext-kit` | 扩展 kit 定义文件（`extends` 指向库的 `schema/kit.def.json`；同名组件覆盖基础 kit） |
| `--prefix` | 产物文件名前缀（`<前缀>_ui_kit.g.h` / `<前缀>_ui_kit.js` / `<前缀>_ui_kit.md`） |
| `--namespace` | C++ 命名空间（如 `musicxx::ui::kit`），只影响 C++；JS 统一写全局 `pluginxx.ui.kit` |
| `--targets` | `cpp,js`（Dart 侧由基础包提供 `KitRuntime` 与模板，不单独生成客户端 kit） |
| `--out` | 输出目录（生成器只往一个目录写，多目录时用脚本搬运，见两个项目的 `tools/gen_ui_kit.ps1`） |

三条纪律：**只写数值 u**（取 8 / 12 / 20 这类贴近格整数倍的值）、**不引用客户端专属块以外的库外概念**、
**只装配不含逻辑**。需要"目标不支持时的替代形态"就写变体：

```jsonc
"variants": [
  { "requires": ["Image"], "template": { "kind": "Image", "src": "$cover", "alt": "$title" } },
  { "template": { "kind": "Text", "text": "$title" } }        // 兜底变体（必须有无条件的那一个）
]
```

生成器会校验：枚举取值齐全、recipe 只引用已声明的组件与字段、尺寸取值非负、每个组件都有
无条件的兜底变体。**改 kit 后重新生成并把生成物一起提交**（kit 版本随插件冻结）。

JS 插件目录要带 kit 文件：有的项目用脚本同步（musicxx 的 `tools/sync_ui_kit.ps1` 把基础 + 扩展
kit 复制进示例插件目录）。

---

## 6. 演进流程（加组件 / 加字段 / 加枚举值）

1. 改 `schema/ui.def.json`（组件、字段、枚举、上限、适配规则、样例）或 `schema/kit.def.json`；
2. `dart run tools/gen_ui.dart` 重新生成 → 三份绑定 + 文档 + fixture；
3. 补 fixture（`fixtures/`）与用例：解析/往返、适配（完整能力 / 终端能力 / 最小能力）、纯文本；
   纯文本金文件按 README 用 `PLUGINXX_UI_WRITE_GOLDEN=1` 重生成；
4. 各客户端实现渲染分支 → 把新组件加进自己的能力段 → 重跑扩展 kit 生成；
5. `dart run tools/gen_ui.dart --check` 与三份绑定的测试全绿后提交；

规则：**只增不改**。新增组件与可选字段 = 老客户端忽略；语义变了就换新的组件名，
**不做别名**（一个概念只有一个名字）。`uiApiVersion` 随词汇变化抬高。

---

## 7. 常见问题

| 现象 | 原因 | 怎么查 |
|---|---|---|
| 插件页面空白 | 组件名/字段名不是规范写法，被当成未知块跳过 | `ParseReport.warnings`；`plainText` 打印同一份 JSON |
| 某个块画不出来，也没有提示 | 能力段声明了但渲染层没实现 | 对照 `caps.blocks` 与渲染层的分支；插件看不出问题，因为能力是客户端自己报的 |
| 卡片时挤时松 | u 值不是格的整数倍，终端取整后留白消失或撑开 | `lintWithCaps`；把值写成格大小的整数倍（默认 8 / 20） |
| 控件操作后界面没变化 | 控件没写 `action`，或写成了旧名（`capability` / `action`） | 动作只认 `dispatch` / `route` / `command` / `none`；字符串短写等于 `dispatch` |
| `percent` 宽度没效果 | 父容器在这一轴无界（例如自动高度的纵向容器） | 高度基准会退化成内容尺寸；改父容器的尺寸约束 |
| 终端里图片/着色器不见了 | 它们是可选级，`adapt` 按能力降级 | 插件侧用 `env.hasBlock('Image')` 之类挑替代结构 |
| JS 插件报 `pluginxx is not defined` | 清单没写 `scripts`（kit 随插件目录分发，宿主不预置） | 清单加 `scripts: [pluginxx_ui_kit.js, <client>_ui_kit.js, plugin.js]` |
| 扩展 kit 与基础 kit 同名组件 | 两边的命名空间/加载顺序 | C++：各在自己的命名空间，可同时包含；JS：后加载的覆盖同名的 |

---

## 8. 新增渲染器接入清单（GUI 客户端或第三端）

写一个新渲染器要做的只有四件事：**声明能力 → 解析 → 适配 → 渲染 + 接动作**。
描述层、适配规则、纯文本降级、基础 kit、夹具都可以直接复用，不需要改库。

### 8.1 必须实现（核心组件）

`Text` / `Divider` / `Gap` / `Button` / `Block` / `Row` / `Column` / `Expanded` / `Spacer` /
`SizedBox` / `Padding` / `Align` / `Collapse` / `KV` / `Table` / `Tree` / `Progress` / `Badge` /
`Control` / `Markdown`。

实现时的语义要点：

- `Row` / `Column`：`main`（`start`/`center`/`end`/`spaceBetween`）、`cross`
  （`start`/`center`/`end`/`stretch`）、`gap`（换算后的间距）；
- `Expanded` / `Spacer`：按 `flex` 分剩余空间（不能只按比例分整宽，否则与固定尺寸冲突）；
- `SizedBox`：`width`/`height` 是 `SizeValue`；`{percent:n}` 按直接父容器算；`aspect` 优先于单轴；
- `Padding` / `Block.padding` / `Block.margin`：`Edges` 的三种写法都要支持；
- `Collapse`：按 `id` 维护展开状态（客户端状态，不是描述的一部分）；
- `KV`：`keyWidth` 省略 / `auto` = 按最长键自适应，数值 = 固定，`{percent:n}` = 父宽比例；
- `Table`：列宽三态（省略/`auto` 自动分配、数值固定、`percent` 比例），超出可用宽度按比例压缩；
- `Progress`：`value`/`total`/`unit`/`showValue`/`thresholds`（按 `at` 抢 `tone`）；
- `Control`：见 §2.6 的派发与状态规则。

### 8.2 可选组件（不实现就靠 `adapt` 降级，**不要声明进能力段**）

`Icon`（GUI 用 `name`、终端用 `glyph`；两边都没有就跳过）、`Image`（取不到源用 `alt`）、
`Stack`、`Diff`、`Sparkline`、`Diagram`，以及各客户端的专属块（如 `musicxx.Shader`）。

### 8.3 动作与控件通道

- `dispatch` → 交回内容归属方（插件能力 / 页面刷新），客户端把 `{id, value}` 合并进参数；
- `route` → 跳转（可跳范围由客户端自己定，例如只允许跳到本客户端的外壳页或插件的自绘页）；
- `command` → 客户端官方动作；
- `none` → 不响应。

### 8.4 能力上报三处一致

1. 客户端信息（`host.info()` 的 `ui` 段 / 客户端状态快照）；
2. 调用插件取内容时作为参数传（`{"view":…,"ui":{…}}`）；
3. 客户端自己的调试页展示（排查"插件为什么没用某个组件"）。

三处内容都来自 `capabilitiesToJson(caps)`，不要各写一份。
