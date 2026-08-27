import 'package:flutter_test/flutter_test.dart';
import 'package:kurier_web/core/gif_search.dart';

void main() {
  test('gifUrlsFromJson reads vanilla results and KLIPY nested files', () {
    expect(
      gifUrlsFromJson({
        'results': [
          {'url': 'https://cdn.example/a.gif'},
          {'previewUrl': 'https://cdn.example/b.gif'},
        ],
      }),
      [
        'https://cdn.example/a.gif',
        'https://cdn.example/b.gif',
      ],
    );

    expect(
      gifUrlsFromJson({
        'data': {
          'data': [
            {
              'file': {
                'hd': {
                  'gif': {'url': 'https://klipy.example/hd.gif'},
                },
              },
            },
          ],
        },
      }),
      ['https://klipy.example/hd.gif'],
    );
  });
}
