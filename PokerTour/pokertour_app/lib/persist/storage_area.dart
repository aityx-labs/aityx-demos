import 'package:aityx_web/aityx_web.dart' show MapArea, StorageArea;

import 'storage_area_memory.dart'
    if (dart.library.js_interop) 'storage_area_web.dart'
    as impl;

/// The browser's localStorage ("remember on this device") on the web,
/// memory elsewhere. Every read and write may fail (storage blocked):
/// the callers treat that as nothing stored.
StorageArea localArea() => impl.localArea();

/// The browser tab's sessionStorage ("only this session") on the web,
/// memory elsewhere.
StorageArea sessionArea() => impl.sessionArea();

/// Memory, for tests.
StorageArea memoryArea([Map<String, String>? entries]) => MapArea(entries);
