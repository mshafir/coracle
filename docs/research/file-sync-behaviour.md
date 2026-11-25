# How file syncers behave with live-edited files

Research for [issue #6](https://github.com/mshafir/coracle/issues/6). Written 2026-11-25.

This note supplies facts and trade-offs for the later ticket that decides the sync folder's layout and format. It does not make that decision.

**How to read the sourcing.** Every claim is followed by its source. Claims marked _(from memory)_ come from the author's background knowledge and were not checked against a source during this research. Claims marked _(secondary)_ come from a well-regarded third party, not the vendor. Section 10 lists what could not be verified at all.

## 1. Short answer

- **No file syncer merges.** iCloud Drive, Dropbox and Syncthing each pick a whole-file winner and set the loser aside. Only git merges text, and only when the person runs it.
- **Each syncer sets the loser aside differently.** Dropbox and Syncthing leave a sibling file with a recognisable name, which any app on macOS or Linux can see. git writes conflict markers into the file itself, so it stops parsing. iCloud Drive hides the loser in a version store that only Apple's `NSFileVersion` API can see, so a plain POSIX app never learns a conflict happened.
- **iCloud Drive has no Linux client** _(from memory)_. A person using a Mac and a Linux machine must use something else, so iCloud matters only for Mac-to-Mac.
- **Files in a cloud folder may not be on disk.** On macOS, iCloud Drive (and other File Provider syncers) can evict a file's contents. Reading it then blocks on a download, or fails when offline.
- **Write with temp file + fsync + atomic rename, and watch the directory, not the file.** Every syncer and editor examined replaces files by rename, which gives the file a new inode and breaks per-file watches.
- **The practices that prevent most trouble are about what is written and how often**, more than about the format: never rewrite a file whose contents have not changed, serialise deterministically, keep machine-specific and fast-changing values out, and give every item a stable ID.
- **Format shortlist: KDL, TOML, or JSON with comments.** YAML is the weakest fit. Section 8 has the comparison.

## 2. How each mechanism surfaces a conflict

| Mechanism | What happens to the losing version | Visible to a plain app on macOS | Visible to a plain app on Linux |
|---|---|---|---|
| iCloud Drive | Kept as a hidden conflict version, reached through `NSFileVersion`. A sibling "name 2.ext" appears only when two new files collide | Only through Foundation APIs | Not applicable: no client |
| Dropbox | Sibling file with "conflicted copy" in its name | Yes | Yes |
| Syncthing | Sibling file `name.sync-conflict-<date>-<time>-<device>.ext` | Yes | Yes |
| git | Conflict markers written into the file; nothing happens until the person merges | Yes (file fails to parse) | Yes (file fails to parse) |

### iCloud Drive

- **The loser becomes a conflict version, not a file.** "For files in the cloud, there is usually only one version of the file at any given time. However, additional file versions may be created in cases where two different computers attempt to save the file to the cloud at the same time. In that case, one file is chosen as the current version and any other versions are tagged as being in conflict with the original. Conflict versions are reported to the appropriate file presenter objects and should be resolved as soon as possible." ([NSFileVersion](https://developer.apple.com/documentation/foundation/nsfileversion))
- **Duplicate files appear only for new-file collisions.** When two devices create a file of the same name, iCloud Drive gives one a "bounced" name such as "abc 2.txt". This applies only to the Documents scope, and identical contents are not treated as a conflict. "iCloud Drive automatically creates new versions for all other conflicts." ([TN2336](https://developer.apple.com/library/archive/technotes/tn2336/_index.html), dated 2016)
- **Apple does not document how the winner is chosen.** TN2336 says only that iCloud "resolves them automatically by picking up a winning version and keeping the other changes in a losing version". A developer reported in 2025 that the current version differed between devices after a simultaneous edit ([forum thread 804253](https://developer.apple.com/forums/thread/804253), unanswered by Apple).
- **Losing versions persist until an app removes them.** "If you do not explicitly remove the versions that are no longer useful, they will continue to synchronize to all iCloud peers and consume the user's iCloud quota." ([TN2336](https://developer.apple.com/library/archive/technotes/tn2336/_index.html))
- **The APIs for seeing a conflict:**
  - `URLResourceKey.ubiquitousItemHasUnresolvedConflictsKey`: "whether this item has outstanding conflicts" ([docs](https://developer.apple.com/documentation/foundation/urlresourcekey/ubiquitousitemhasunresolvedconflictskey)).
  - `NSFileVersion.unresolvedConflictVersionsOfItem(at:)`: "an array of version objects that are currently in conflict" ([docs](https://developer.apple.com/documentation/foundation/nsfileversion)). Each has a readable URL.
  - `NSFilePresenter` callbacks `presentedItemDidGain(_:)` and `presentedSubitemDidChange(at:)`, plus the per-subitem version callbacks listed in TN2336, announce new versions.
  - After merging, mark versions resolved and call `removeOtherVersionsOfItem(at:)`.
- **A consequence for Coracle:** on macOS, without this Apple-only code path, an iCloud conflict looks like one machine's change silently vanishing.

### Dropbox

- **Sibling file, no merging.** "A conflicted copy is a file that Dropbox creates when multiple people edit the same file at the same time." "The editor's username, 'conflicted copy', and the save date will be added to the filename." "The last version saved will always appear as the conflicted copy." ([Dropbox help](https://help.dropbox.com/organize/conflicted-copy))
- **The name looks like** `space (Ada's conflicted copy 2026-11-25).ext` _(from memory; the help page describes the parts but gives no exact pattern)_.
- **It also fires when a file is merely held open.** One listed cause is "A file is left open on another user's computer, which Dropbox saves as a new edit" ([same page](https://help.dropbox.com/organize/conflicted-copy)).
- **Linux is supported**, on ext4, zfs, eCryptFS, xfs or btrfs, x86-64 only ([system requirements](https://help.dropbox.com/installs/system-requirements)).

### Syncthing

- **Sibling file, older edit loses.** "The file with the older modification time will be marked as the conflicting file and thus be renamed" to `<filename>.sync-conflict-<date>-<time>-<modifiedBy>.<ext>`. ([Syncthing: Understanding Synchronization](https://docs.syncthing.net/users/syncing.html))
- **Conflict files are synced like any other file**: "files are treated as normal files after they are created, so they are propagated between devices" ([same page](https://docs.syncthing.net/users/syncing.html)). Every machine sees them.
- **The number kept is configurable.** `maxConflicts` defaults to 10; `-1` is unlimited ([config docs](https://docs.syncthing.net/users/config.html)). Setting it to `0` disables conflict copies, so the loser is discarded _(from memory)_.
- **A deletion can beat a modification.** "If the conflict is between a modification and a deletion of the file, and the deletion wins", no conflict copy is made ([syncing docs](https://docs.syncthing.net/users/syncing.html)).
- **Because it depends on modification times**, clock skew between machines decides the winner.

### git

- **Nothing syncs until the person acts.** "Syncing isn't automatic. You must push and pull changes manually" is how Obsidian's docs put it ([Obsidian: sync your notes](https://obsidian.md/help/sync-notes)).
- **A conflict is written into the file.** The built-in `text` driver marks conflicted regions "with conflict markers `<<<<<<<`, `=======` and `>>>>>>>`" ([gitattributes](https://git-scm.com/docs/gitattributes)). A space file in that state is not valid in any candidate format.
- **git is the only mechanism that merges**, line by line, against a common ancestor. Non-overlapping edits to the same file merge cleanly. This is where format choice matters (section 8).
- **`merge=union` is not a shortcut.** It takes "lines from both versions, instead of leaving conflict markers. This tends to leave the added lines in the resulting file in random order" ([gitattributes](https://git-scm.com/docs/gitattributes)). Ordered tab lists would be scrambled, and deletions can be resurrected.
- **A custom merge driver is possible**: a command given the ancestor, ours and theirs, defined in git config, not in the repository ([gitattributes](https://git-scm.com/docs/gitattributes)). Each person would have to install it.
- **A clean line merge can still be semantically wrong**, for example the same tab ID in two folders. Loading must validate and repair.

## 3. Files that are not on disk (macOS)

- **A dataless file has metadata but no contents.** "A file that contains only metadata is known as a dataless file. The file's content typically resides on a remote server." ([TN3150](https://developer.apple.com/documentation/technotes/tn3150-getting-ready-for-data-less-files))
- **Reading one triggers a download and blocks.** Symptoms Apple lists: "Spins or hangs when performing file system operations" and "Time-out errors (`ETIMEDOUT`) when invoking file system APIs". Even enumerating a directory or calling `stat` can materialise dataless parent folders. ([TN3150](https://developer.apple.com/documentation/technotes/tn3150-getting-ready-for-data-less-files))
- **Detect without downloading** by checking `SF_DATALESS` in `st_flags` ([TN3150](https://developer.apple.com/documentation/technotes/tn3150-getting-ready-for-data-less-files); the flag is defined in the macOS SDK's `sys/stat.h`). The Foundation equivalent is `ubiquitousItemDownloadingStatusKey`, whose values are `current`, `downloaded` and `notDownloaded` ([docs](https://developer.apple.com/documentation/foundation/urlubiquitousitemdownloadingstatus)).
- **Ask for the download** with `FileManager.startDownloadingUbiquitousItem(at:)` ([docs](https://developer.apple.com/documentation/foundation/filemanager/startdownloadingubiquitousitem(at:))).
- **Eviction is real for iCloud Drive on a Mac.** With "Optimise Mac Storage" on, "the local copy of that file loses all its data, becoming a dataless file", and opening it re-downloads it ([Eclectic Light](https://eclecticlight.co/2024/03/18/how-icloud-drive-works-in-macos-sonoma/), _secondary_).
- **Other apps tell people to pin the folder.** Obsidian says keeping the vault downloaded is "strongly recommended", and that on macOS 14 and earlier this means turning Optimise Mac Storage off for the whole device ([Obsidian: sync your notes](https://obsidian.md/help/sync-notes)). Later macOS versions have a per-folder "Keep Downloaded" command _(from memory)_.
- **Dropbox on macOS has the same shape.** It now lives under `~/Library/CloudStorage` as a File Provider and supports online-only files _(from memory)_. Online-only files are reported as unavailable on Linux ([Dropbox forum](https://www.dropboxforum.com/discussions/101001014/when-will-online-only-files-work-on-linux/262171), _secondary, posts to about 2023_).
- **Syncthing and git have no placeholders.** Files are always whole on disk _(from memory)_.
- **Consequences for Coracle:**
  - A space file that cannot be read is not a deleted space. Show it as unavailable.
  - Read space files off the main thread, with a timeout.
  - Space files are tiny, so asking the person to keep the sync folder downloaded costs them nothing.

## 4. File coordination on macOS

- **Apple requires it for iCloud files.** "The use of file coordinators and presenters is mandatory when working with iCloud documents." "If you are not using document objects to access files, you must handle the file coordination yourself." ([iCloud Design Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/DesigningForDocumentsIniCloud.html), archived)
- **What it does.** A coordinated write waits "until all file presenters indicate that it is safe"; a coordinated read of an undownloaded file "blocks until the file finishes downloading (or fails to download)" ([same guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/DesigningForDocumentsIniCloud.html)). The sync daemon is one of the parties being coordinated with.
- **It is also the notification channel.** `NSFilePresenter` reports changes and version conflicts, but "Your presenter objects are not notified about changes made directly using low-level read and write calls to the file. Only changes that go through a file coordinator result in notifications." ([NSFilePresenter](https://developer.apple.com/documentation/foundation/nsfilepresenter))
- **It suppresses echoes of your own writes.** Creating the coordinator with your presenter "Prevents the file coordinator from sending messages to the file presenter. This means that the file presenter won't receive notifications about its own file operations", except version messages ([init(filePresenter:)](https://developer.apple.com/documentation/foundation/nsfilecoordinator/init(filepresenter:))).
- **Writing options to know:** `forReplacing` is for when "writing to the file involves actually replacing the file with a different file"; "Do not use this method when simply updating the contents of the existing file" ([docs](https://developer.apple.com/documentation/foundation/nsfilecoordinator/writingoptions/forreplacing)). `withoutChanges` on reads skips asking other presenters to save first ([docs](https://developer.apple.com/documentation/foundation/nsfilecoordinator/readingoptions/withoutchanges)).
- **What Apple does not say** is what happens when an app skips coordination. Neither TN2336 nor the design guide describes the failure. In practice plain POSIX tools do work inside iCloud Drive _(from memory)_; what is lost is the ordering guarantee against the sync daemon and all conflict visibility.
- **Trade-off for Coracle:** coordination and `NSFileVersion` are macOS-only. Supporting iCloud well means a macOS-specific storage path beside the portable one. Skipping it means iCloud conflicts are silent.

## 5. Safe write patterns

- **`rename` is the atomic step.** macOS: "The rename() system call guarantees that an instance of new will always exist, even if the system should crash in the middle of the operation" (`man 2 rename`, macOS 27). A reader therefore sees the old file or the new one, never half of each. The temp file must be on the same filesystem.
- **`fsync` the temp file before renaming**, or a crash can leave the new name pointing at empty contents _(from memory)_. On macOS plain `fsync` is weak: "the drive itself may not physically write the data to the platters for quite some time"; `F_FULLFSYNC` "asks the drive to flush all buffered data to permanent storage" (`man 2 fsync`, macOS 27). For a small settings file, losing the last edit on power loss is tolerable; a truncated file is not.
- **Foundation's equivalents:** `Data.write(options: .atomic)` writes "to an auxiliary file first and then replace[s] the original file" ([docs](https://developer.apple.com/documentation/foundation/nsdata/writingoptions/atomic)). `FileManager.replaceItemAt` replaces "in a manner that ensures no data loss occurs" and preserves creation date and permissions; pair it with `itemReplacementDirectory` to get a temp location on the right volume ([docs](https://developer.apple.com/documentation/foundation/filemanager/replaceitemat(_:withitemat:backupitemname:options:))).
- **Syncers use the same pattern on the receiving side.** "Syncthing never writes directly to a destination file. Instead all changes are made to a temporary copy which is then moved in place over the old version." ([syncing docs](https://docs.syncthing.net/users/syncing.html)). Coracle on the receiving machine therefore sees whole files from Syncthing. How Dropbox's and iCloud's daemons place incoming files is not documented.
- **Zed does exactly this for settings**: a `NamedTempFile` in the destination's own directory, then `persist` (a rename), with no fsync ([zed `crates/fs/src/fs.rs`, `atomic_write`](https://github.com/zed-industries/zed/blob/main/crates/fs/src/fs.rs)).

### Costs of atomic rename

- **The file gets a new inode on every save.** Per-file watches break (section 6). Hard links are severed and a symlinked space file is replaced by a regular file unless the path is resolved first _(from memory)_. Zed canonicalises the settings path before watching it ([zed `settings_file.rs`](https://github.com/zed-industries/zed/blob/main/crates/settings/src/settings_file.rs)). This matters to people who manage dotfiles with symlinks.
- **The temp file sits in the synced folder for a moment**, and a syncer may try to upload it. Known exclusions:

| Syncer | Names it skips | Source |
|---|---|---|
| Dropbox | Names starting `~$` or `.~`; `.DS_Store`, `desktop.ini`, `thumbs.db` | [Dropbox help](https://help.dropbox.com/sync/files-not-syncing) |
| iCloud Drive | Extensions `.nosync` and `.tmp`; names starting `~$`; `.DS_Store` | [Eclectic Light](https://eclecticlight.co/2026/01/06/exclude-or-include-items-in-backup-search-icloud-drive-and-quicklook-preview/), _secondary; Apple publishes no list_ |
| Syncthing | Only its own `.syncthing.` and `~syncthing~` prefixes, which apps must not use. Otherwise needs `.stignore`, which "will never be synced to other devices" | [syncing](https://docs.syncthing.net/users/syncing.html), [ignoring](https://docs.syncthing.net/users/ignoring.html) |
| git | Whatever `.gitignore` says | _(from memory)_ |

- **A temp name such as `.~<name>.tmp` would be skipped by Dropbox and iCloud on those rules.** This is an inference from the table and is untested.
- **Syncthing rarely sees a short-lived temp file anyway.** Its watcher "accumulates changes for 10s" before scanning ([syncing docs](https://docs.syncthing.net/users/syncing.html)).
- **An alternative is a temp directory outside the sync folder**, but only if it is on the same filesystem, which Coracle cannot assume.

### What to write, and how often

These follow from the behaviours above. They are inferences, not quoted guidance.

- **Do not write when nothing changed.** Compare the serialised bytes with what is on disk first. Otherwise two running machines can trade rewrites forever, and every needless write is a chance for a conflict.
- **Serialise deterministically.** The same layout must produce the same bytes on macOS and Linux: fixed key order, fixed indentation, LF endings, one trailing newline, UTF-8 without a byte-order mark.
- **Debounce.** Write once after a burst of edits, such as dragging several tabs. Syncthing batches over 10 seconds and Dropbox treats each save as a version.
- **Never overwrite a file that failed to parse.** It may be mid-sync, hold git conflict markers, or hold a hand-editing mistake. Keep the last good state in memory and tell the person.
- **Keep per-machine and fast-changing values out**, including "last active", timestamps and window state. This is already decided; it is what keeps write frequency low enough for file syncers to cope.

## 6. Watching for changes

### macOS: FSEvents

- **File-level events are opt-in.** `kFSEventStreamCreateFlagFileEvents`: "Your stream will receive events about individual files in the hierarchy you're watching instead of only receiving directory level notifications." (`FSEvents.h`, macOS 27 SDK)
- **Own writes can be filtered by the system.** `kFSEventStreamCreateFlagIgnoreSelf`: "Don't send events that were triggered by the current process." `kFSEventStreamCreateFlagMarkSelf` tags them with an "OwnEvent" flag instead. (`FSEvents.h`)
- **Events can be coalesced or dropped.** `kFSEventStreamEventFlagMustScanSubDirs`: "Your application must rescan not just the directory given in the event, but all its children, recursively." (`FSEvents.h`)
- **FSEvents can replay history** from a saved event ID, which covers changes made while the app was not running (`FSEvents.h`, `sinceWhen`).

### Linux: inotify

- **Watches follow the inode, not the name.** "Inotify monitoring is inode-based" ([inotify(7)](https://man7.org/linux/man-pages/man7/inotify.7.html)). After an atomic rename, a watch on the file itself is watching the dead inode. Watch the directory.
- **Not recursive.** "Inotify monitoring of directories is not recursive." ([inotify(7)](https://man7.org/linux/man-pages/man7/inotify.7.html))
- **No way to identify your own writes.** "The inotify API provides no information about the user or process that triggered the inotify event." ([inotify(7)](https://man7.org/linux/man-pages/man7/inotify.7.html))
- **Events can be lost.** "Note that the event queue can overflow", reported as `IN_Q_OVERFLOW`; identical events may be merged. ([inotify(7)](https://man7.org/linux/man-pages/man7/inotify.7.html))
- **Rename pairs are racy.** "Matching up the IN_MOVED_FROM and IN_MOVED_TO event pair generated by rename(2) is thus inherently racy." ([inotify(7)](https://man7.org/linux/man-pages/man7/inotify.7.html))
- **Blind on network filesystems.** "It does not catch remote events that occur on network filesystems"; applications "must fall back to polling" ([inotify(7)](https://man7.org/linux/man-pages/man7/inotify.7.html)). Zed's filesystem layer has a `requires_poll_watcher` check for this ([zed `fs.rs`](https://github.com/zed-industries/zed/blob/main/crates/fs/src/fs.rs)).
- **No history.** Changes made while Coracle was closed produce no events _(from memory)_.

### A watching approach that works on both

- **Watch the sync folder directory**, never individual files.
- **Treat every event as "something may have changed".** Debounce, re-read the affected file, and compare a hash of its contents with the hash Coracle last loaded or wrote. Act only on a real difference. This removes the need to recognise own writes at all, so it works on inotify, and it makes duplicate and reordered events harmless.
- **Rescan the whole folder** on launch, on wake from sleep, and on any overflow or must-rescan signal.
- **Expect an incoming file to be momentarily incomplete or absent.** Retry a failed parse after a short delay before reporting it.
- **Zed's settings watcher is this simple**: watch the path with 100 ms latency, and on any event reload the whole file ([zed `settings_file.rs`](https://github.com/zed-industries/zed/blob/main/crates/settings/src/settings_file.rs)).

## 7. How comparable apps handle it

- **Obsidian (vault of Markdown plus a `.obsidian` settings folder).**
  - Its own paid sync merges: Markdown with "Google's diff-match-patch algorithm"; settings by merging JSON, applying "keys from the local JSON on top of the remote JSON"; everything else last-modified-wins ([Obsidian Sync troubleshooting](https://obsidian.md/help/sync/troubleshoot)). This is an app-level merge that understands the format.
  - It can instead create `name (Conflicted copy device-name YYYYMMDDHHMM).md` ([same page](https://obsidian.md/help/sync/troubleshoot)).
  - It warns against two syncers on one folder: "Avoid syncing the same vault across multiple services" ([sync your notes](https://obsidian.md/help/sync-notes)).
  - For Syncthing it suggests excluding `.obsidian` "if you want separate settings on each device" ([same page](https://obsidian.md/help/sync-notes)).
  - Its `workspace.json`, which records open panes, is a well-known source of sync conflicts and is commonly git-ignored _(from memory)_. That is the mistake Coracle's durable-layout rule already avoids.
- **VS Code.**
  - Settings are a live `settings.json` in the user config folder ([settings docs](https://code.visualstudio.com/docs/configure/settings)), in JSON with comments _(from memory)_.
  - It does not rely on file syncers. Settings Sync is a dedicated service that "automatically merges your local and cloud data"; on conflict, "Synchronization pauses until you resolve the conflicts", with accept-local, accept-remote, or a three-way merge editor ([Settings Sync](https://code.visualstudio.com/docs/configure/settings-sync)).
  - Machine-scoped settings are excluded from sync ([same page](https://code.visualstudio.com/docs/configure/settings-sync)): a per-machine/per-person split inside one schema.
  - An invalid file blocks writes: "Unable to write into user settings. Please open user settings to correct errors/warnings in it and try again." ([settings docs](https://code.visualstudio.com/docs/configure/settings)). That is the "never overwrite what you cannot parse" rule.
- **Zed.** Live JSON-with-comments settings, watched and reloaded on any change, written by temp file plus rename (sources in sections 5 and 6). No built-in sync of the file.
- **Logseq.** The official docs could not be fetched. Forum reports, including from staff, describe duplicate files and missed change events with iCloud, and races when two machines run at once ([forum guide](https://discuss.logseq.com/t/how-to-sync-your-logseq-graph-across-devices/8462), _secondary_). Its newer database mode is not suited to git or Syncthing per a staff reply ([forum](https://discuss.logseq.com/t/syncing-logseq-db/31285), _secondary_).
- **Arc.** The sidebar is one undocumented JSON file, `~/Library/Application Support/Arc/StorableSidebar.json`, known only through third-party exporters ([arc-export](https://github.com/ivnvxd/arc-export), _secondary_). Arc syncs through its own accounts _(from memory)_.
- **Zen.** Spaces and pinned tabs are in `zen-sessions.jsonlz4` in the profile, which is compressed JSON and not hand-editable; community tools exist to copy it between machines ([zen-sync](https://github.com/enisbu/zen-sync), [discussion #8182](https://github.com/zen-browser/desktop/discussions/8182), _secondary_).
- **Pattern across these:** the apps that sync well either run their own merging service (Obsidian Sync, VS Code) or keep files small, separate and slow-changing and accept whole-file conflicts. No sidebar browser examined offers a hand-editable, file-synced layout.

## 8. Formats

### What makes diffs and merges clean

Line-based merging happens only in git. For iCloud, Dropbox and Syncthing these properties still help a person compare a conflict copy by eye, and help Coracle merge one itself.

- **One item per line or per block, with no separator between siblings.** In strict JSON, appending to a list edits the previous line too (to add a comma), so two machines that each append a pinned tab produce a git conflict. Formats with no separators, or with a trailing comma always written, avoid this.
- **Stable order of keys.** TOML, JSON5 and YAML all define mappings as unordered ([TOML](https://toml.io/en/v1.0.0), [JSON5](https://spec.json5.org/), [YAML 1.2.2](https://yaml.org/spec/1.2.2/)). The order on disk is the writer's choice, so Coracle must fix one.
- **A stable ID on every space, folder and pinned tab.** It lets a merge match items across versions when a title or URL changed, gives the diff unique lines to anchor on, and lets validation catch duplicates after a merge.
- **Order of items is meaningful and should stay positional.** Tabs appear in file order. Reordering then shows as moved lines. Explicit position numbers would make every reorder touch many lines and are unpleasant to hand-edit.
- **No derived or volatile fields.** No modification timestamps, counters or "last opened".
- **Duplicate keys should fail loudly.** A line merge can leave the same key twice. TOML: "Defining a key multiple times is invalid" ([spec](https://toml.io/en/v1.0.0)). JSON5 leaves behaviour open ([spec](https://spec.json5.org/)), and most JSON parsers silently keep the last _(from memory)_.

### The rewrite problem

Coracle rewrites these files whenever the layout changes. A person's comments and formatting survive only if the writer edits the existing text instead of regenerating it. That needs a format-preserving library, or a decision that comments are not kept. This matters more than syntax. Format-preserving libraries exist for TOML (`toml_edit`), KDL (`kdl-rs`) and JSON with comments (the `jsonc-parser` edit API used by VS Code) _(all from memory; availability depends on the implementation language, which is undecided)_.

### Comparison

| Format | Comments | Siblings need separators | Fit for a tree of folders and tabs | Hand-editing hazards | Notes |
|---|---|---|---|---|---|
| JSON | No | Yes, and no trailing comma | Natural | Quotes and commas everywhere; one missing comma breaks the file | Universal parsers. Worst for append merges |
| JSON with comments (JSONC) | Yes | Yes; trailing commas tolerated by some parsers only | Natural | Same as JSON, slightly softened | No formal specification _(from memory)_. Familiar from VS Code and Zed |
| JSON5 | Yes | Yes; "Objects and arrays can end with one trailing comma" | Natural | Fewer: unquoted keys, single quotes | [Spec](https://spec.json5.org/). Fewer libraries and editor support than JSON _(from memory)_ |
| TOML | Yes (`#`) | No: each `[[item]]` is its own block | Awkward beyond one level. Nested lists of tables need long dotted headers; inline tables "are intended to appear on a single line" | Low for flat settings; nesting confuses people | [Spec 1.0](https://toml.io/en/v1.0.0). Rejects duplicate keys. Good for the settings file |
| YAML | Yes (`#`) | No | Natural | High: "structure is determined by indentation", tabs forbidden, and unquoted values can change type | [Spec 1.2.2](https://yaml.org/spec/1.2.2/). A bad merge can shift indentation and still parse, silently re-parenting items _(from memory)_ |
| KDL | Yes (`//`, `/* */`, and `/-` to disable a node) | No: one node per line | Natural: a node with children is a folder | Low. Booleans are `#true`/`#false` in v2, which surprises newcomers | [Spec 2.0.0](https://kdl.dev/spec/), released 2024-12-21. Node and argument order is preserved; properties "SHOULD NOT be assumed to be presented in a given order". Smallest ecosystem; v1 and v2 differ |

### Trade-offs between the three strongest

- **KDL** reads most like the sidebar it describes: a `folder` node containing `tab` nodes, one per line, with no separators. Best diffs and merges of the group. The cost is a young ecosystem: fewer parsers, less editor support, and a recent breaking version change.
- **TOML** is the most widely known and the most forgiving for a flat settings file, and it fails loudly on duplicate keys. It handles one level of list well and becomes hard to read at folders-within-folders.
- **JSON with comments (or JSON5)** has the best tooling and is what VS Code and Zed users expect. It has the noisiest syntax for hand-editing and the worst append-merge behaviour, unless the writer always emits trailing commas, which then rules out strict JSON parsers.
- **Mixing is an option**: one format for the settings file and another for space files. The cost is two parsers and two things to learn.

## 9. Conflict handling Coracle could do itself

These are options the facts allow, for the later ticket to weigh.

- **Detect conflict siblings by name** in the sync folder: `*.sync-conflict-*` (Syncthing), `* conflicted copy *` (Dropbox), and "name 2.ext" (iCloud new-file collision). The last pattern is ambiguous with a file a person named that way.
- **Do not load conflict siblings as extra spaces.** With stable IDs inside the file, a sibling carrying the same space ID as another file is recognisably a conflict, whatever its name.
- **Offer a merge.** With stable item IDs, two versions of a space can be combined item by item.
- **A two-way merge cannot tell an addition from a deletion.** If one machine has a tab the other lacks, either it was added there or deleted here. Resolving that needs the common ancestor. Coracle could keep its own last-synced copy of each space file outside the sync folder, per machine, to serve as the ancestor. git supplies the ancestor itself.
- **On macOS with iCloud**, the same merge would be fed from `NSFileVersion` conflict versions.

## 10. What could not be verified

- **Whether `NSFileVersion` reports conflicts to an app that has no iCloud entitlement** and is simply pointed at a folder inside the person's iCloud Drive. Apple's documentation is written for apps with their own iCloud container. Needs a test on two Macs.
- **How iCloud Drive treats temp-file-plus-rename writes made without file coordination**: whether it uploads cleanly as a new version, briefly as a delete and create, or occasionally produces a "name 2" duplicate. User reports of spurious "2" files exist ([Apple Community](https://discussions.apple.com/thread/256016012), _secondary_). Needs a test.
- **How iCloud picks the winning version.** Undocumented.
- **iCloud's list of names it will not sync.** Only third-party lists exist; it may change between macOS versions.
- **How Dropbox's and iCloud's daemons write incoming files** (in place or by rename), and so whether a reader can observe a partial file. Syncthing documents that it renames.
- **How Dropbox reacts to rename-over-existing**, and its exact conflicted-copy filename pattern.
- **Current state of Dropbox online-only files on Linux.** The evidence found is forum posts up to about 2023.
- **TN2336 is from 2016** and predates the File Provider rewrite of iCloud Drive in macOS Sonoma. Its conflict model matches the current `NSFileVersion` documentation, but details may have shifted.
- **Logseq's and Arc's own documentation** could not be read; those entries rest on secondary sources.
- **Library availability for each format** was not checked, because the implementation language is not yet chosen.
- **Not examined:** OneDrive, Google Drive, Nextcloud, Resilio, and network filesystems, which a person could also point the sync folder at.
