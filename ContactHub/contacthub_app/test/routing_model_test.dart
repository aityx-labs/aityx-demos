import 'package:contacthub_app/routing/routing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the routing model is one of the app\'s assets', () async {
    final model = await loadRoutingModel();
    expect(model['model'], 'jev-latest');
    expect(model['questions'], isA<Map>());
    expect(model['decision'], isA<Map>());
    expect(identical(await loadRoutingModel(), model), isTrue);
  });
}
