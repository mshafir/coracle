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
A tab a person has chosen to keep in a space. It never expires, has a home URL and is part of the space's durable layout.
_Avoid_: Bookmark, favorite

**Home URL**:
The address a pinned tab or favorite was kept at and returns to. Browsing away from it does not change it.
_Avoid_: Pinned URL, original URL

**Asleep**:
The state of a pinned tab or favorite whose page is not loaded. It stays in the sidebar and wakes at its home URL.
_Avoid_: Closed, unloaded, suspended, discarded

**Folder**:
A named container for pinned tabs inside a space. A folder may contain other folders. Folders hold only pinned tabs; unpinned tabs are never grouped.
_Avoid_: Group, tab group, collection

**Favorite**:
A kept site shown at the top of every space that uses the same profile. It belongs to the profile, not to any one space, and is a single tab shared by those spaces.
_Avoid_: Top site, shortcut, bookmark

**Window**:
A view onto one space at a time. Several windows may show the same space; they show the same tabs, each with its own selected tab.
_Avoid_: Instance, session

**Unpinned tab**:
A tab that is open in a space but not kept. It belongs to the space rather than to any window, is subject to expiry, and exists only on the machine it was opened on.
_Avoid_: Temporary tab, today tab

**Expiry**:
The automatic removal of an unpinned tab after a configured period.
_Avoid_: Archiving, auto-close, cleanup

**Space file**:
The single file that is a space: its name, appearance, profile link and durable layout. Opening a space file opens that space.
_Avoid_: Export, workspace file

**Durable layout**:
The arrangement a person deliberately keeps: settings, spaces, folders, pinned tabs, favorites and appearance. It is what the sync folder holds.
_Avoid_: Config, state

**Sync folder**:
The folder on disk that holds the durable layout, which a person may point at any file-syncing mechanism of their choosing.
_Avoid_: Cloud, backup, store
