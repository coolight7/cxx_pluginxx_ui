# cxx_pluginxx_ui

插件界面**描述层**（与渲染器无关）：插件不写界面代码，只交一份 JSON 声明，客户端负责画。

同一份描述经 `adapt(caps)` 之后，既能渲染到**终端**（字符列/行），也能渲染到**图形界面**
（逻辑像素）—— 差异全部由客户端的**能力段**（`kind` / `blocks` / `cell` / `limits` …）吸收，
库本身不含任何"if 终端"这类判断。

```
插件 JSON ──parse──► 规范模型 ──adapt(caps)──► 客户端可渲染的模型 ──► 客户端渲染
                        │
                        └── 校验上限与未知项（截断 / fallback / 提示）
```

## 目录

```text
include/pluginxx/ui/
  item.h            规范模型（组件项、尺寸、文本、动作；**只用标准库**）
  capabilities.h    客户端能力与上限
  parse.h           JSON → 模型（校验 + 上限 + 提示）
  adapt.h           模型 + 能力 → 客户端可渲染的模型（降级规则）
  plain_text.h      模型 → 纯文本（日志 / CLI / 降级）
  display_width.h   显示列宽口径（CJK=2 列）
  build.h           构建器（header-only）
  kit_runtime.h     kit 模板展开（具体组件见生成的 gen/kit.g.h）
  lint.h            开发期检查
  gen/              生成物：组件表 / 枚举 / 默认值 / 适配规则 / 基础 kit
src/                parse / adapt / plain_text / kit_runtime / lint 的实现
schema/             **唯一组件定义**（ui.def.json + kit.def.json）
tools/gen_ui.dart   生成器（生成三份绑定 + 文档 + fixture）
dart/               Dart 包 `pluginxx_ui`（模型 / 解析 / 适配 / 文本降级 / kit）
js/pluginxx_ui_kit.js  基础 kit（JS 插件随插件目录分发这一份）
fixtures/           共享夹具（两端解析/降级/纯文本测试共用）
docs/               生成文档（ui-schema.md / kit.md）
tests/              C++ 单元测试
```

## 三份绑定与一处定义

| 绑定 | 内容 | 谁用 | 依赖 |
|---|---|---|---|
| C++ | 模型 + 解析 + 适配 + 文本降级 + 构建器 + 生成的常量与 kit | 宿主与动态库插件 | 头文件零依赖；实现依赖 `cxx_utilxx_base`（JSON） |
| Dart | 模型 + 解析 + 适配 + 文本降级 + 生成的常量与 kit | Flutter 渲染层 | 纯 Dart（无三方依赖） |
| JS | 生成的基础 kit（构建器 + recipe 展开） | JS 插件 | 无 |

三份绑定的**语义一致**由同一套夹具与测试约束：解析/往返、适配（完整 / 终端 / 最小能力）、
尺寸换算、纯文本（`fixtures/plaintext.golden.json` 逐字节比对）、kit 展开。

## 关键约定

- **尺寸只有一个单位 u**（允许小数）：GUI 1u = 1 逻辑像素；终端按客户端上报的 `cell`
  （每个字符格相当于多少 u）换算成列/行（四舍五入；留白允许换算成 0；固定尺寸至少 1 格）。
  另有 `{ "percent": n }`（基准 = 直接父容器可分配空间）与 `"auto"`（内容决定）。
  数值不允许为负（解析时负数按 0 处理并记一条提示）。
- **文本用 `TextValue`**：字符串，或 `{ key, fallback, args }`；客户端按自己的语言表取 `key`，
  取不到用 `fallback`，`args` 做 `{n}` 命名占位替换。
- **动作**：`dispatch`（字符串短写）/ `route` / `command` / `none`；控件只在**值变化时**派发，
  客户端把 `{id, value}` 合并进参数；库**不提供**表单提交层。
- **降级适配保证收敛**：适配结果只包含客户端声明支持的组件，最多降到 `Text`。
  规则表在 `schema/ui.def.json` 的 `adapt` 段，由生成器产出，客户端不要再写一套判断。
- **未知不致命**：未知组件走 `fallback` 或跳过；未知字段忽略；未知枚举值取默认值；超限截断。

组件全集、字段与适配规则见生成的 [`docs/ui-schema.md`](docs/ui-schema.md)，基础 kit 见
[`docs/kit.md`](docs/kit.md)。

## 构建与测试

```bash
# 生成物与定义一致（改 schema 后先跑生成，再提交生成物）
dart run tools/gen_ui.dart --check
dart run tools/gen_ui.dart                 # 重新生成全部产物

# C++（独立构建；依赖 cxx_utilxx_base / fmt 由 CMake 找）
cmake -G Ninja -S . -B build -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PREFIX_PATH=<依赖安装前缀> -DXX_EXEC_INSTALL_PREFIX=build/install
cmake --build build --parallel && ./build/cxx_pluginxx_ui_tests

# Dart
cd dart && dart test

# JS kit 自检（与 C++/Dart 的 kit 测试同一组期望）
node tools/kit_js_test.js
```

纯文本金文件（`fixtures/plaintext.golden.json`）由 C++ 侧生成：口径调整后跑一次
`PLUGINXX_UI_WRITE_GOLDEN=1 <测试可执行文件>` 并提交新文件，Dart 侧会自动比对。

## 扩展 kit（各客户端自己）

扩展 kit 在各自仓库里写一个 `extends` 定义（引用本库的 `schema/ui.def.json` 与
`schema/kit.def.json`），由**同一个生成器**产出，可覆盖基础 kit 的同名组件：

```bash
cd <本库>
dart run tools/gen_ui.dart --ext-kit <客户端 kit 定义> \
    --prefix <名字前缀> --namespace <C++ 命名空间> --targets cpp,js --out <客户端目录>
```

产出 `<前缀>_ui_kit.g.h` / `<前缀>_ui_kit.js` / `<前缀>_ui_kit.md`（合并了基础 kit 的全部组件，
自包含，不引用基础 kit 头文件）。

- C++ 产物按 `--namespace` 落在自己的命名空间里（默认 `pluginxx::ui::kit`）。因此**基础 kit 与
  扩展 kit 可以同时包含**：同名组件各在自己的命名空间，不会重复定义；扩展 kit 里的名字都是
  全限定写法，放在任何命名空间深度都能编译。
- JS 产物写的是同一个全局 `pluginxx.ui.kit`（内容是合并后的超集）：先加载基础 kit 再加载扩展 kit
  时，扩展 kit 的同名组件覆盖基础 kit 的。只加载扩展 kit 也够用（它自带全部基础组件）。
- 生成前会校验合并后的组件表：扩展 kit 里的 `params`/`variants` 只引用已声明的参数与组件，
  尺寸取值非负，且每个组件都有无条件的兜底变体。

## 接入位置

| 项目 | 接入 | 说明 |
|---|---|---|
| agentxx | `agent/third_party/cxx_pluginxx_ui` | TUI 渲染器消费适配后的模型；将来 GUI 客户端复用同一份描述层 |
| mymusic | `package_extend/musicxx_extern_plugin/src/third_party/cxx_pluginxx_ui` | Flutter 渲染层用 Dart 绑定；宿主与插件用 C++ 绑定；JS 插件用生成的 kit |

## 版本

| 版本 | 何时变 |
|---|---|
| `schemaVersion` | 定义文件结构变化（字段 / 组件结构） |
| `uiApiVersion` | 组件词汇变化（新增 kind / 可选字段 / 枚举值），**只增不改** |
| kit 版本 | kit recipe 变化（各版本冻结在插件里） |
