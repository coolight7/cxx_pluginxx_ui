// 降级适配：规范模型 + 客户端能力 → 客户端能渲染的模型（Dart 绑定）
//
// 规则表来自生成的 adapt_rules.g.dart（源：schema/ui.def.json 的 adapt 段）；
// 保证适配结果只包含客户端声明支持的组件，最多降到 Text。
import 'capabilities.dart';
import 'gen/adapt_rules.g.dart';
import 'model.dart';
import 'plain_text.dart';

/// 适配过程中的说明（客户端记日志）
class AdaptReport {
  final List<String> notes = <String>[];

  void note(String message) => notes.add(message);
}

const int _maxAdaptDepth = 16;

String _clampBytes(String text, int maxBytes) {
  if (maxBytes <= 0 || text.length <= maxBytes) {
    return text;
  }
  int cut = maxBytes;
  if (cut > 0 && cut < text.length) {
    final int unit = text.codeUnitAt(cut);
    if (unit >= 0xDC00 && unit <= 0xDFFF) {
      cut -= 1;
    }
  }
  return text.substring(0, cut);
}

ItemData _makeText(String text, {bool mono = false, String textType = 'body', String tone = 'normal', UiAction? action}) {
  final ItemData item = ItemData(kind: 'Text');
  item.text = TextValue.of(text);
  item.mono = mono;
  item.textType = textType;
  item.tone = tone;
  item.action = action;
  return item;
}

/// 能力相关的取值调整：percent 不支持 → 内容尺寸；aspect 不支持 → 忽略比例
ItemData _applyCapabilityAdjust(ItemData item, PluginCapabilities caps) {
  if (!caps.percent) {
    if (item.size.isPercent) {
      item.size = SizeValue.autoValue;
    }
    if (item.width.isPercent) {
      item.width = SizeValue.autoValue;
    }
    if (item.height.isPercent) {
      item.height = SizeValue.autoValue;
    }
    if (item.keyWidth.isPercent) {
      item.keyWidth = SizeValue.autoValue;
    }
    if (item.gap.isPercent) {
      item.gap = SizeValue.autoValue;
    }
  }
  if (!caps.aspect) {
    item.aspect = 0;
  }
  return item;
}



ItemData _degradeToText(ItemData source, String text,
        {bool mono = false, String textType = 'body', String tone = 'normal'}) =>
    _makeText(text, mono: mono, textType: textType, tone: tone, action: source.action);

List<ItemData> _adaptList(
  List<ItemData> items,
  PluginCapabilities caps,
  AdaptReport? report,
  int depth,
) {
  final List<ItemData> out = <ItemData>[];
  for (final ItemData item in items) {
    out.addAll(_adaptItem(item, caps, report, depth));
  }
  return out;
}

List<ItemData> _adaptItem(
  ItemData item,
  PluginCapabilities caps,
  AdaptReport? report,
  int depth,
) {
  final List<ItemData> out = <ItemData>[];
  if (depth > _maxAdaptDepth) {
    report?.note('降级层数超过上限，`${item.kind}` 被丢弃');
    return out;
  }

  // 未识别的组件：有 fallback 就显示它，否则跳过
  if (!item.known) {
    if (item.fallback.isNotEmpty) {
      out.add(_degradeToText(item, item.fallback, textType: 'caption', tone: 'hint'));
    } else {
      report?.note('跳过未识别的组件（没有 fallback）');
    }
    return out;
  }

  if (caps.supportsBlock(item.kind)) {
    final ItemData node = _applyCapabilityAdjust(item.clone(), caps);

    // 控件的这个形态不认识 → 退成只读展示（与纯文本形态一致）
    if (node.kind == 'Control' && !caps.supportsControl(node.control)) {
      report?.note('控件形态 `${node.control}` 不受支持，退成只读文本');
      final String text = plainTextItem(node);
      if (text.isNotEmpty) {
        out.add(_degradeToText(node, text));
      }
      return out;
    }

    // 子块：层级与数量上限按客户端能力截断
    if (node.children.isNotEmpty) {
      if (depth >= caps.limits.maxDepth) {
        report?.note('${node.kind} 的层级超过上限 ${caps.limits.maxDepth}，子块被丢弃');
        node.children = <ItemData>[];
      } else {
        if (node.children.length > caps.limits.maxItems) {
          report?.note('${node.kind} 的子块超过上限 ${caps.limits.maxItems}，已截断');
          node.children = node.children.sublist(0, caps.limits.maxItems);
        }
        node.children = _adaptList(node.children, caps, report, depth + 1);
      }
    }

    if (node.text.fallback.isNotEmpty) {
      node.text = TextValue(
        key: node.text.key,
        fallback: _clampBytes(node.text.fallback, caps.limits.maxTextBytes),
        args: node.text.args,
      );
    }
    if (node.data.length > caps.limits.maxDataPoints) {
      node.data = node.data.sublist(0, caps.limits.maxDataPoints);
    }
    out.add(node);
    return out;
  }

  switch (kAdaptRules[item.kind] ?? AdaptRule.terminal) {
    case AdaptRule.terminal:
      // 收敛终点：即使能力表里没写也保留
      out.add(item);
      return out;
    case AdaptRule.flatten:
      report?.note('展开 ${item.kind}（客户端不支持该容器）');
      if (item.title.isNotEmpty) {
        out.add(_degradeToText(item, item.title.resolve(), textType: 'title'));
      } else if (item.text.isNotEmpty && item.kind != 'Block') {
        final String text = item.text.resolve();
        if (text.isNotEmpty) {
          out.add(_degradeToText(item, text, mono: item.mono));
        }
      }
      for (final ItemData child in item.children) {
        out.addAll(_adaptItem(child, caps, report, depth + 1));
      }
      return out;
    case AdaptRule.lastChild:
      report?.note('${item.kind} 不支持，保留最后一个子块');
      if (item.children.isNotEmpty) {
        return _adaptItem(item.children.last, caps, report, depth + 1);
      }
      return out;
    case AdaptRule.glyphText:
      final String text = item.glyph.isNotEmpty ? item.glyph : item.icon;
      if (text.isNotEmpty) {
        out.add(_degradeToText(item, text, mono: true, tone: item.tone));
      } else if (item.fallback.isNotEmpty) {
        out.add(_degradeToText(item, item.fallback, textType: 'caption', tone: 'hint'));
      } else {
        report?.note('${item.kind} 不支持且没有 glyph/name，跳过');
      }
      return out;
    case AdaptRule.altText:
      final String text = item.alt.resolve();
      if (text.isNotEmpty) {
        out.add(_degradeToText(item, text, tone: item.tone));
      } else if (item.fallback.isNotEmpty) {
        out.add(_degradeToText(item, item.fallback, textType: 'caption', tone: 'hint'));
      } else {
        report?.note('${item.kind} 不支持且没有 alt，跳过');
      }
      return out;
    case AdaptRule.skip:
    case AdaptRule.plainTextMono:
      String text = item.fallback;
      text = text.isEmpty ? plainTextItem(item) : text;
      if (text.isNotEmpty) {
        report?.note('${item.kind} 不支持，退成文本');
        out.add(_degradeToText(item, text, mono: true, tone: item.tone));
      } else {
        report?.note('${item.kind} 不支持且没有可显示的文本，跳过');
      }
      return out;
  }
}

/// 某组件在当前能力下的适配规则（未声明返回 [AdaptRule.terminal]）
AdaptRule adaptRuleOf(String kind) => kAdaptRules[kind] ?? AdaptRule.terminal;

/// 适配一组块（展开型降级可能让一个块变成多个）
List<ItemData> adaptBlocks(
  List<ItemData> items,
  PluginCapabilities caps, {
  AdaptReport? report,
}) =>
    _adaptList(items, caps, report, 0);

/// 适配单个块（返回 0..N 个块）
List<ItemData> adaptItem(
  ItemData item,
  PluginCapabilities caps, {
  AdaptReport? report,
}) =>
    _adaptItem(item, caps, report, 0);

/// 适配整份内容（标题/副标题保留，块逐个适配）
UiDocument adaptDocument(
  UiDocument doc,
  PluginCapabilities caps, {
  AdaptReport? report,
}) {
  final UiDocument out = UiDocument(title: doc.title, subtitle: doc.subtitle);
  out.blocks = _adaptList(doc.blocks, caps, report, 0);
  return out;
}
