import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';

/// One phone number the player picked in the system contact picker.
class PickedContact {
  const PickedContact({required this.name, required this.number});
  final String name;
  final String number;
}

/// Inviting a friend straight from the address book, without the contacts
/// permission: Android's own picker shows the contacts and hands back only
/// the number the player tapped. Nothing is stored or sent to the server.
class ContactInvite {
  static const _channel = MethodChannel('chitplay/contacts');

  /// Opens the picker; null if the player backed out or there is no
  /// contacts app.
  static Future<PickedContact?> pick() async {
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('pickPhone');
      final number = r?['number'];
      if (number is! String || digits(number).length < 6) return null;
      final name = r?['name'];
      return PickedContact(
        name: name is String && name.trim().isNotEmpty ? name.trim() : number,
        number: number,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static String digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// The number in international form for wa.me (digits only, no +), or
  /// null when the country can't be told. Local 10-digit numbers get India's
  /// code when the phone is set to India, and a leading 0 trunk prefix is
  /// dropped first.
  static String? whatsappNumber(String number, {String? country}) {
    final raw = number.trim();
    final d = digits(raw);
    if (raw.startsWith('+')) return d.length >= 8 ? d : null;
    if (raw.startsWith('00') && d.length > 10) return d.substring(2);
    final region =
        country ?? PlatformDispatcher.instance.locale.countryCode ?? '';
    final local = d.startsWith('0') ? d.substring(1) : d;
    if (region == 'IN' && local.length == 10) return '91$local';
    if (region == 'IN' && local.length == 12 && local.startsWith('91')) {
      return local;
    }
    return null;
  }

  /// WhatsApp chat with [number] and [text] typed in, or WhatsApp's own
  /// share picker when the number's country is unknown.
  static Uri whatsappUri(String number, String text, {String? country}) {
    final n = whatsappNumber(number, country: country);
    return Uri.parse(
      'https://wa.me/${n ?? ''}?text=${Uri.encodeComponent(text)}',
    );
  }

  /// An SMS to [number] with [text] in the box (the player still taps send).
  static Uri smsUri(String number, String text) {
    final n = number.replaceAll(RegExp(r'[^\d+]'), '');
    return Uri.parse('sms:$n?body=${Uri.encodeComponent(text)}');
  }
}
