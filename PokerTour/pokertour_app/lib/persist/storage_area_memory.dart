import 'package:aityx_web/aityx_web.dart' show MapArea, StorageArea;

/// Off the web, nothing outlives the app.
StorageArea localArea() => MapArea();
StorageArea sessionArea() => MapArea();
