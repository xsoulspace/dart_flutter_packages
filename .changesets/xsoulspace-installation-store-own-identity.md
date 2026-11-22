---
'xsoulspace_installation_store': minor
---

**Own the installation-target identity — no oka dependency (oka
ADR-0056).** `InstallationTargetStore` is no longer a typedef of oka's
`StoreKey`: it is this package's own validated string extension type
(`InstallationTargetStore('my-market')`, `isValidName`), with the
well-known targets as local constants and the display-label extension
unchanged. The oka re-exports (`StoreBinding`, `StoreKey`,
`NoopStoreBinding`) are removed — import oka packages from oka, store
names are strings here.
