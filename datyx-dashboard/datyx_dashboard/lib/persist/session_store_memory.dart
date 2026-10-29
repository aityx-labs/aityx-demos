import 'session_store.dart';

/// Off the web, nothing outlives the app: memory.
class PlatformSessionStore extends MemorySessionStore {}
