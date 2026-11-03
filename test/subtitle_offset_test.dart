import 'package:flutter_test/flutter_test.dart';
import 'package:srctv_flutter/data/store/subtitle_offset.dart';

void main() {
  test('offset display is signed seconds', () {
    expect(formatSubtitleOffset(0), '0s');
    expect(formatSubtitleOffset(500), '+0.5s');
    expect(formatSubtitleOffset(1000), '+1s');
    expect(formatSubtitleOffset(-500), '-0.5s');
    expect(formatSubtitleOffset(-1500), '-1.5s');
  });
}
