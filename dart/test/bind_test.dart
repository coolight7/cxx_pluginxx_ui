import 'package:pluginxx_ui/pluginxx_ui.dart';
import 'package:test/test.dart';

void main() {
  group('绑定', () {
    test('对象形态的变量绑定', () {
      final BindResult result = bindVariables(<String, Object?>{
        'name': <String, Object?>{'var': 'musicxx.song.name'},
        'volume': <String, Object?>{'var': 'musicxx.player.volume'},
      }, <String, Object?>{
        'musicxx.song.name': '晴天',
        'musicxx.player.volume': 72,
      });
      expect(result.value, <String, Object?>{
        'name': '晴天',
        'volume': 72,
      });
      expect(result.missing, isEmpty);
    });

    test('取不到值时用 default；没有 default 就删掉这个键', () {
      final BindResult result = bindVariables(<String, Object?>{
        'a': <String, Object?>{'var': 'musicxx.song.name', 'default': '未知'},
        'b': <String, Object?>{'var': 'musicxx.song.artist'},
        'c': 1,
      }, <String, Object?>{});
      expect(result.value, <String, Object?>{'a': '未知', 'c': 1});
      expect(result.missing, <String>['musicxx.song.artist']);
    });

    test('unit: percent 换成 {"percent": n}', () {
      final BindResult result = bindVariables(<String, Object?>{
        'width': <String, Object?>{'var': 'w', 'unit': 'percent'},
      }, <String, Object?>{'w': 40});
      expect(result.value, <String, Object?>{
        'width': <String, Object?>{'percent': 40},
      });
    });

    test('字符串插值、转义与含 args 的占位', () {
      final BindResult result = bindVariables(<String, Object?>{
        'text': '正在播放 {musicxx.song.name}',
        'escaped': r'字面量 \{musicxx.song.name} 与反斜杠 \\',
        'args': '{n} 首歌',
        'unknown': 'a {foo} b',
      }, <String, Object?>{
        'musicxx.song.name': '晴天',
      }, args: <String, Object?>{'n': 3});
      expect(result.value, <String, Object?>{
        'text': '正在播放 晴天',
        'escaped': '字面量 {musicxx.song.name} 与反斜杠 \\',
        'args': '3 首歌',
        'unknown': 'a  b',
      });
      expect(result.missing, <String>['foo']);
    });

    test('值表达式节点原样保留，着色器参数不绑定', () {
      final Map<String, Object?> node = <String, Object?>{
        'kind': 'smooth',
        'of': <String, Object?>{'kind': 'source', 'name': 'musicxx.spectrum.level'},
      };
      final BindResult result = bindVariables(<String, Object?>{
        'kind': 'musicxx.Shader',
        'args': <String, Object?>{'uName': <String, Object?>{'var': 'musicxx.song.name'}},
        'values': node,
        'visible': <String, Object?>{'var': 'musicxx.player.playing'},
      }, <String, Object?>{'musicxx.player.playing': true});
      final Map<String, Object?> out = result.value! as Map<String, Object?>;
      expect(out['values'], same(node));
      expect(
        (out['args']! as Map<String, Object?>)['uName'],
        <String, Object?>{'var': 'musicxx.song.name'},
      );
      expect(out['visible'], isTrue);
    });

    test('列表里的变量取不到时删掉这一项', () {
      final BindResult result = bindVariables(<Object?>[
        1,
        <String, Object?>{'var': 'missing.value'},
        2,
      ], <String, Object?>{});
      expect(result.value, <Object?>[1, 2]);
      expect(result.missing, <String>['missing.value']);
    });

    test('bindTextValue 保留占位参数，等 TextValue 自己替换', () {
      final TextValue value = bindTextValue(
        const TextValue(
          key: '',
          fallback: '共 {n} 首：{musicxx.song.name}',
          args: <String, Object?>{'n': 3},
        ),
        <String, Object?>{'musicxx.song.name': '晴天'},
      );
      expect(value.resolve(), '共 3 首：晴天');
    });
  });
}
