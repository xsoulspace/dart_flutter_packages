@dart_dev.mdc

Hi! Let's create a plan.

I'm exploring the idea is to create dart_package to save / get / restore file based on git systems and usual file systems.

Basically it should work well for office applications and games.

# How it should work

API should be clear (for developer as user):

- init/auth save provider (GitHub (for start), File System (for start), GitLab (next))
- create/update/get/delete file (implementation: init repo with the project or create folder where user choose, where the file will be saved, commit / save on change, resolve as client is always right)

# how it will be used:

Case 1:
Imagine notes like project, where every note is document which should be saved. Note = file. Settings = file.

Case 2:
Imagine budget app, which have sophisticated collection of records (separate files per account / user) + helper file for quick savings. Should be started / restored from single source of truth (files per account, file with short settings) so any data won't be corrupted.

Case 3:
Imagine a game, which should be started / restored from single source of truth: Game Save = File, Settings = File.

# Tech stack:

Dart, should be cross platform (iOS, Android, web, macOS, Linux, Windows)
