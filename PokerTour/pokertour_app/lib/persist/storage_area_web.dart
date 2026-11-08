import 'package:aityx_web/aityx_web.dart' show StorageArea;
import 'package:web/web.dart' as web;

StorageArea localArea() => _WebArea(() => web.window.localStorage);
StorageArea sessionArea() => _WebArea(() => web.window.sessionStorage);

class _WebArea implements StorageArea {
  _WebArea(this._storage);

  final web.Storage Function() _storage;

  @override
  String? read(String name) => _storage().getItem(name);

  @override
  void write(String name, String value) => _storage().setItem(name, value);

  @override
  void remove(String name) => _storage().removeItem(name);
}
