/// Unsupported platforms do not advertise POSIX file-state authority.
bool get supportsPosixFileState => false;

void writePosixStage(
  String path,
  String content,
  int mode, {
  void Function()? onPrivateBytes,
}) => throw UnsupportedError('POSIX file state unavailable');
