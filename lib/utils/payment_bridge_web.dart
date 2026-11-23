import 'dart:js_interop';

import 'package:web/web.dart' as web;

const _channelName = 'smartpayla-payment';

/// Tells every other tab of this site that the statement for [token] was paid.
void notifyPaymentConfirmed(String token) {
  try {
    final channel = web.BroadcastChannel(_channelName);
    channel.postMessage(token.toJS);
    channel.close();
  } catch (_) {
    // The tabs are in different browser contexts; the next refresh will catch up.
  }
}

/// Calls [onConfirmed] when another tab reports a payment for [token].
///
/// Returns a function that stops listening.
void Function() listenPaymentConfirmed(
  String token,
  void Function() onConfirmed,
) {
  web.BroadcastChannel? channel;
  try {
    channel = web.BroadcastChannel(_channelName);
    void handler(web.MessageEvent event) {
      if (event.data.dartify()?.toString() == token) onConfirmed();
    }

    final listener = handler.toJS;
    channel.addEventListener('message', listener);
    final active = channel;
    return () {
      try {
        active.removeEventListener('message', listener);
        active.close();
      } catch (_) {
        // The tab is going away.
      }
    };
  } catch (_) {
    channel?.close();
    return () {};
  }
}
