/// Normalizes a South African phone number to E.164 format (+27...).
///
/// Accepts:
///   - "0821234567"       -> "+27821234567"
///   - "082 123 4567"     -> "+27821234567"
///   - "27821234567"      -> "+27821234567"
///   - "+27821234567"     -> "+27821234567"
///   - "+27 82 123 4567"  -> "+27821234567"
///
/// Returns null if the input can't be interpreted as a valid SA mobile number.
String? normalizeSaPhone(String raw) {
  // Strip everything that isn't a digit or leading +.
  final cleaned = raw.replaceAll(RegExp(r'[^\d+]'), '');
  if (cleaned.isEmpty) return null;

  String digits;
  if (cleaned.startsWith('+27')) {
    digits = cleaned.substring(3);
  } else if (cleaned.startsWith('27') && cleaned.length == 11) {
    digits = cleaned.substring(2);
  } else if (cleaned.startsWith('0')) {
    digits = cleaned.substring(1);
  } else {
    return null;
  }

  // SA mobile subscriber number is 9 digits after the country/trunk code.
  if (digits.length != 9) return null;
  if (!RegExp(r'^\d{9}$').hasMatch(digits)) return null;

  return '+27$digits';
}