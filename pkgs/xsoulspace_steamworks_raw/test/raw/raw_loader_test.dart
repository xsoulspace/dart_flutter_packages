import 'dart:ffi';

import 'package:test/test.dart';
import 'package:xsoulspace_steamworks_raw/xsoulspace_steamworks_raw.dart';

void main() {
  test('library naming by OS is deterministic', () {
    expect(
      SteamRawLibraryLoader.libraryNamesFor(SteamDesktopPlatform.windows),
      equals(const <String>['steam_api64.dll', 'steam_api.dll']),
    );
    expect(
      SteamRawLibraryLoader.libraryNamesFor(SteamDesktopPlatform.macos),
      equals(const <String>['libsteam_api.dylib']),
    );
    expect(
      SteamRawLibraryLoader.libraryNamesFor(SteamDesktopPlatform.linux),
      equals(const <String>['libsteam_api.so']),
    );
  });

  test('library loader expands explicit directories using platform names', () {
    final loader = SteamRawLibraryLoader(
      platformOverride: SteamDesktopPlatform.windows,
      librarySearchPaths: const <String>['/tmp/custom-steam'],
    );

    final candidates = loader.candidateLibraryPaths();
    expect(candidates, contains('/tmp/custom-steam/steam_api64.dll'));
    expect(candidates, contains('/tmp/custom-steam/steam_api.dll'));
  });

  test('load maps missing binaries to libraryNotFound', () {
    final loader = SteamRawLibraryLoader(
      platformOverride: SteamDesktopPlatform.linux,
      librarySearchPaths: const <String>['/path/that/does/not/exist'],
    );

    expect(
      () => loader.load(),
      throwsA(
        isA<SteamRawException>().having(
          (final e) => e.code,
          'code',
          SteamRawErrorCode.libraryNotFound,
        ),
      ),
    );
  });

  test('missing symbol maps to symbolNotFound', () {
    final bindings = SteamRawBindings.fromResolver(_MissingSymbolResolver());

    expect(
      () => bindings.restartAppIfNecessary(480),
      throwsA(
        isA<SteamRawException>()
            .having(
              (final e) => e.code,
              'code',
              SteamRawErrorCode.symbolNotFound,
            )
            .having(
              (final e) => e.symbol,
              'symbol',
              'SteamAPI_RestartAppIfNecessary',
            ),
      ),
    );
  });
}

final class _MissingSymbolResolver implements SteamRawSymbolResolver {
  @override
  Pointer<T> lookup<T extends NativeType>(final String symbolName) {
    throw ArgumentError('Missing symbol: $symbolName');
  }
}
