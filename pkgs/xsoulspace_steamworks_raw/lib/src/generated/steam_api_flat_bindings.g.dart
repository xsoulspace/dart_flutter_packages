// GENERATED CODE - DO NOT MODIFY BY HAND.

library;

import 'dart:ffi';

base class CallbackMsg_t extends Struct {
  @Int32()
  external int m_hSteamUser;

  @Int32()
  external int m_iCallback;

  external Pointer<Uint8> m_pubParam;

  @Int32()
  external int m_cubParam;
}

base class SteamAPICallCompleted_t extends Struct {
  @Uint64()
  external int m_hAsyncCall;

  @Int32()
  external int m_iCallback;

  @Uint32()
  external int m_cubParam;
}
