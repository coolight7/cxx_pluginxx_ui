import 'dart:typed_data';

import 'package:pluginxx_ui/pluginxx_ui.dart';
import 'package:test/test.dart';

/// 简单的来源解析：名字 → 值
class _Sources implements UiValueSourceResolver {
  _Sources(this.values);

  final Map<String, UiValue> values;

  @override
  UiValue? resolveValue(String name, UiValueCtx ctx, {required bool convert}) =>
      values[name];
}

UiValueCtx _ctx({
  Map<String, UiValue>? sources,
  UiValueScope? scope,
  double timeSec = 0,
  double dtSec = 0,
}) => UiValueCtx(
  timeSec: timeSec,
  dtSec: dtSec,
  night: false,
  paletteValid: false,
  spectrumAvailable: true,
  sources: _Sources(sources ?? <String, UiValue>{}),
  scope: scope,
);

UiValueNode _node(Object? json) {
  final List<String> problems = <String>[];
  final UiValueNode? node = parseUiValueNode(json, problems, 'test');
  expect(node, isNotNull, reason: problems.join('; '));
  return node!;
}

void main() {
  group('值表达式', () {
    test('字面量与数字格式化', () {
      expect(_node(12).eval(_ctx()).number, 12);
      expect(_node('abc').eval(_ctx()).asText(), 'abc');
      expect(UiValue.formatNumber(12), '12');
      expect(UiValue.formatNumber(1.5), '1.5');
      expect(UiValue.formatNumber(-0.0), '0');
    });

    test('source 来源与 fallback', () {
      final UiValueNode node = _node(<String, Object?>{
        'kind': 'source',
        'name': 'musicxx.spectrum.level',
      });
      expect(
        node.eval(_ctx(sources: <String, UiValue>{
          'musicxx.spectrum.level': UiValue.number(0.7),
        })).number,
        closeTo(0.7, 1e-6),
      );
      expect(node.eval(_ctx()).number, 0);
      final UiValueNode withFallback = _node(<String, Object?>{
        'kind': 'source',
        'name': 'musicxx.spectrum.level',
        'fallback': 0.25,
      });
      expect(withFallback.eval(_ctx()).number, 0.25);
    });

    test('四则与比较、逻辑、select', () {
      final UiValueCtx ctx = _ctx();
      expect(
        _node(<String, Object?>{
          'kind': 'add',
          'of': <Object?>[1, 2, 3],
        }).eval(ctx).number,
        6,
      );
      expect(
        _node(<String, Object?>{
          'kind': 'mul',
          'of': <Object?>[2, 3],
        }).eval(ctx).number,
        6,
      );
      expect(
        _node(<String, Object?>{
          'kind': 'clamp',
          'of': 9,
          'min': 0,
          'max': 5,
        }).eval(ctx).number,
        5,
      );
      expect(
        _node(<String, Object?>{
          'kind': 'cmp',
          'op': 'gt',
          'a': 3,
          'b': 1,
        }).eval(ctx).flag,
        isTrue,
      );
      expect(
        _node(<String, Object?>{
          'kind': 'select',
          'cond': <String, Object?>{'kind': 'cmp', 'op': 'lt', 'a': 1, 'b': 2},
          'then': '小',
          'else': '大',
        }).eval(ctx).asText(),
        '小',
      );
    });

    test('smooth 按时间推进（状态存在节点里）', () {
      double source = 0;
      final UiValueNode smooth = _node(<String, Object?>{
        'kind': 'smooth',
        'attackMs': 100,
        'releaseMs': 100,
        'of': <String, Object?>{'kind': 'source', 'name': 'v'},
      });
      UiValueCtx ctx() => _ctx(
        dtSec: 0.05,
        sources: <String, UiValue>{'v': UiValue.number(source)},
      );
      expect(smooth.eval(ctx()).number, 0);
      source = 1;
      final double first = smooth.eval(ctx()).number;
      expect(first, greaterThan(0));
      expect(first, lessThan(1));
      double value = first;
      for (int i = 0; i < 20; i++) {
        value = smooth.eval(ctx()).number;
      }
      expect(value, greaterThan(0.9));
    });

    test('局部作用域里的通道互相引用', () {
      final UiValueNode node = _node(<String, Object?>{
        'kind': 'add',
        'of': <Object?>[
          <String, Object?>{'kind': 'source', 'name': 'a'},
          <String, Object?>{'kind': 'source', 'name': 'b'},
        ],
      });
      final UiValueScope scope = UiValueScope(
        values: <String, UiValueNode>{
          'a': _node(1),
          'b': _node(<String, Object?>{
            'kind': 'source',
            'name': 'a',
            'fallback': 10,
          }),
        },
      );
      expect(node.eval(_ctx(scope: scope)).number, 2);
    });

    test('collectSources 与 needsSourcePrefix', () {
      final UiValueParseResult result = parseUiArgsTable(<String, Object?>{
        'w': <String, Object?>{
          'kind': 'source',
          'name': 'musicxx.spectrum.level',
        },
        'h': <String, Object?>{
          'kind': 'source',
          'name': 'musicxx.icon.main',
        },
      });
      expect(result.problems, isEmpty);
      expect(result.table.needsSourcePrefix('musicxx.spectrum.'), isTrue);
      expect(result.table.needsSourcePrefix('musicxx.icon.'), isTrue);
      expect(result.table.needsSourcePrefix('musicxx.env.'), isFalse);
      expect(result.table.evaluate(_ctx()).length, 2);
    });

    test('非法节点给出原因而不是抛异常', () {
      final List<String> problems = <String>[];
      expect(parseUiValueNode(<String, Object?>{'kind': 'nope'}, problems, 'x'), isNull);
      expect(problems, isNotEmpty);
    });

    test('值的相等的判断（消费者用来判断"值有没有变"）', () {
      final UiValue a = UiValue.vec(Float32List.fromList(<double>[1, 2, 3, 4]));
      final UiValue b = UiValue.vec(Float32List.fromList(<double>[1, 2, 3, 4]));
      final UiValue c = UiValue.vec(Float32List.fromList(<double>[1, 2, 3, 5]));
      expect(a.sameAs(b), isTrue);
      expect(a.sameAs(c), isFalse);
    });
  });
}
