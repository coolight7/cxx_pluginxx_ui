#pragma once

/// 插件界面描述层的**规范模型**（schema v1）
///
/// 本文件是描述层的数据模型：插件交一份界面 JSON，客户端把它解析成本文件的
/// [Document] / [Item]，再按自己的渲染器画出来。模型只描述"界面上有什么"，
/// 不含任何渲染概念（没有终端转义、没有像素精度要求、没有"必须悬停"这类交互）。
///
/// 三条约定：
/// - **不依赖任何第三方库**（只用标准库）：插件、宿主、终端渲染、GUI 渲染共用
///   同一份模型；JSON 解析在 parse.h（实现依赖 cxx_utilxx_base）。
/// - **JSON 片段按原文携带**：动作参数、控件值这类"任意 JSON"字段保存的是**紧凑
///   JSON 文本**（`argsJson` / `valueJson`），客户端需要结构化时自行再解析。这样
///   模型不引入 JSON 依赖，也不会因为"反序列化再序列化"改掉原值。
/// - **尺寸只有一个单位 u**（逻辑长度，允许小数）：GUI 1u = 1 逻辑像素，终端按
///   客户端的 `cell`（每个字符格相当于多少 u）换算成列/行，见 capabilities.h。
///
/// 组件全集与字段见生成的 docs/ui-schema.md（源：schema/ui.def.json）。
#include "pluginxx/ui/export.h"

#include <cstddef>
#include <cstdint>
#include <functional>
#include <string>
#include <string_view>
#include <vector>

namespace pluginxx {
namespace ui {

namespace detail {

/// 命名占位替换：把 `{n}` 换成 argsJson 里 `n` 对应的值（字符串形态）
PLUGINXX_UI_API std::string applyTextArgs(std::string_view text, std::string_view argsJson);

/// 枚举取值归一化：在表里忽略大小写查找，命中返回表里的规范写法，未命中返回空串
PLUGINXX_UI_API std::string_view
    enumNormalize(const std::string_view* values, std::size_t count, std::string_view v);

/// 枚举取值是否合法（忽略大小写）
PLUGINXX_UI_API bool
    enumContains(const std::string_view* values, std::size_t count, std::string_view v);

/// 数值格式化（两端一致的文本形态）：整数不带小数点，小数最多两位且去掉尾随 0
PLUGINXX_UI_API std::string formatNumber(double value);

/// 忽略大小写的相等比较（组件名与枚举值都按这个口径比较）
PLUGINXX_UI_API bool iequals(std::string_view a, std::string_view b);

} // namespace detail

// ===== 基本取值形态 =====

/// 尺寸取值：数值（u）/ `auto` / `{ "percent": n }`
struct SizeValue {
    enum class Mode : std::uint8_t {
        Value   = 0, ///< 数值（u）
        Auto    = 1, ///< 由内容决定
        Percent = 2, ///< 占直接父容器可分配空间的比例
    };

    Mode   mode  = Mode::Auto;
    double value = 0.0; ///< Mode::Value / Mode::Percent 时有意义

    bool isAuto() const {
        return mode == Mode::Auto;
    }

    bool isPercent() const {
        return mode == Mode::Percent;
    }

    bool isValue() const {
        return mode == Mode::Value;
    }

    static SizeValue of(const double v) {
        return SizeValue{Mode::Value, v};
    }

    static SizeValue autoValue() {
        return SizeValue{Mode::Auto, 0.0};
    }

    static SizeValue percent(const double p) {
        return SizeValue{Mode::Percent, p};
    }
};

/// 四边数值（内边距 / 外边距的统一写法）
struct Edges {
    double left   = 0.0;
    double top    = 0.0;
    double right  = 0.0;
    double bottom = 0.0;

    bool isZero() const {
        return left == 0.0 && top == 0.0 && right == 0.0 && bottom == 0.0;
    }

    static Edges all(const double v) {
        return Edges{v, v, v, v};
    }

    static Edges axis(const double horizontal, const double vertical) {
        return Edges{horizontal, vertical, horizontal, vertical};
    }
};

/// 文本取值：字面字符串，或 `{ "key": …, "fallback": …, "args": {…} }`
///
/// 客户端优先按 `key` 取自己的语言表，取不到用 `fallback`（再取不到用 key 原文）；
/// `argsJson` 是 `{n: 3}` 这类命名占位参数，用于替换文本里的 `{n}`。
struct TextValue {
    std::string key;      ///< 语言表键（可为空）
    std::string fallback; ///< 字面文本 / 缺键回退
    std::string argsJson; ///< 占位参数（紧凑 JSON 对象文本，可为空）

    bool empty() const {
        return key.empty() && fallback.empty();
    }

    bool hasKey() const {
        return !key.empty();
    }

    static TextValue of(std::string_view text) {
        TextValue v;
        v.fallback.assign(text);
        return v;
    }

    /// 解析成最终文本
    /// - `lookup` 非空时先按键取语言表；返回空串视为缺键
    /// - 缺键时用 `fallback`，`fallback` 也为空时用 key 原文
    /// - 最后按 `argsJson` 做 `{n}` 命名占位替换
    std::string resolve(const std::function<std::string(std::string_view)>& lookup = {}) const {
        std::string out;
        if (lookup && !key.empty()) {
            out = lookup(key);
        }
        if (out.empty()) {
            out = fallback.empty() ? key : fallback;
        }
        return argsJson.empty() ? out : detail::applyTextArgs(out, argsJson);
    }
};

// ===== 动作与控件 =====

/// 动作：`dispatch`（交回内容归属方处理）/ `route`（跳转）/ `command`（客户端官方动作）
struct Action {
    enum class Kind : std::uint8_t {
        None     = 0,
        Dispatch = 1,
        Route    = 2,
        Command  = 3,
    };

    Kind        kind = Kind::None;
    std::string name;     ///< dispatch / command 的动作名
    std::string route;    ///< route 的目标地址
    std::string argsJson; ///< 动作参数（紧凑 JSON 对象文本）

    bool empty() const {
        return kind == Kind::None;
    }
};

/// 控件候选项（`buttons` / `select`）
struct ControlOption {
    std::string valueJson; ///< 候选项的原值（紧凑 JSON 文本）
    TextValue   label;     ///< 显示标签
    std::string tone;      ///< 文本色（空 = 按控件样式）
};

/// 计量条阈值（达到该值起用对应语义色；客户端按由高到低匹配首个满足项）
struct Threshold {
    double      at = 0.0;
    std::string tone;
};

// ===== 结构化数据 =====

/// 表格列
struct TableColumn {
    TextValue   title;
    std::string align = "start"; ///< start / center / end
    SizeValue   width;           ///< 缺省 = 自动分配（按内容比例分剩余空间）
    std::string tone;
};

/// 表格单元格
struct TableCell {
    TextValue   text;
    std::string tone;
    Action      action;
};

/// 键值对
struct KeyValuePair {
    TextValue   key;
    TextValue   value;
    std::string kTone;
    std::string vTone;
};

/// 树节点
struct TreeNode {
    TextValue             label;
    std::string           tone;
    Action                action;
    std::vector<TreeNode> children;

    /// 展开后的节点总数（含自身）
    std::size_t count() const {
        std::size_t n = 1;
        for (const TreeNode& child : children) {
            n += child.count();
        }
        return n;
    }
};

// ===== 组件元信息（由 schema 生成，见 gen/blocks.g.h） =====

/// 组件级别
enum class BlockLevel : std::uint8_t {
    Core     = 0, ///< 两个渲染目标都必须实现
    Optional = 1, ///< 允许客户端不实现（按适配规则降级）
    Client   = 2, ///< 客户端专属（`<client>.<Name>`）
};

/// 适配规则（客户端不支持某个块时怎么降级）
enum class AdaptRule : std::uint8_t {
    Terminal      = 0, ///< 收敛终点（Text）
    PlainTextMono = 1, ///< 该节点的纯文本，包成 Text(mono=true)
    Flatten       = 2, ///< 展开子节点
    Skip          = 3, ///< 跳过
    LastChild     = 4, ///< 保留最后一个子节点
    GlyphText     = 5, ///< Text(glyph)（无 glyph 则跳过）
    AltText       = 6, ///< Text(alt)（无 alt 则跳过）
};

/// 组件的元信息
struct BlockMeta {
    std::string_view kind;
    BlockLevel       level;
    std::string_view client; ///< 客户端专属组件的归属（其余为空）
    AdaptRule        rule;
    std::string_view doc;
};

// ===== 组件项 =====

/// 一个组件项
///
/// 各组件只使用与自己相关的字段（用不到的字段保持缺省值）；字段含义见生成的
/// docs/ui-schema.md。JSON 片段（`argsJson` / `valueJson`）保存紧凑 JSON 文本。
struct Item {
    /// 组件类型（规范名，如 `Text`；解析时忽略大小写）
    std::string kind;
    /// 组件标识（控件必填；其它组件可选，用于状态保持与诊断）
    std::string id;
    /// 解析结果是否被识别（false = 未知 kind / 解析失败 → 走 `fallback`）
    bool known = true;

    // ---- 文本与排版 ----
    TextValue   text;               ///< Text.text
    std::string textType = "body";  ///< body / caption / title
    std::string tone     = "normal";
    bool        bold     = false;
    bool        dim      = false;
    bool        mono     = false;
    bool        wrap     = true;
    int         maxLines = 0;       ///< 0 = 不限制
    std::string align    = "start"; ///< start / center / end（Align 用 start/center/end/stretch）
    std::string vertical = "center";///< Align.vertical
    std::string main     = "start"; ///< Row/Column.main（含 spaceBetween）
    std::string cross    = "start"; ///< Row/Column.cross

    // ---- 尺寸与留白 ----
    SizeValue   size;             ///< Gap.size / Icon.size
    SizeValue   width;            ///< SizedBox.width / Image.width / Progress.width
    SizeValue   height;           ///< SizedBox.height / Image.height
    SizeValue   keyWidth;         ///< KV.keyWidth（Auto = 按最长键自适应）
    double      aspect = 0.0;     ///< >0 = 纵横比（宽/高）
    double      radius = 0.0;     ///< 圆角（Image）
    double      blur = 0.0;       ///< 模糊强度（Image.blur，sigma，逻辑像素；0 = 不模糊）
    double      opacity = 1.0;    ///< 不透明度（Image.opacity，0~1）
    std::string fit;              ///< Image.fit（contain/cover/…）
    int         flex = 1;         ///< Expanded.flex / Spacer.flex（≥1）

    bool      hasGap     = false; ///< Row/Column.gap 是否给出
    SizeValue gap;
    bool      hasPadding = false;
    Edges     padding;
    bool      hasMargin  = false;
    Edges     margin;

    std::vector<Item> children;

    // ---- 按钮 / 图标 ----
    TextValue   label;   ///< Button.label
    std::string variant; ///< Button.variant / Block.variant
    std::string icon;    ///< Button.icon / Icon.name（客户端图标名）
    std::string glyph;   ///< Icon.glyph（文本替代字符）
    bool        disabled = false;

    // ---- 内容块 / 折叠 ----
    TextValue title;           ///< Block.title / Collapse.title
    bool      expanded = true; ///< Collapse.expanded

    // ---- 键值 / 表格 / 树 ----
    std::vector<KeyValuePair>           pairs;
    std::string                         sep = " : ";
    bool                                header = true;
    std::vector<TableColumn>            columns;
    std::vector<std::vector<TableCell>> rows;
    bool                                connector = true;
    std::vector<TreeNode>               nodes;

    // ---- 进度 / 趋势 ----
    double                   value      = 0.0;
    double                   total      = 100.0;
    std::string              unit;             ///< 数值单位（如 `%`）
    bool                     showValue  = true;
    std::vector<Threshold>   thresholds;
    std::vector<double>      data;             ///< Sparkline 数据点
    int                      glyphHeight = 1;  ///< Sparkline 图形高度（行）
    std::string              glyphStyle = "block"; ///< block / bar
    bool                     showLast   = true;
    std::vector<std::string> colors;           ///< 按值分档的语义色（空 = 单色）

    // ---- 控件 ----
    std::string                control; ///< buttons / select / checkbox / switch / text / number
    TextValue                  help;
    std::vector<ControlOption> options;
    std::string                valueJson; ///< 初始值（紧凑 JSON 文本）
    bool                       integer   = false;
    bool                       multiline = false;

    // 数值型字段的上下限（Control.min/max/step 与 Sparkline.min/max 共用）
    bool   hasMin   = false;
    double minValue = 0.0;
    bool   hasMax   = false;
    double maxValue = 0.0;
    bool   hasStep  = false;
    double step     = 0.0;

    // ---- Markdown / Diff / Diagram ----
    std::string markdown; ///< Markdown.text（markdown 源码）
    std::string path;     ///< Diff.path
    std::string oldStr;   ///< Diff.oldStr
    std::string newStr;   ///< Diff.newStr
    std::string mermaid;  ///< Diagram.mermaid

    // ---- 图片 ----
    std::string source; ///< Image.source（惯例 cover/file/asset/url，不做限制）
    std::string src;    ///< Image.src
    TextValue   alt;    ///< 取不到图时的替代文本

    // ---- 客户端专属块：musicxx.Shader ----
    std::string bundle;
    std::string shaderArgsJson;
    double      speed           = 1.0;
    int         maxFps          = 0;
    bool        animate         = true;
    double      resolutionScale = 1.0;

    // ---- 动作与兜底 ----
    Action      action;   ///< 点击动作（可点组件）
    std::string fallback; ///< 客户端不认识这个块时显示的文本

    /// 是否含可交互内容（控件 / 带动作的可点组件）
    bool interactive() const {
        return kind == "Control" || !action.empty();
    }
};

/// 一份界面内容：可选包装 + 块数组
struct Document {
    TextValue         title;
    TextValue         subtitle;
    std::vector<Item> blocks;

    bool empty() const {
        return blocks.empty() && title.empty() && subtitle.empty();
    }
};

} // namespace ui
} // namespace pluginxx
