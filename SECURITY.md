# Security Policy

## Reporting a vulnerability

Please report a security problem privately, not in a public issue:

- **[Report it on GitHub](https://github.com/TheIdeaPlace/ParallelsManager/security/advisories/new)**
  (private vulnerability reporting), or
- email **kelly@theideaplace.net**.

Include what you found, how to reproduce it, and what it could affect. You'll hear back within a
few days.

## What's worth knowing

Parallels Manager runs `prlctl` (Parallels Desktop's command-line tool) and, for New Ubuntu VM and
New Windows VM, an install script in Terminal. It isn't sandboxed, because the sandbox forbids
running other programs.

- **Passwords.** New Ubuntu VM's password goes to the install script in a file only you can read,
  in a private temporary folder; the script deletes it as soon as it has read it, and stores only
  a SHA-512 hash in the new VM.
- **Downloads.** The Ubuntu installer comes from Ubuntu's own servers over HTTPS and is checked
  against Ubuntu's published SHA-256 checksums before it's used.
- **SSH.** A new Ubuntu VM gets your Mac's SSH *public* keys (`~/.ssh/*.pub`) so you can sign in to
  it. Private keys never leave your Mac.
- **Releases** are signed with Developer ID and notarized by Apple, and each comes with a SHA-256
  checksum.

## Supported versions

Only the latest release gets fixes.
