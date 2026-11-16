/// Trims a customer name and collapses repeated spaces, so " ah  seng " and
/// "Ah Seng" are the same person and share one statement link.
String normaliseCustomerName(String value) {
  final cleaned = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (cleaned.isEmpty) return '';
  return cleaned
      .split(' ')
      .map(
        (word) => word.length == 1
            ? word.toUpperCase()
            : word[0].toUpperCase() + word.substring(1),
      )
      .join(' ');
}
