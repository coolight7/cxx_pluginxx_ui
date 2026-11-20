import 'package:pluginxx_ui/pluginxx_ui.dart';
import 'package:test/test.dart';

void main() {
  group('文本取值', () {
    test('语言表优先，缺键用 fallback', () {
      final Map<String, String> table = <String, String>{'ui.play': '播放'};
      expect(
        resolveTextValue(
          const TextValue(key: 'ui.play', fallback: '播放（备用）'),
          lookup: (String key) => table[key] ?? '',
        ),
        '播放',
      );
      expect(
        resolveTextValue(
          const TextValue(key: 'ui.missing', fallback: '备用'),
          lookup: (String key) => table[key] ?? '',
        ),
        '备用',
      );
    });

    test('字符串里插值变量，args 里的值也可以是变量', () {
      final List<String> missing = <String>[];
      final String text = resolveTextValue(
        const TextValue(
          fallback: '{musicxx.song.name} · {n} 首',
          args: <String, Object?>{'n': <String, Object?>{'var': 'cnt'}},
        ),
        values: <String, Object?>{'musicxx.song.name': '晴天', 'cnt': 3},
        missing: missing,
      );
      expect(text, '晴天 · 3 首');
      expect(missing, isEmpty);
    });

    test('取不到的变量换空串并记一条', () {
      final List<String> missing = <String>[];
      expect(
        resolveTextValue(
          const TextValue(fallback: '歌手：{musicxx.song.artist}'),
          values: const <String, Object?>{},
          missing: missing,
        ),
        '歌手：',
      );
      expect(missing, <String>['musicxx.song.artist']);
    });

    test('值表达式用回调求值；求值失败退回字面量', () {
      const TextValue expr = TextValue(fallback: '备用', expr: <String, Object?>{'kind': 'const', 'value': 'x'});
      expect(resolveTextValue(expr, evalExpr: (Object? node) => '求值结果'), '求值结果');
      expect(resolveTextValue(expr), '备用');
      expect(
        resolveTextValue(expr, evalExpr: (Object? node) => throw StateError('bad')),
        '备用',
      );
    });
  });
}
