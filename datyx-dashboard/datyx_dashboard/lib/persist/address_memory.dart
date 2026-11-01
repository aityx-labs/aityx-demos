/// Off the web there is no address to keep the tab in.
void replaceQuery(Map<String, String> query) {}

/// Off the web there are no tabs to open: the links asked for, for tests.
final List<String> opened = [];

void openTab(String url) => opened.add(url);
