# Background synchronization and local startup

The homepage opens local notes immediately. `SyncStatusOverlay` only loads or
migrates the saved profile; Dartloom owns startup, activation, polling, retries,
and local-write triggers. The app no longer starts a second manual sync or waits
for the network before showing notes. Manual retry preserves the mounted page.
Failure messages follow the current snapshot and disappear after success.
Downloaded or remotely deleted documents refresh the visible notes.

`syncSnapshotProvider` subscribes before publishing the current snapshot, so runs
started before the UI mounts and subsequent state changes are both visible.

Two fixes are applied in the local Dartloom packages, selected through ordinary
dependency overrides:

- `dartloom_sync_etag` skips GET when both the remote ETag and the local payload
  hash match the last reconciliation. A changed remote version, a missing local
  file, or an external local edit still fetches the remote data.
- `dartloom_sync_webdav` shares successful/in-flight MKCOL requests within one
  pass. Each new pass verifies the root again, and failed requests are removed
  from the cache. Uploading 32 sibling attachments takes 4 collection requests
  instead of 131.

App regressions are covered by `test/sync_startup_test.dart`. Package regressions
live in `dartloom_sync_etag/test/etag_sync_test.dart` and
`dartloom_sync_webdav/test/webdav_replica_test.dart` in the sibling Dartloom repo.
