# Network folders

Network folders appear in the sidebar's **Locations** section. Which servers you use is personal, so it
lives in `~/Library/Application Support/LocalSearch/settings.json`, outside the repository, and is never
committed. The sidebar also lists any network or external volume that is already mounted, with
**Eject / Disconnect** on its right-click menu.

```json
{
  "network_locations": [
    { "title": "NAS", "kind": "smb", "url": "smb://nas.example/share" },
    { "title": "Pi",  "kind": "ssh", "host": "pi", "path": "" }
  ]
}
```

A configured location is dimmed until it is connected. Clicking it connects and opens it in the current tab.
The file is re-read whenever the app is brought to the front.

## SMB (a NAS, a Windows share)

Nothing to install. The app asks macOS to mount `smb://host/share`; if a password is needed, macOS shows
its usual sign-in dialog and can save it in your keychain. The share appears under `/Volumes`.
Connecting gives up after 15 seconds if the server doesn't answer.

## SSH (a Raspberry Pi, any Linux box)

macOS cannot mount a folder over SSH by itself. This needs **FUSE-T** (a FUSE layer that does not use a
kernel extension) and its **sshfs**.

### 1. Install (once per Mac, needs your administrator password)

```bash
brew tap macos-fuse-t/cask
brew trust macos-fuse-t/cask        # Homebrew 7 asks you to trust third-party taps
brew install --cask fuse-t fuse-t-sshfs
```

Run it in a normal Terminal window: the installers ask for your password. If macOS then asks you to allow
the software in System Settings › Privacy & Security, allow it and run the command again.
The app looks for `sshfs` in `/opt/homebrew/bin` and `/usr/local/bin`.

### 2. Describe the machine in ~/.ssh/config (required)

An SSH location's `host` must be a `Host` alias in `~/.ssh/config`; ssh supplies the user, key and port,
so they aren't repeated in `settings.json`. The sidebar shows only the hosts you add, not every line of
the config: use **Go › Add SSH Location** to pick from the config's hosts.

```
Host pi
    HostName pi.example.local
    User me
    IdentityFile ~/.ssh/id_ed25519
```

The app can't type a password, so key login must work: `ssh -o BatchMode=yes pi true && echo ok`
(set it up with `ssh-copy-id pi`). `path` is the remote folder to mount (empty = the home folder).

### 3. Connect

Click the location in the sidebar. The folder is mounted at
`~/Library/Application Support/LocalSearch/mnt/<title>` and opens in the tab. Right-click › **Disconnect**
unmounts it. Connecting gives up after 25 seconds; the yellow bar then shows why (it re-runs a plain `ssh` to find out).

### Troubleshooting

- *"SSH folders need sshfs"*: step 1 hasn't been done, or `sshfs` is somewhere else.
- *"isn't a Host in ~/.ssh/config"*: add the alias in step 2.
- *"Permission denied"*: key login isn't set up for that host.
- *Stuck mount*: `umount ~/Library/Application\ Support/LocalSearch/mnt/<title>` (or `diskutil unmount force …`).
