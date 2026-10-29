import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme.dart';
import 'location_controller.dart';

/// A map of OpenStreetMap's tiles, darkened to the aityx palette, with the
/// user's location highlighted: an orange dot in a white ring and a halo,
/// inside the circle of how sure the device is. It shows the whole world
/// until the location comes, then flies there; a button brings it back.
class UserLocationMap extends StatefulWidget {
  const UserLocationMap({
    super.key,
    required this.location,
    this.showTiles = true,
    this.zoom = 15,
  });

  final LocationController location;

  /// Off in tests, which have no network for the tiles.
  final bool showTiles;

  /// How close to come once the location is known.
  final double zoom;

  @override
  State<UserLocationMap> createState() => _UserLocationMapState();
}

class _UserLocationMapState extends State<UserLocationMap> {
  static const _world = LatLng(20, 0);

  final _map = MapController();
  bool _ready = false;
  bool _centred = false;

  @override
  void initState() {
    super.initState();
    widget.location.addListener(_moved);
  }

  @override
  void dispose() {
    widget.location.removeListener(_moved);
    _map.dispose();
    super.dispose();
  }

  /// The first location found centres the map once; later ones only move
  /// the dot, so a user looking around isn't pulled back.
  void _moved() {
    if (!_centred && _ready && widget.location.location != null) _centre();
    setState(() {});
  }

  void _centre() {
    final here = widget.location.location;
    if (here == null) return;
    _map.move(here.point, widget.zoom);
    _centred = true;
  }

  @override
  Widget build(BuildContext context) {
    final here = widget.location.location;
    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: here?.point ?? _world,
            initialZoom: here != null ? widget.zoom : 2,
            minZoom: 2,
            backgroundColor: Aityx.bg0,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onMapReady: () {
              _ready = true;
              _centred = here != null;
              if (!_centred) _centre();
            },
          ),
          children: [
            if (widget.showTiles)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ai.aletyx.healthhub',
                tileBuilder: darkModeTileBuilder,
              ),
            if (here != null) ...[
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: here.point,
                    radius: here.accuracy,
                    useRadiusInMeter: true,
                    color: Aityx.orange.withValues(alpha: 0.12),
                    borderColor: Aityx.orange.withValues(alpha: 0.5),
                    borderStrokeWidth: 1,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: here.point,
                    width: 44,
                    height: 44,
                    child: const _YouAreHere(key: Key('you-are-here')),
                  ),
                ],
              ),
            ],
            if (widget.showTiles)
              const SimpleAttributionWidget(
                source: Text('OpenStreetMap contributors'),
                backgroundColor: Color(0xAA17161A),
              ),
          ],
        ),
        if (here != null)
          Positioned(
            right: 12,
            bottom: 40,
            child: IconButton.filledTonal(
              key: const Key('recentre'),
              tooltip: 'Back to where you are',
              onPressed: _centre,
              icon: const Icon(Icons.my_location),
            ),
          ),
      ],
    );
  }
}

/// The highlight: an orange dot in a white ring, in a soft orange halo.
class _YouAreHere extends StatelessWidget {
  const _YouAreHere({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Aityx.orange.withValues(alpha: 0.25),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Aityx.orange,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
        ),
      ),
    ),
  );
}
