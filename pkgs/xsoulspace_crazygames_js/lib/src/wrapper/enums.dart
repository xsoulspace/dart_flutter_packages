
enum Environment {
  crazygames('crazygames'),
  local('local'),
  disabled('disabled'),
  unknownValue('__unknown__');

  const Environment(this.value);
  final String value;

  static Environment fromValue(final String? value) {
    if (value == null) return unknownValue;
    for (final item in values) {
      if (item.value == value) return item;
    }
    return unknownValue;
  }
}

enum AdType {
  midgame('midgame'),
  rewarded('rewarded'),
  unknownValue('__unknown__');

  const AdType(this.value);
  final String value;

  static AdType fromValue(final String? value) {
    if (value == null) return unknownValue;
    for (final item in values) {
      if (item.value == value) return item;
    }
    return unknownValue;
  }
}

enum AdblockPopupState {
  open('open'),
  unknownValue('__unknown__');

  const AdblockPopupState(this.value);
  final String value;

  static AdblockPopupState fromValue(final String? value) {
    if (value == null) return unknownValue;
    for (final item in values) {
      if (item.value == value) return item;
    }
    return unknownValue;
  }
}

enum PaymentProvider {
  xsolla('xsolla'),
  unknownValue('__unknown__');

  const PaymentProvider(this.value);
  final String value;

  static PaymentProvider fromValue(final String? value) {
    if (value == null) return unknownValue;
    for (final item in values) {
      if (item.value == value) return item;
    }
    return unknownValue;
  }
}

enum DeviceType {
  desktop('desktop'),
  tablet('tablet'),
  mobile('mobile'),
  unknownValue('__unknown__');

  const DeviceType(this.value);
  final String value;

  static DeviceType fromValue(final String? value) {
    if (value == null) return unknownValue;
    for (final item in values) {
      if (item.value == value) return item;
    }
    return unknownValue;
  }
}

enum ApplicationType {
  googlePlayStore('google_play_store'),
  appleStore('apple_store'),
  pwa('pwa'),
  web('web'),
  unknownValue('__unknown__');

  const ApplicationType(this.value);
  final String value;

  static ApplicationType fromValue(final String? value) {
    if (value == null) return unknownValue;
    for (final item in values) {
      if (item.value == value) return item;
    }
    return unknownValue;
  }
}

enum AccountLinkAnswer {
  yes('yes'),
  no('no'),
  unknownValue('__unknown__');

  const AccountLinkAnswer(this.value);
  final String value;

  static AccountLinkAnswer fromValue(final String? value) {
    if (value == null) return unknownValue;
    for (final item in values) {
      if (item.value == value) return item;
    }
    return unknownValue;
  }
}
