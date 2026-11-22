/// The installation target store as an **open key**.
///
/// This used to be a closed `enum` — which locked the store list into
/// this package: every developer targeting a store it never heard of had
/// to send a PR. The identity is now [InstallationTargetStore], a
/// validated string extension type owned HERE (oka ADR-0056 dependency
/// law: a store-adjacent package must not depend on oka store packages
/// just to name a store): a new store is a new key value composed by the
/// project, never a package change. Nothing switches on these names.
///
/// ```dart
/// const myStore = InstallationTargetStore('my-market'); // works everywhere
/// if (monetizationStoreTarget == installationTargetRuStore) { ... }
/// ```
library;

/// The installation target store identity: a lowercase identifier
/// (`google-play`, `rustore`, `appgallery`, `apple-store`, …).
///
/// Erasure caveat: the value IS its [String] at runtime — the type is
/// static only, and `==` compares name values.
extension type const InstallationTargetStore(String name) {
  /// The name pattern for store keys: lowercase identifiers, digits,
  /// dashes, underscores.
  static final RegExp namePattern = RegExp(r'^[a-z][a-z0-9_-]*$');

  /// Whether [name] is a valid store key.
  static bool isValidName(String name) => namePattern.hasMatch(name);
}

/// Human-friendly labels for well-known stores (display only; nothing
/// switches on these, and unknown keys fall back to the raw name).
extension InstallationTargetStoreLabel on InstallationTargetStore {
  /// Display label for the store key.
  String get label => switch (name) {
    'google-play' => 'Google Play',
    'apple-store' => 'App Store',
    'rustore' => 'RuStore',
    'appgallery' => 'Huawei AppGallery',
    'samsung-store' => 'Samsung Galaxy Store',
    'amazon-appstore' => 'Amazon Appstore',
    'snapstore' => 'Snap Store',
    'windows-store' => 'Microsoft Store',
    _ => name,
  };
}

/// Well-known installation targets (convenience only — the set stays
/// open: compose your own [InstallationTargetStore] value).

/// The Google Play installation target.
const installationTargetGooglePlay = InstallationTargetStore('google-play');

/// The Apple App Store installation target.
const installationTargetAppleAppStore = InstallationTargetStore('apple-store');

/// The RuStore installation target.
const installationTargetRuStore = InstallationTargetStore('rustore');

/// The Huawei AppGallery installation target.
const installationTargetHuawei = InstallationTargetStore('appgallery');
