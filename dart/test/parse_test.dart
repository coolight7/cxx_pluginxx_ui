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

  test('尺寸字段接受值表达式（带 kind 的对象原样保留）', () {
    // 字面量：数值 / auto / percent 都不变
    expect(parseBlock(<String, Object?>{'kind': 'Gap', 'size': 12}).size.isValue, isTrue);
    expect(
      parseBlock(<String, Object?>{'kind': 'Gap', 'size': 'auto'}).size.isAuto,
      isTrue,
    );
    final ItemData percent = parseBlock(<String, Object?>{
      'kind': 'SizedBox',
      'height': <String, Object?>{'percent': 40},
    });
    expect(percent.height.isPercent, isTrue);
    expect(percent.height.value, 40);

    // 值表达式：整份 JSON 保留给客户端求值，往返不丢
    final Map<String, Object?> node = <String, Object?>{
      'kind': 'lfo',
      'periodMs': 1600,
      'from': 40,
      'to': 72,
    };
    final ItemData item = parseBlock(<String, Object?>{
      'kind': 'SizedBox',
      'width': <String, Object?>{'kind': 'const', 'value': 120},
      'height': node,
    });
    expect(item.width.isExpr, isTrue);
    expect((item.width.expr! as Map)['kind'], 'const');
    expect(item.height.isExpr, isTrue);
    expect(dumpItem(item)['height'], node, reason: '值表达式往返保持原样');
    expect(dumpItem(item)['width'], <String, Object?>{'kind': 'const', 'value': 120});
  });

  test('动画块（musicxx.AnimatedBuilder / SizeTransition / FadeTransition）解析与往返', () {
    final ItemData builder = parseBlock(<String, Object?>{
      'kind': 'musicxx.AnimatedBuilder',
      'values': <String, Object?>{
        'h': <String, Object?>{'kind': 'const', 'value': 40},
      },
      'maxFps': 24,
      'children': <Object?>[
        <String, Object?>{'kind': 'Text', 'text': '动画子树'},
      ],
    });
    expect(builder.kind, 'musicxx.AnimatedBuilder');
    expect((builder.animValues! as Map)['h'], isNotNull);
    expect(builder.maxFps, 24);
    expect(builder.children.length, 1);

    final ItemData size = parseBlock(<String, Object?>{
      'kind': 'musicxx.SizeTransition',
      'axis': 'horizontal',
      'axisAlignment': 0,
      'value': <String, Object?>{'kind': 'source', 'name': 'h'},
      'curve': 'outCubic',
      'children': <Object?>[
        <String, Object?>{'kind': 'Text', 'text': '撑开'},
      ],
    });
    expect(size.axis, 'horizontal');
    expect(size.axisAlignment, 0);
    expect(size.curve, 'outCubic');
    expect(size.animValue.isExpr, isTrue);
    expect((size.animValue.raw! as Map)['name'], 'h');
    expect(dumpItem(size)['value'], size.animValue.raw);

    // 值是数字时照旧（原始值与数值字段都能拿到）
    final ItemData fade = parseBlock(<String, Object?>{
      'kind': 'musicxx.FadeTransition',
      'value': 0.5,
      'children': <Object?>[
        <String, Object?>{'kind': 'Text', 'text': '淡入'},
      ],
    });
    expect(fade.animValue.number, 0.5, reason: '数字字面量直接用');
    expect(dumpItem(fade)['value'], 0.5);
  });

  test('文本字段写值表达式 + 公共字段 visible / action', () {
    // 文本字段：值表达式原样保留，求值交给客户端
    final ItemData text = parseBlock(<String, Object?>{
      'kind': 'Text',
      'text': <String, Object?>{
        'kind': 'format',
        'value': <String, Object?>{'kind': 'const', 'value': 42},
        'text': '进度 {0}%',
      },
    });
    expect(text.text.isExpr, isTrue);
    expect(dumpItem(text)['text'], text.text.expr);

    // 公共字段：每个块都能写 visible（字面量或值表达式）；action 也收进公共字段
    final ItemData visible = parseBlock(<String, Object?>{
      'kind': 'Gap',
      'size': 12,
      'visible': false,
      'action': 'openSettings',
    });
    expect(visible.visible.flag, isFalse);
    expect(visible.action?.isNotEmpty, isTrue);
    expect(dumpItem(visible)['visible'], false, reason: 'visible 往返不丢');
    expect(dumpItem(visible)['action'], 'openSettings', reason: 'action 是公共字段（块里不再逐个声明）');

    final ItemData dynamicVisible = parseBlock(<String, Object?>{
      'kind': 'Text',
      'text': '条件块',
      'visible': <String, Object?>{'kind': 'const', 'value': 1},
    });
    expect(dynamicVisible.visible.isExpr, isTrue);
  });
  test('列表块（ListViewBase / ListView）解析与往返', () {
    final ItemData base = parseBlock(<String, Object?>{
      'kind': 'ListViewBase',
      'id': 'subs',
      'layout': 'grid',
      'variant': 'plain',
      'emptyText': '还没有订阅',
      'items': <Object?>[
        <String, Object?>{
          'id': 'weekly',
          'title': '每周新歌',
          'subtitle': '每周一更新',
          'trailing': '12 首',
          'image': 'cover',
          'selected': true,
          'action': 'openPlaylist',
        },
        <String, Object?>{'title': '我的收藏', 'tone': 'hint'},
      ],
    });
    expect(base.kind, 'ListViewBase');
    expect(base.layout, 'grid');
    expect(base.variant, 'plain');
    expect(base.emptyText.fallback, '还没有订阅');
    expect(base.items.length, 2);
    expect(base.items.first.id, 'weekly');
    expect(base.items.first.title.fallback, '每周新歌');
    expect(base.items.first.subtitle.fallback, '每周一更新');
    expect(base.items.first.trailing.fallback, '12 首');
    expect(base.items.first.image, 'cover');
    expect(base.items.first.selected, isTrue);
    expect(base.items.first.action?.name, 'openPlaylist');
    expect(base.items[1].tone, 'hint');
    // 默认值：没写 layout / variant / 工具条字段
    final ItemData plain = parseBlock(<String, Object?>{
      'kind': 'ListView',
      'items': <Object?>[],
    });
    expect(plain.layout, 'auto');
    expect(plain.variant, 'card');
    expect(plain.enableCheck, isTrue);
    expect(plain.enableDrop, isTrue);
    expect(plain.showCount, isFalse);
    expect(plain.editAction, isNull);

    final ItemData full = parseBlock(<String, Object?>{
      'kind': 'ListView',
      'items': <Object?>[],
      'toolbar': <Object?>[
        <String, Object?>{'kind': 'Text', 'text': '共 12 项'},
      ],
      'menu': <Object?>[
        <String, Object?>{'title': '全部刷新', 'icon': 'resource/svg/refresh.svg', 'action': 'refreshAll'},
      ],
      'itemMenu': <Object?>[
        <String, Object?>{'title': '重命名', 'action': 'rename'},
      ],
      'editAction': 'beginEdit',
      'saveAction': 'saveOrder',
      'removeTipTitle': '确认删除',
      'showCount': true,
    });
    expect(full.toolbar.length, 1);
    expect(full.menu.first.title.fallback, '全部刷新');
    expect(full.menu.first.icon, 'resource/svg/refresh.svg');
    expect(full.itemMenu.first.action?.name, 'rename');
    expect(full.editAction?.name, 'beginEdit');
    expect(full.saveAction?.name, 'saveOrder');
    expect(full.removeTipTitle.fallback, '确认删除');
    expect(full.showCount, isTrue);

    // 往返稳定
    final Map<String, Object?> dumped = dumpItem(full);
    final Object secondDump = dumpItem(parseBlock(dumped));
    expect(jsonEncode(secondDump), jsonEncode(dumped));
    // 列表项的非对象元素只记提示，不使整份描述失效
    final ParseReport report = ParseReport();
    final ItemData mixed = parseBlock(<String, Object?>{
      'kind': 'ListViewBase',
      'items': <Object?>['乱写的', 3],
    }, report: report);
    expect(mixed.items, isEmpty);
    expect(report.warnings, isNotEmpty);
  });

  test('列表项的 song：带 src 才算歌曲，往返稳定', () {
    final ItemData view = parseBlock(<String, Object?>{
      'kind': 'musicxx.DirListView',
      'items': <Object?>[
        <String, Object?>{
          'title': '稻香.flac',
          'path': '/Music/稻香.flac',
          'song': <String, Object?>{
            'type': 'plugin.demo.audio',
            'src': 'a/稻香.flac',
            'artist': '周杰伦',
            'fileName': '稻香.flac',
            'size': 12345678,
            'durationMs': 223000,
            'cover': 'resource/cover/a.jpg',
          },
        },
        // 只给了 artist 没有 src：不当歌曲（按普通文件画）
        <String, Object?>{
          'title': '说明.txt',
          'path': '/Music/说明.txt',
          'song': <String, Object?>{'artist': '无关'},
        },
      ],
    });
    expect(view.items.first.song, isNotNull);
    expect(view.items.first.song!.type, 'plugin.demo.audio');
    expect(view.items.first.song!.src, 'a/稻香.flac');
    expect(view.items.first.song!.artist.fallback, '周杰伦');
    expect(view.items.first.song!.fileName, '稻香.flac');
    expect(view.items.first.song!.size, 12345678);
    expect(view.items.first.song!.durationMs, 223000);
    expect(view.items.first.song!.cover, 'resource/cover/a.jpg');
    expect(view.items[1].song, isNull);

    final Map<String, Object?> dumped = dumpItem(view);
    expect(jsonEncode(dumpItem(parseBlock(dumped))), jsonEncode(dumped));
  });

  test('控件形态包含 password', () {
    expect(kControlKinds.contains('password'), isTrue);
    final ItemData item = parseBlock(<String, Object?>{
      'kind': 'Control',
      'control': 'PASSWORD',
      'id': 'token',
      'value': 'abc',
    });
    expect(item.control, 'password');
    expect(item.controlValue, 'abc');
  });

  test('Progress.value 接受值表达式', () {
    final Map<String, Object?> node = <String, Object?>{
      'kind': 'source',
      'name': 'plugin.demo.progress',
    };
    final ItemData item = parseBlock(<String, Object?>{
      'kind': 'Progress',
      'value': node,
      'total': 100,
    });
    expect(item.value.isExpr, isTrue, reason: '值表达式原样保留');
    expect(item.value.raw, node);
    expect(item.value.number, 0, reason: '表达式没有字面量数值，客户端求值后才有效');
    expect(dumpItem(item)['value'], node);

    // 数字写法不受影响
    final ItemData plain = parseBlock(<String, Object?>{
      'kind': 'Progress',
      'value': 72,
    });
    expect(plain.value.isExpr, isFalse);
    expect(plain.value.number, 72);
  });
}
