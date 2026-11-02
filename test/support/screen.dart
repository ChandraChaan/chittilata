import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The phone behaviour tests run on (1080x2400, like a Pixel 7). Other
/// sizes and font scales are covered by layout_test.dart.
void useTestScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
}
