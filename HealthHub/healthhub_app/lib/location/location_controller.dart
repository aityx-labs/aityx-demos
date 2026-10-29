import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Where the user is: the point and how sure the device is, in metres.
class UserLocation {
  const UserLocation(this.point, {this.accuracy = 0});

  final LatLng point;
  final double accuracy;
}

/// Where the user's location stands.
enum LocationStatus {
  /// Asking the device (and the user, for permission).
  asking,

  /// Found, and followed as it changes.
  found,

  /// The user said no, or the browser blocks it.
  denied,

  /// No location here: services off, or a platform without them.
  unavailable,
}

/// Why there is no location: the status to show and a line saying why.
class LocationProblem implements Exception {
  const LocationProblem(this.status, this.message);

  final LocationStatus status;
  final String message;

  @override
  String toString() => message;
}

/// Where locations come from: the device's (GeolocatorSource), or a test's.
abstract class LocationSource {
  /// The user's location, first as soon as it is known, then each change.
  /// Fails with a [LocationProblem] when there is none to give.
  Stream<UserLocation> watch();
}

/// The device's location through `geolocator`: the browser's geolocation
/// on the web (which asks the user), the platform's services elsewhere.
class GeolocatorSource implements LocationSource {
  const GeolocatorSource();

  @override
  Stream<UserLocation> watch() async* {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationProblem(
        LocationStatus.unavailable,
        'Location services are off on this device.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationProblem(
        LocationStatus.denied,
        'Allow location access to see where you are.',
      );
    }
    const settings = LocationSettings(accuracy: LocationAccuracy.high);
    yield _from(await Geolocator.getCurrentPosition(locationSettings: settings));
    yield* Geolocator.getPositionStream(locationSettings: settings).map(_from);
  }

  static UserLocation _from(Position p) =>
      UserLocation(LatLng(p.latitude, p.longitude), accuracy: p.accuracy);
}

/// The user's location for every map in the app: asked once, at start, and
/// followed while the app runs, so the index and home share one answer and
/// one permission prompt.
class LocationController extends ChangeNotifier {
  LocationController({LocationSource? source}) : _source = source ?? const GeolocatorSource();

  final LocationSource _source;
  StreamSubscription<UserLocation>? _watching;
  LocationStatus _status = LocationStatus.asking;
  UserLocation? _location;
  String? _message;

  LocationStatus get status => _status;

  /// The last location found, or null.
  UserLocation? get location => _location;

  /// Why there is no location, when there isn't.
  String? get message => _message;

  /// Starts asking; again after a failure (the user may have allowed it).
  void start() {
    _watching?.cancel();
    _status = LocationStatus.asking;
    _message = null;
    notifyListeners();
    _watching = _source.watch().listen(
      (location) {
        _location = location;
        _status = LocationStatus.found;
        _message = null;
        notifyListeners();
      },
      onError: (Object e) {
        // A later failure keeps the last location found on the map.
        if (_location != null) return;
        if (e is LocationProblem) {
          _status = e.status;
          _message = e.message;
        } else {
          _status = LocationStatus.unavailable;
          _message = kIsWeb
              ? 'This browser did not give a location.'
              : 'No location on this device.';
        }
        notifyListeners();
      },
    );
  }

  @override
  void dispose() {
    _watching?.cancel();
    super.dispose();
  }
}
