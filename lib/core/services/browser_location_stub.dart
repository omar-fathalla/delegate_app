/// Non-web builds have no browser address bar.
({String path, String query, String hash, String base})?
readBrowserLocation() => null;

void replaceBrowserUrl(String url) {}
