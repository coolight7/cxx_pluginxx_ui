// 降级适配（Dart 绑定）
import 'dart:convert';
import 'dart:io';

import 'package:pluginxx_ui/pluginxx_ui.dart';
import 'package:test/test.dart';

String get fixturesDir {
  for (final String candidate in <String>['../fixtures', 'fixtures']) {
    if (Directory(candidate).existsSync()) {
      return candidate;
    }
  }
  return '../fixtures';
}

List<ItemData> parseFixture(String name) =>
    parseBlocks(jsonDecode(File('$fixturesDir/$name').readAsStringSync()));

PluginCapabilities capsWithout(List<String> remove) {
  final PluginCapabilities caps = PluginCapabilities.full();
  return PluginCapabilities(
    kind: caps.kind,
    blocks: <String>[
      for (final String name in caps.blocks)
        if (!remove.any((String r) => r.toLowerCase() == name.toLowerCase())) name,
    ],
    controls: caps.controls,
    cell: caps.cell,
    gap: caps.gap,
    percent: caps.percent,
    aspect: caps.aspect,
    limits: caps.limits,
  );
}

void collectKinds(List<ItemData> items, List<String> out) {
  for (final ItemData item in items) {
    out.add(item.kind);
    collectKinds(item.children, out);
  }
}

void main() {
  test('完整能力下适配不改结构', () {
    final List<ItemData> items = parseFixture('core.json');
    final List<ItemData> out = adaptBlocks(items, PluginCapabilities.full());
    expect(out.length, items.length);
    final List<String> kinds = <String>[];
    collectKinds(out, kinds);
    for (final String kind in kinds) {
      expect(canonicalKind(kind), kind);
    }
  });

  test('最小能力全部收敛到文本', () {
    final List<ItemData> items = parseFixture('core.json');
    final AdaptReport report = AdaptReport();
    final List<ItemData> out = adaptBlocks(items, PluginCapabilities.minimal(), report: report);
    expect(out, isNotEmpty);
    for (final ItemData item in out) {
      expect(item.kind, 'Text');
      expect(item.children, isEmpty);
    }
  });

  test('终端能力下降级为文本', () {
    final PluginCapabilities caps =
        capsWithout(<String>['Image', 'Stack', 'Icon', 'Sparkline', 'musicxx.Shader']);
    final List<ItemData> out = adaptBlocks(parseFixture('gui_heavy.json'), caps);
    final List<String> kinds = <String>[];
    collectKinds(out, kinds);
    for (final String kind in kinds) {
      expect(caps.supportsBlock(kind), isTrue, reason: '只产出客户端支持的组件：$kind');
    }
    final List<ItemData> queue = <ItemData>[...out];
    bool hasAlt = false;
    while (queue.isNotEmpty) {
      final ItemData item = queue.removeLast();
      if (item.kind == 'Text' && item.text.fallback == '封面') {
        hasAlt = true;
      }
      queue.addAll(item.children);
    }
    expect(hasAlt, isTrue, reason: 'Image 退成 alt 文本');
  });

  test('容器不支持时展开子块', () {
    final PluginCapabilities caps = capsWithout(<String>['Block', 'Padding', 'Align', 'Collapse']);
    final List<ItemData> items = parseBlocks(<Object?>[
      <String, Object?>{
        'kind': 'Block',
        'title': '卡片',
        'children': <Object?>[
          <String, Object?>{'kind': 'Text', 'text': '内容'},
          <String, Object?>{'kind': 'Text', 'text': '第二行'},
        ],
      },
    ]);
    final List<ItemData> out = adaptBlocks(items, caps);
    expect(out.length, 3);
    expect(out[0].kind, 'Text');
    expect(out[0].text.fallback, '卡片');
    expect(out[1].text.fallback, '内容');
    expect(out[2].text.fallback, '第二行');
  });

  test('不支持的可选块退成纯文本', () {
    final PluginCapabilities caps =
        capsWithout(<String>['Sparkline', 'Diff', 'Diagram', 'Markdown']);
    final List<ItemData> items = parseBlocks(<Object?>[
      <String, Object?>{'kind': 'Sparkline', 'data': <double>[1, 2, 3], 'showLast': true},
      <String, Object?>{'kind': 'Markdown', 'text': '# 标题'},
    ]);
    final List<ItemData> out = adaptBlocks(items, caps);
    expect(out.length, 2);
    for (final ItemData item in out) {
      expect(item.kind, 'Text');
      expect(item.text.fallback, isNotEmpty);
    }
  });

  test('未知组件用兜底文本', () {
    final List<ItemData> items = parseBlocks(<Object?>[
      <String, Object?>{'kind': 'Whatever', 'fallback': '兜底文本'},
    ]);
    final List<ItemData> out = adaptBlocks(items, PluginCapabilities.full());
    expect(out.length, 1);
    expect(out[0].kind, 'Text');
    expect(out[0].text.fallback, '兜底文本');
    expect(out[0].tone, 'hint');
  });

  test('控件形态不支持时退成只读文本', () {
    final PluginCapabilities caps = PluginCapabilities.full()..controls = <String>['checkbox'];
    final List<ItemData> items = parseBlocks(<Object?>[
      <String, Object?>{
        'kind': 'Control',
        'control': 'select',
        'id': 'theme',
        'label': '主题',
        'value': 'dark',
        'options': <Object?>[
          <String, Object?>{'value': 'dark', 'label': '深色'},
        ],
      },
    ]);
    final AdaptReport report = AdaptReport();
    final List<ItemData> out = adaptBlocks(items, caps, report: report);
    expect(out.length, 1);
    expect(out[0].kind, 'Text');
    expect(out[0].text.fallback, '主题: 深色');
    expect(report.notes, isNotEmpty);
  });

  test('percent 与 aspect 不被支持时退回内容尺寸', () {
    final PluginCapabilities caps = PluginCapabilities.full()
      ..percent = false
      ..aspect = false;
    final List<ItemData> items = parseBlocks(<Object?>[
      <String, Object?>{
        'kind': 'SizedBox',
        'width': <String, Object?>{'percent': 50},
        'height': 40,
        'aspect': 1.5,
      },
    ]);
    final List<ItemData> out = adaptBlocks(items, caps);
    expect(out.length, 1);
    expect(out[0].width.isAuto, isTrue);
    expect(out[0].height.isValue, isTrue);
    expect(out[0].aspect, 0);
  });

  test('适配规则表与定义一致', () {
    expect(adaptRuleOf('Stack'), AdaptRule.lastChild);
    expect(adaptRuleOf('Image'), AdaptRule.altText);
    expect(adaptRuleOf('Block'), AdaptRule.flatten);
    expect(adaptRuleOf('Text'), AdaptRule.terminal);
    expect(kAdaptRules.length, kBlockTable.length);
  });
}
