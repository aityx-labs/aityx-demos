import 'package:contacthub_app/request/samples.dart';
import 'package:contacthub_app/routing/routing_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('there is one sample for each department', () {
    final departments = {
      for (final MapEntry(:key, :value) in topicNames.entries)
        if (key != 'other') value,
    };
    expect(departmentSamples.map((s) => s.department).toSet(), departments);
    expect(departmentSamples.length, departments.length);
  });
}
