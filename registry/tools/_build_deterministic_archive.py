#!/usr/bin/env python3
import argparse
import gzip
import json
import os
import stat
import tarfile


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package-dir", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--manifest", required=True)
    return parser.parse_args()


def _tarinfo_for(path_on_disk: str, archive_name: str) -> tarfile.TarInfo:
    st = os.lstat(path_on_disk)
    info = tarfile.TarInfo(name=archive_name)
    info.uid = 0
    info.gid = 0
    info.uname = ""
    info.gname = ""
    info.mtime = 0
    info.mode = stat.S_IMODE(st.st_mode)

    if stat.S_ISLNK(st.st_mode):
      info.type = tarfile.SYMTYPE
      info.linkname = os.readlink(path_on_disk)
      info.size = 0
      return info

    if stat.S_ISREG(st.st_mode):
      info.size = st.st_size
      return info

    raise RuntimeError(f"Unsupported file type for archive: {archive_name}")


def main() -> int:
    args = _parse_args()
    with open(args.manifest, "r", encoding="utf-8") as fh:
        files = json.load(fh)
    if not isinstance(files, list) or not all(isinstance(item, str) for item in files):
        raise RuntimeError("Manifest must be a JSON array of file paths.")

    files = sorted(files)
    os.makedirs(os.path.dirname(args.output), exist_ok=True)

    with open(args.output, "wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as gz:
            with tarfile.open(fileobj=gz, mode="w", format=tarfile.GNU_FORMAT) as tar:
                for relative_path in files:
                    path_on_disk = os.path.join(args.package_dir, relative_path)
                    tar_info = _tarinfo_for(path_on_disk, relative_path)
                    if tar_info.isreg():
                        with open(path_on_disk, "rb") as source:
                            tar.addfile(tar_info, source)
                    else:
                        tar.addfile(tar_info)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
