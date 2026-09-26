/// `pluginxx_ui`：插件界面描述层（与渲染器无关）的 Dart 绑定
///
/// 与 C++ 绑定（`cxx_pluginxx_ui`）一一对应，两端共享 `schema/` 定义与 `fixtures/`：
/// - [ItemData] / [UiDocument]：规范模型
/// - [PluginCapabilities] / [Limits]：客户端能力与上限
/// - [parseDocument] / [parseBlocks] / [parseBlock]：JSON → 模型（校验 + 上限 + 提示）
/// - [adaptDocument] / [adaptBlocks] / [adaptItem]：模型 + 能力 → 客户端可渲染的模型
/// - [plainText] / [plainTextItem] / [plainTextDocument]：模型 → 纯文本（日志 / 降级）
/// - [KitRuntime]：kit 模板展开（具体 kit 组件见 `gen/kit.g.dart`）
///
/// 用法（客户端渲染层）：
/// ```dart
/// final UiDocument doc = parseDocument(jsonFromPlugin);
/// final UiDocument renderable = adaptDocument(doc, myCapabilities);
/// for (final ItemData block in renderable.blocks) {
///   // 按 block.kind 渲染：适配后只会出现 myCapabilities 声明支持的组件
/// }
/// ```
library pluginxx_ui;

export 'src/adapt.dart';
export 'src/capabilities.dart';
export 'src/gen/adapt_rules.g.dart';
export 'src/gen/blocks.g.dart';
export 'src/gen/kit.g.dart';
export 'src/kit_runtime.dart';
export 'src/model.dart';
export 'src/parse.dart';
export 'src/plain_text.dart';
