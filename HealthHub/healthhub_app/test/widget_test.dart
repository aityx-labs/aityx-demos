import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthhub_app/api/health_hub_api.dart';
import 'package:healthhub_app/auth/auth_controller.dart';
import 'package:healthhub_app/location/location_controller.dart';
import 'package:healthhub_app/main.dart';
import 'package:latlong2/latlong.dart';

/// An API with sign-in on or off.
class FakeApi implements HealthHubApi {
  FakeApi({this.auth = true});

  final bool auth;

  @override
  Future<AuthConfig> authConfig() async => AuthConfig(
    enabled: auth,
    issuer: 'https://accounts.google.com',
  );

  @override
  Future<Health> health() async => Health(ok: true, db: true, aityx: false);

  @override
  Future<Me> me() async => const Me(authenticated: false);

  @override
  Future<Me> datyxMe() async => const Me(authenticated: false);

  @override
  Future<int> datyxDataSources() async => 0;

  @override
  Future<Greeting> hello() async => Greeting(message: 'Hello, world', since: null, postgres: 'PostgreSQL 17.6');
}

/// A sign-in that is on and says who is signed in, without Google.
class FakeAuth extends AuthController {
  FakeAuth({this.signedInAs});

  SignedInUser? signedInAs;
  AuthConfig? _config;

  @override
  Future<void> start(AuthConfig config) async {
    _config = config;
    notifyListeners();
  }

  @override
  AuthConfig? get config => _config;

  @override
  bool get enabled => _config?.enabled ?? false;

  @override
  bool get signedIn => signedInAs != null;

  @override
  SignedInUser? get user => signedInAs;

  @override
  Future<void> signOut() async {
    signedInAs = null;
    notifyListeners();
  }
}

/// Locations a test hands out, or a problem.
class FakeLocations implements LocationSource {
  FakeLocations({this.problem});

  final LocationProblem? problem;
  final _controller = StreamController<UserLocation>.broadcast();

  void move(double lat, double lng) => _controller.add(UserLocation(LatLng(lat, lng), accuracy: 30));

  @override
  Stream<UserLocation> watch() =>
      problem != null ? Stream.error(problem!) : _controller.stream;
}

Widget app({FakeApi? api, FakeAuth? auth, FakeLocations? locations}) => HealthHubApp(
  api: api ?? FakeApi(),
  auth: auth ?? FakeAuth(),
  location: LocationController(source: locations ?? FakeLocations()),
  showTiles: false,
);

void main() {
  testWidgets('the index: a map and the welcome for someone not signed in', (tester) async {
    final locations = FakeLocations();
    await tester.pumpWidget(app(locations: locations));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to HealthHub'), findsOneWidget);
    expect(find.text('Finding where you are…'), findsOneWidget);
    expect(find.byKey(const Key('you-are-here')), findsNothing);

    locations.move(38.72, -9.14);
    await tester.pumpAndSettle();
    expect(find.text('The orange dot is you.'), findsOneWidget);
    expect(find.byKey(const Key('you-are-here')), findsOneWidget);
    expect(find.byKey(const Key('location-tile')), findsNothing);
  });

  testWidgets('says why when the location is refused, and asks again', (tester) async {
    await tester.pumpWidget(
      app(
        locations: FakeLocations(
          problem: const LocationProblem(LocationStatus.denied, 'Allow location access to see where you are.'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Allow location access to see where you are.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byKey(const Key('you-are-here')), findsNothing);
  });

  testWidgets('home after signing in: a dashboard with the map tile', (tester) async {
    final auth = FakeAuth(signedInAs: const SignedInUser(name: 'Ada', email: 'ada@example.com'));
    final locations = FakeLocations();
    await tester.pumpWidget(app(auth: auth, locations: locations));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to HealthHub'), findsNothing);
    expect(find.text('HealthHub'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.byKey(const Key('location-tile')), findsOneWidget);
    expect(find.text('Where you are'), findsOneWidget);

    locations.move(38.72, -9.14);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('you-are-here')), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to HealthHub'), findsOneWidget);
  });

  testWidgets('home straight away when the API has sign-in off', (tester) async {
    await tester.pumpWidget(app(api: FakeApi(auth: false)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('location-tile')), findsOneWidget);
    expect(find.text('Welcome to HealthHub'), findsNothing);
  });
}
