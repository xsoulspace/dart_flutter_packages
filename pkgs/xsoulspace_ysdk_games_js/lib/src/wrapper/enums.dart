// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: @types/ysdk@1.2.0

library;

enum FeedbackError {
  game_rated('GAME_RATED'),
  no_auth('NO_AUTH'),
  review_already_requested('REVIEW_ALREADY_REQUESTED'),
  unknown('UNKNOWN'),
  unknownValue('__unknown__');

  const FeedbackError(this.value);
  final String value;

  static FeedbackError fromValue(final String? value) {
    if (value == null) return unknownValue;
    for (final item in FeedbackError.values) {
      if (item.value == value) return item;
    }
    return unknownValue;
  }
}

enum StickyAdvError {
  adv_is_not_connected('ADV_IS_NOT_CONNECTED'),
  unknown('UNKNOWN'),
  unknownValue('__unknown__');

  const StickyAdvError(this.value);
  final String value;

  static StickyAdvError fromValue(final String? value) {
    if (value == null) return unknownValue;
    for (final item in StickyAdvError.values) {
      if (item.value == value) return item;
    }
    return unknownValue;
  }
}

enum SdkEventName {
  exit('EXIT'),
  history_back('HISTORY_BACK'),
  unknownValue('__unknown__');

  const SdkEventName(this.value);
  final String value;

  static SdkEventName fromValue(final String? value) {
    if (value == null) return unknownValue;
    for (final item in SdkEventName.values) {
      if (item.value == value) return item;
    }
    return unknownValue;
  }
}

enum ISO_639_1 {
  af('af'),
  am('am'),
  ar('ar'),
  az('az'),
  be('be'),
  bg('bg'),
  bn('bn'),
  ca('ca'),
  cs('cs'),
  da('da'),
  de('de'),
  el('el'),
  en('en'),
  es('es'),
  et('et'),
  eu('eu'),
  fa('fa'),
  fi('fi'),
  fr('fr'),
  gl('gl'),
  he('he'),
  hi('hi'),
  hr('hr'),
  hu('hu'),
  hy('hy'),
  id('id'),
  isValue('is'),
  it('it'),
  ja('ja'),
  ka('ka'),
  kk('kk'),
  km('km'),
  kn('kn'),
  ko('ko'),
  ky('ky'),
  lo('lo'),
  lt('lt'),
  lv('lv'),
  mk('mk'),
  ml('ml'),
  mn('mn'),
  mr('mr'),
  ms('ms'),
  my('my'),
  ne('ne'),
  nl('nl'),
  no('no'),
  pl('pl'),
  pt('pt'),
  ro('ro'),
  ru('ru'),
  si('si'),
  sk('sk'),
  sl('sl'),
  sr('sr'),
  sv('sv'),
  sw('sw'),
  ta('ta'),
  te('te'),
  tg('tg'),
  th('th'),
  tk('tk'),
  tl('tl'),
  tr('tr'),
  uk('uk'),
  ur('ur'),
  uz('uz'),
  vi('vi'),
  zh('zh'),
  zu('zu'),
  unknownValue('__unknown__');

  const ISO_639_1(this.value);
  final String value;

  static ISO_639_1 fromValue(final String? value) {
    if (value == null) return unknownValue;
    for (final item in ISO_639_1.values) {
      if (item.value == value) return item;
    }
    return unknownValue;
  }
}

enum TopLevelDomain {
  az('az'),
  by('by'),
  co_il('co.il'),
  com('com'),
  com_am('com.am'),
  com_ge('com.ge'),
  com_tr('com.tr'),
  ee('ee'),
  fr('fr'),
  kg('kg'),
  kz('kz'),
  lt('lt'),
  lv('lv'),
  md('md'),
  ru('ru'),
  tj('tj'),
  tm('tm'),
  ua('ua'),
  uz('uz'),
  unknownValue('__unknown__');

  const TopLevelDomain(this.value);
  final String value;

  static TopLevelDomain fromValue(final String? value) {
    if (value == null) return unknownValue;
    for (final item in TopLevelDomain.values) {
      if (item.value == value) return item;
    }
    return unknownValue;
  }
}

enum DeviceType {
  desktop('desktop'),
  mobile('mobile'),
  tablet('tablet'),
  tv('tv'),
  unknownValue('__unknown__');

  const DeviceType(this.value);
  final String value;

  static DeviceType fromValue(final String? value) {
    if (value == null) return unknownValue;
    for (final item in DeviceType.values) {
      if (item.value == value) return item;
    }
    return unknownValue;
  }
}

