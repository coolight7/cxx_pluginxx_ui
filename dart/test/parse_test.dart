// 解析 / 往返 / 上限（Dart 绑定）
import 'dart:convert';
import 'dart:io';

import 'package:pluginxx_ui/pluginxx_ui.dart';
import 'package:test/test.dart';

String readFixture(String name) => File('$fixturesDir/$name').readAsStringSync();

/// 夹具目录：从测试工作目录（dart/）往上找仓库根的 fixtures/
String get fixturesDir {
  for (final String candidate in <String>['../fixtures', 'fixtures']) {
    if (Directory(candidate).existsSync()) {
      return candidate;
    }
  }
  return '../fixtures';
}

Object? readFixtureJson(String name) => jsonDecode(readFixture(name));

void main() {
  test('样例夹具里的组件全部被识别', () {
    final ParseReport report = ParseReport();
    final UiDocument doc = parseDocument(readFixtureJson('schema_samples.json'), report: report);
    expect(doc.blocks.length, kBlockTable.length);
    for (final ItemData item in doc.blocks) {
      expect(item.known, isTrue, reason: '样例组件被识别：${item.kind}');
    }
  });

  test('组件名忽略大小写', () {
    final ItemData item = parseBlock(<String, Object?>{'kind': 'TEXT', 'text': '大小写'});
    expect(item.kind, 'Text');
    expect(item.text.fallback, '大小写');
  });

  test('未知组件保留兜底文本', () {
    final ItemData item =
        parseBlock(<String, Object?>{'kind': 'Whatever', 'fallback': '兜底'});
    expect(item.known, isFalse);
    expect(item.fallback, '兜底');
  });

  test('负尺寸按 0 处理并记提示', () {
    final ParseReport report = ParseReport();
    final ItemData item = parseBlock(
      <String, Object?>{'kind': 'SizedBox', 'width': -10},
      report: report,
    );
    expect(item.width.isValue, isTrue);
    expect(item.width.value, 0);
    expect(report.warnings, isNotEmpty);
  });

  test('尺寸的三种形态', () {
    expect(parseBlock(<String, Object?>{'kind': 'Gap', 'size': 12}).size.value, 12);
    expect(parseBlock(<String, Object?>{'kind': 'Gap', 'size': 'auto'}).size.isAuto, isTrue);
    final ItemData percent =
        parseBlock(<String, Object?>{'kind': 'Gap', 'size': <String, Object?>{'percent': 40}});
    expect(percent.size.isPercent, isTrue);
    expect(percent.size.value, 40);
    expect(parseBlock(<String, Object?>{'kind': 'Gap'}).size.isAuto, isTrue);
  });

  test('文本取值支持键与命名占位', () {
    final ItemData item = parseBlock(<String, Object?>{
      'kind': 'Text',
      'text': <String, Object?>{
        'key': 'demo.total',
        'fallback': '共 {n} 项',
        'args': <String, Object?>{'n': 3},
      },
    });
    expect(item.text.key, 'demo.total');
    expect(item.text.resolve(), '共 3 项');
    expect(item.text.resolve(lookup: (String key) => 'total {n}'), 'total 3');
  });

  test('动作的四种形态', () {
    UiAction? actionOf(Object? value) => parseBlock(<String, Object?>{
          'kind': 'Button',
          'label': 'x',
          'action': value,
        }).action;

    final UiAction? shortForm = actionOf('openSettings');
    expect(shortForm?.kind, ActionKind.dispatch);
    expect(shortForm?.name, 'openSettings');

    final UiAction? route = actionOf(<String, Object?>{
      'kind': 'route',
      'route': 'ext://demo/settings',
    });
    expect(route?.kind, ActionKind.route);
    expect(route?.route, 'ext://demo/settings');

    final UiAction? command = actionOf(<String, Object?>{
      'kind': 'command',
      'name': 'musicxx.player.play',
      'args': <String, Object?>{'x': 1},
    });
    expect(command?.kind, ActionKind.command);
    expect(command?.args, <String, Object?>{'x': 1});

    expect(actionOf(<String, Object?>{'kind': 'none'}), isNull);
  });

  test('动作解析器可直接用（块字段与客户端扩展点共用）', () {
    expect(parseAction('openSettings')?.kind, ActionKind.dispatch);
    expect(parseAction('openSettings')?.name, 'openSettings');
    expect(
      parseAction(<String, Object?>{'kind': 'ROUTE', 'route': 'ext://demo/card'})?.route,
      'ext://demo/card',
    );
    expect(parseAction(<String, Object?>{'kind': 'none'}), isNull);
    expect(parseAction(<String, Object?>{'kind': 'unknown-kind'}), isNull);
    expect(parseAction(null), isNull);
    expect(parseAction(3), isNull);
  });

  test('解析与序列化往返稳定', () {
    final Object? first = readFixtureJson('core.json');
    final Object firstDump = dumpDocument(parseDocument(first));
    final Object secondDump = dumpDocument(parseDocument(firstDump));
    expect(jsonEncode(secondDump), jsonEncode(firstDump));
  });

  test('不再按数量/层级上限截断（限制已移除）', () {
    final List<Object?> array = <Object?>[
      for (int i = 0; i < 600; i++) <String, Object?>{'kind': 'Text', 'text': 'x'},
    ];
    final ParseReport report = ParseReport();
    final List<ItemData> items = parseBlocks(array, report: report);
    expect(items.length, 600);
    expect(report.truncated, isFalse);

    // 深层嵌套同样完整保留
    Object? deep = <String, Object?>{'kind': 'Text', 'text': '最深处'};
    for (int i = 0; i < 20; i++) {
      deep = <String, Object?>{
        'kind': 'Column',
        'children': <Object?>[deep],
      };
    }
    final ParseReport deepReport = ParseReport();
    final ItemData block = parseBlock(deep, report: deepReport);
    int depth = 0;
    ItemData cursor = block;
    while (cursor.children.isNotEmpty) {
      cursor = cursor.children.first;
      depth++;
    }
    expect(depth, 20);
    expect(deepReport.truncated, isFalse);
  });

  test('能力段往返', () {
    final PluginCapabilities full = fullCapabilities();
    final Map<String, Object?> json = capabilitiesToJson(full);
    expect(json['apiVersion'], full.apiVersion);
    expect(json['kind'], 'gui');
    final PluginCapabilities back = capabilitiesFromJson(json);
    expect(back.blocks.length, full.blocks.length);
    expect(back.supportsBlock('Text'), isTrue);
    expect(back.gap, full.gap);

    final PluginCapabilities minimal = minimalCapabilities();
    final PluginCapabilities minimalBack = capabilitiesFromJson(capabilitiesToJson(minimal));
    expect(minimalBack.blocks.length, 1);
    expect(minimalBack.percent, isFalse);
  });
}
