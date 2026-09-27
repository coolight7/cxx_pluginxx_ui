// 纯文本降级（Dart 绑定）
//
// 与 C++ 侧 tests/test_plain_text.cpp 使用同一批断言（同样的字面期望值），
// 并逐字节比对 fixtures/plaintext.golden.json（由 C++ 侧生成）。
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

void main() {
  test('纯文本的基本形态', () {
    final UiDocument doc = parseDocument(
      jsonDecode(File('$fixturesDir/tui_heavy.json').readAsStringSync()),
    );
    final String out = plainTextDocument(doc);
    expect(out, contains('等宽文本'));
    expect(out, contains('状态: 运行中'));
    expect(out, contains('命令   说明'));
    expect(out, contains('-----------'));
    expect(out, contains('build  构建'));
    expect(out, contains('agent\n  lib\ndocs'));
    expect(out, contains('\u2581\u2584\u2582\u2588\u2585 5'));
    expect(out, contains('\u258F\u258F\u2588'));
    expect(out, contains('-' * 40));
    expect(out, contains('[----------] 0%'));
    expect(out, contains('[居中标签]'));
  });

  test('纯文本逐行形态', () {
    final List<ItemData> items = parseBlocks(<Object?>[
      <String, Object?>{
        'kind': 'KV',
        'pairs': <Object?>[
          <String, Object?>{'k': 'a', 'v': '1'},
          <String, Object?>{'k': 'bb', 'v': '2'},
        ],
      },
      <String, Object?>{'kind': 'Progress', 'label': '进度', 'value': 50, 'unit': '%'},
      <String, Object?>{'kind': 'Badge', 'text': 'OK'},
    ]);
    expect(plainText(items), 'a  : 1\nbb : 2\n进度: [#####-----] 50%\n[OK]');
  });

  test('纯文本按宽度折行', () {
    final List<ItemData> ascii =
        parseBlocks(<Object?>[<String, Object?>{'kind': 'Text', 'text': 'abcdefgh'}]);
    expect(plainText(ascii, width: 4), 'abcd\nefgh');

    final List<ItemData> wide =
        parseBlocks(<Object?>[<String, Object?>{'kind': 'Text', 'text': '中文abc'}]);
    expect(plainText(wide, width: 4), '中文\nabc');
  });

  test('纯文本的缩进留白', () {
    // Padding 的左留白折算成缩进列数（u → 列，默认每列 8u）; 折行宽度扣掉缩进
    final List<ItemData> items = parseBlocks(<Object?>[
      <String, Object?>{
        'kind': 'Padding',
        'padding': 16,
        'children': <Object?>[<String, Object?>{'kind': 'Text', 'text': 'abc'}],
      },
    ]);
    expect(plainText(items), '  abc');
    expect(plainText(items, width: 6), '  abc');

    final List<ItemData> wrapped = parseBlocks(<Object?>[
      <String, Object?>{
        'kind': 'Padding',
        'padding': 16,
        'children': <Object?>[<String, Object?>{'kind': 'Text', 'text': 'abcdefgh'}],
      },
    ]);
    expect(plainText(wrapped, width: 6), '  abcd\n  efgh');

    final List<ItemData> others = parseBlocks(<Object?>[
      <String, Object?>{
        'kind': 'Padding',
        'padding': <String, Object?>{'left': 3, 'top': 40, 'right': 40, 'bottom': 40},
        'children': <Object?>[<String, Object?>{'kind': 'Text', 'text': 'x'}],
      },
    ]);
    expect(plainText(others), 'x');
  });

  test('纯文本的容器与降级形态', () {
    final List<ItemData> items = parseBlocks(<Object?>[
      <String, Object?>{
        'kind': 'Block',
        'title': '卡片',
        'children': <Object?>[<String, Object?>{'kind': 'Text', 'text': '内容'}],
      },
      <String, Object?>{
        'kind': 'Row',
        'children': <Object?>[
          <String, Object?>{'kind': 'Text', 'text': '左'},
          <String, Object?>{'kind': 'Text', 'text': '右'},
        ],
      },
      <String, Object?>{'kind': 'Button', 'label': '保存'},
      <String, Object?>{
        'kind': 'Collapse',
        'id': 'x',
        'title': '折叠',
        'expanded': false,
        'children': <Object?>[<String, Object?>{'kind': 'Text', 'text': '隐藏'}],
      },
      <String, Object?>{'kind': 'Icon', 'glyph': '▶'},
      <String, Object?>{'kind': 'Image', 'alt': '封面'},
      <String, Object?>{
        'kind': 'Stack',
        'children': <Object?>[
          <String, Object?>{'kind': 'Text', 'text': '底'},
          <String, Object?>{'kind': 'Text', 'text': '顶'},
        ],
      },
      <String, Object?>{
        'kind': 'musicxx.Shader',
        'bundle': 'a.shaderbundle',
        'fallback': '着色器',
      },
    ]);
    expect(
      plainText(items),
      '卡片\n  内容\n左 | 右\n[保存]\n[+] 折叠\n▶\n封面\n顶\n着色器',
    );
  });

  test('显示列宽', () {
    expect(displayWidth('abc'), 3);
    expect(displayWidth('中文'), 4);
    expect(displayWidth('a中b'), 4);
  });

  test('纯文本与 C++ 侧逐字节一致（金文件）', () {
    final File goldenFile = File('$fixturesDir/plaintext.golden.json');
    if (!goldenFile.existsSync()) {
      fail('缺少 fixtures/plaintext.golden.json');
    }
    final Map<String, Object?> golden =
        (jsonDecode(goldenFile.readAsStringSync()) as Map).cast<String, Object?>();
    golden.forEach((String name, Object? expected) {
      final File fixture = File('$fixturesDir/$name');
      if (!fixture.existsSync()) {
        return;
      }
      final String actual = plainTextDocument(
        parseDocument(jsonDecode(fixture.readAsStringSync())),
      );
      expect(actual, expected, reason: '夹具 $name 的纯文本');
    });
  });
}
