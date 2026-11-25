# Coracle

The language of Coracle, a local-first sidebar browser: how a person's tabs are organised, isolated and stored.

## Language

**Space**:
A named, themed set of tabs that a person switches between as a unit. Every space uses exactly one profile.
_Avoid_: Workspace, tab set, context

**Profile**:
One isolated set of cookies, logins and site data. Several spaces may share a profile.
_Avoid_: Account, identity, container

**Pinned tab**:
A tab a person has chosen to keep in a space. It never expires and is part of the space's durable layout.
_Avoid_: Bookmark, favorite

**Unpinned tab**:
A tab that is open in a space but not kept. It is subject to expiry and belongs only to the machine it was opened on.
_Avoid_: Temporary tab, today tab

**Expiry**:
The automatic removal of an unpinned tab after a configured period.
_Avoid_: Archiving, auto-close, cleanup

**Space file**:
The single file that is a space: its name, appearance, profile link and durable layout. Opening a space file opens that space.
_Avoid_: Export, workspace file

**Durable layout**:
The arrangement a person deliberately keeps: settings, spaces, folders, pinned tabs and appearance. It is what the sync folder holds.
_Avoid_: Config, state

**Sync folder**:
The folder on disk that holds the durable layout, which a person may point at any file-syncing mechanism of their choosing.
_Avoid_: Cloud, backup, store
