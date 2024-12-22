bool isValidUrl(String url) {
  try {
    final uri = Uri.parse(url);
    return uri.hasScheme && uri.hasAuthority;
  } catch (e) {
    return false;
  }
} 