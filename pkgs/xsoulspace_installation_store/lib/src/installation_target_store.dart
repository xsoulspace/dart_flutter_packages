/// The installation target store as an **open key** (ADR-0055 lineage in
/// the oka repo).
///
/// This used to be a closed `enum` — which locked the store list into
/// this package: every developer targeting a store it never heard of had
/// to send a PR. The identity is now oka's open `StoreKey` (a validated
/// string extension type): a new store is a new key value composed by the
/// project, never a package change. Nothing switches on these names.
///
/// ```dart
/// const myStore = StoreKey('my-market'); // works everywhere
/// final binding = MyStoreBinding();      // implements StoreBinding
/// if (monetizationStoreTarget == storeKeyRuStore) { ... }
/// ```
library;

import 'package:oka_store/oka_store.dart';

export 'package:oka_store/oka_store.dart'
    show NoopStoreBinding, StoreBinding, StoreKey;

/// The installation target store identity — an alias of oka's open key,
/// kept for existing import sites.
typedef InstallationTargetStore = StoreKey;

/// Human-friendly labels for well-known stores (display only; nothing
/// switches on these, and unknown keys fall back to the raw name).
extension InstallationTargetStoreLabel on StoreKey {
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

/// Well-known installation targets (convenience only — see
/// `oka_store` for the fuller set; both are open sets).

/// The Google Play installation target.
const installationTargetGooglePlay = storeKeyGooglePlay;

/// The Apple App Store installation target.
const installationTargetAppleAppStore = storeKeyAppleStore;

/// The RuStore installation target.
const installationTargetRuStore = storeKeyRuStore;

/// The Huawei AppGallery installation target.
const installationTargetHuawei = storeKeyAppGallery;
