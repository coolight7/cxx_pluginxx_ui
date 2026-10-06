#pragma once

/// kit 运行时：把 kit 模板 + 参数展开成组件项
///
/// 模板表由生成器产出（gen/kit.g.h 与客户端的扩展 kit 头文件），本文件只实现
/// 展开规则。三份绑定（C++/Dart/JS）语义一致：
///
/// | 写法 | 含义 |
/// |---|---|
/// | `"$name"` | 整值替换：字段/元素换成该参数的值（缺省或空 → 字段省略、元素跳过） |
/// | `"${name}"` | 字符串插值：把参数值（字符串/数值/布尔）拼进字面文本 |
/// | `{"$require": "name", …}` | 该参数缺省或为空时**整个节点跳过** |
/// | `{"$map": "name", "wrap": {…"$item"…}}` | 把列表参数逐项展开（`$item` 是当前项） |
///
/// 组件变体：`variants` 里**第一个**`requires` 全部被 `env` 支持的变体生效；
/// 没有 `env`（= 目标未知）时用第一个无条件变体（不存在则用第一个变体）。
#include "pluginxx/ui/capabilities.h"
#include "pluginxx/ui/item.h"

#include <utilxx_base/json.h>

#include <string_view>

namespace pluginxx {
namespace ui {

/// 本库内使用 utilxx_base::Json 的短名（生成物与客户端代码都直接写 `Json`）
using utilxx_base::Json;

namespace detail {

/// 模板查询（生成的 kit 头文件传入自己的表）
using KitTemplateLookup = utilxx_base::Json (*)(std::string_view name);

/// 展开 kit 组件
/// - `params` 是参数对象（键 = 参数名；缺的参数用模板里的默认值）
/// - `env` 为空 = 目标未知（产出中立描述，由客户端的 adapt() 决定最终形态）
/// - 组件名未知时返回 kind 为空的项
PLUGINXX_UI_API Item
    expandKit(std::string_view name, const utilxx_base::Json& params, const Capabilities* env,
              KitTemplateLookup lookup);

/// 展开 kit 模板（不含参数默认值填充；`values` 即已合并的参数）
PLUGINXX_UI_API utilxx_base::Json expandKitTemplate(
    const utilxx_base::Json& templateNode,
    const utilxx_base::Json& values,
    const Capabilities*      env
);

} // namespace detail
} // namespace ui
} // namespace pluginxx
