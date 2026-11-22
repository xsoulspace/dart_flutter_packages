---
'xsoulspace_monetization_foundation': minor
---

**Store name is a plain String — no oka dependency (oka ADR-0056).**

`MonetizationStoreBinding.key` is now a `String` (lowercase store
identifier: `google-play`, `rustore`, `appgallery`, …) and
`storeNameNoop = 'noop'` replaces the imported `storeKeyNoop`. The
package no longer depends on `oka_store`: monetization and oka are
separate ecosystems that join on the store-NAME contract (oka bakes
`OKA_STORE=<name>` into a delivery build; the app boot verifies its
binding carries the same name), never on a shared type. BREAKING for
binding implementors that typed `key` as oka's `StoreKey` — return the
name string instead.
