/// Care centers: the hospitals, clinics and health stations HealthHub
/// knows, seeded into the care_centers table at start (lib/db.dart). The
/// rows are data/care_centers.jsonl, compiled in as lib/care_centers_seed.dart
/// by tool/generate_care_centers.dart, since the API ships as a single
/// native executable.
library;

/// What a care center is: an inpatient hospital, an outpatient clinic, or
/// a primary-care health station (a CAP, a UBS, a community health center).
const careCenterKinds = {'hospital', 'clinic', 'health_station'};

/// Who runs it, as the source says.
const careCenterOwnerships = {'public', 'private', 'unknown'};

/// One care center, as the seed holds it. [key] is unique and stable
/// across reseeds: the source and its id for the facility, or the
/// country, city, name and address when the source has no id.
class CareCenter {
  const CareCenter(
    this.key,
    this.name,
    this.kind,
    this.subtype,
    this.address,
    this.postalCode,
    this.city,
    this.region,
    this.country,
    this.latitude,
    this.longitude,
    this.phone,
    this.website,
    this.ownership,
    this.source,
    this.sourceId,
  );

  /// A row of data/care_centers.jsonl.
  factory CareCenter.fromJson(Map<String, Object?> json) {
    String? text(String name) {
      final value = (json[name] as String?)?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    String required(String name) =>
        text(name) ?? (throw FormatException('care center without "$name": $json'));

    final kind = required('kind');
    if (!careCenterKinds.contains(kind)) {
      throw FormatException('care center kind "$kind": $json');
    }
    final ownership = text('ownership') ?? 'unknown';
    if (!careCenterOwnerships.contains(ownership)) {
      throw FormatException('care center ownership "$ownership": $json');
    }
    final source = required('source');
    final sourceId = text('source_id');
    final name = required('name');
    final city = required('city');
    final country = required('country');
    final address = text('address');
    return CareCenter(
      sourceId != null
          ? '$source:$sourceId'
          : '$country:$city:$name:${address ?? ''}'.toLowerCase(),
      name,
      kind,
      text('subtype'),
      address,
      text('postal_code'),
      city,
      required('region'),
      country,
      (json['lat'] as num?)?.toDouble(),
      (json['lon'] as num?)?.toDouble(),
      text('phone'),
      // Registries put an email address there now and then: not a website,
      // and sometimes a person's.
      text('website')?.contains('@') == true ? null : text('website'),
      ownership,
      source,
      sourceId,
    );
  }

  final String key;
  final String name;
  final String kind;
  final String? subtype;
  final String? address;
  final String? postalCode;
  final String city;
  final String region;
  final String country;
  final double? latitude;
  final double? longitude;
  final String? phone;
  final String? website;
  final String ownership;
  final String source;
  final String? sourceId;

  /// The columns of care_centers, in [values] order.
  static const columns = [
    'key', 'name', 'kind', 'subtype', 'address', 'postal_code', 'city',
    'region', 'country', 'latitude', 'longitude', 'phone', 'website',
    'ownership', 'source', 'source_id',
  ];

  List<Object?> get values => [
    key, name, kind, subtype, address, postalCode, city, region, country,
    latitude, longitude, phone, website, ownership, source, sourceId,
  ];
}

/// A care center's capacity in the simulation: beds for a hospital,
/// places (rooms, chairs) for a clinic or a health station. The registries
/// don't say how big a facility is, and the simulation's twenty people a
/// city would fill no real hospital, so the capacity is sized to the
/// simulation instead: 4 to 12 beds, 2 to 6 places at a clinic, 2 to 5 at
/// a health station, drawn from the center's [key] so it is the same at
/// every start and in every run.
({int places, String unit}) simulatedCapacity(String key, String kind) {
  final (low, high, unit) = switch (kind) {
    'hospital' => (4, 12, 'beds'),
    'health_station' => (2, 5, 'places'),
    _ => (2, 6, 'places'),
  };
  return (places: low + _fnv1a(key) % (high - low + 1), unit: unit);
}

/// FNV-1a over [text]'s UTF-16 code units: a hash that, unlike
/// String.hashCode, is the same in every run and every Dart.
int _fnv1a(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash;
}
