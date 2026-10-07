/// Explicit entrypoint for the local Laya decision server adapter.
///
/// Importing the package's default chat barrel does not expose or construct
/// this adapter. The adapter speaks the System One wire against a local
/// `laya-serve` (or compatible) endpoint on this machine.
library;

export 'src/laya_server_decision_provider.dart';
