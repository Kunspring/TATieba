import 'package:tieba_app/utils/tieba_cuid.dart';

void main() {
  const expected = {
    '0000000000000000': 'C77D5D04D94F5F56C8A0A6DC3DBF240A|VQKEKVL4O',
    'ffffffffffffffff': 'A1739C95D4AD1271F31F292F0EF635AF|VCFXHVF73',
    '1234567890abcdef': '55724A640ECA9DEEDF46E9067AEA0E42|VRVPL7RL2',
    'a1b2c3d4e5f60708': 'C3823E54CE34DBC3B2DA563059971063|VJUUU2OAC',
    '91be894d01799c49': '661CB8A33975DB28AD2F7D15F09E3CF0|VEDCZQMYE',
  };
  var failed = 0;
  for (final entry in expected.entries) {
    final got = TiebaCuid.cuidGalaxy2(entry.key);
    if (got == entry.value) {
      print('${entry.key}: OK');
    } else {
      failed++;
      print('${entry.key}: FAIL');
      print('  want: ${entry.value}');
      print('  got:  $got');
    }
  }
  if (failed > 0) {
    throw StateError('$failed cuid vector(s) failed');
  }
}
