/// Native fallback: the customer statement is a web page, so saving to the
/// photo library is not available without a platform plugin. The UI falls back
/// to a "take a screenshot" hint.
bool saveDataUri(String dataUri, String fileName) => false;
