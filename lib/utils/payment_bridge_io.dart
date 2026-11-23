/// There is only one screen on native, so the checkout returns through the
/// provider's success URL in the same app and no tab-to-tab message is needed.
void notifyPaymentConfirmed(String token) {}

void Function() listenPaymentConfirmed(
  String token,
  void Function() onConfirmed,
) {
  return () {};
}
