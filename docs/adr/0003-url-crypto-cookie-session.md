# ADR 0003: URL, WebVPN Crypto, Cookie and Session Dependencies

Date: 2026-08-17

Status: accepted

The connection layer uses `url` for standards-based absolute and relative URL resolution and `aes` for the AES-128 block primitive required by the frozen BUAA WebVPN AES/CFB/NoPadding host encoding. The CFB chaining is kept in the narrow WebVPN codec module and covered by round-trip and protocol-segment tests. `httpdate` parses the standard `Expires` Cookie attribute.

The project does not use a browser Cookie store because the Core must serialize, inspect and test the exact filtering policy independent of a host. The custom jar covers the contract's host-only/domain, path, Secure, Max-Age, Expires and replacement rules. It intentionally does not expose Cookie values through logging APIs.

Session persistence uses standard-library file/locking APIs, the Unix `O_NOFOLLOW` flag exposed by `libc`, the corresponding standard-library Windows reparse-point flag, unique exclusively-created temporary files, and atomic same-directory replacement. Each fully buffered session JSON document is capped at 1 MiB; this is an internal safety budget, not an upstream protocol limit. Writes are flushed and synchronized before replacement, failed writes remove their temporary file, and existing session files are restricted again when opened. The `session.json` schema remains unchanged. On Unix the implementation enforces 0700 for the configuration directory and 0600 for session/lock files. Symlinks and non-regular configuration/session targets are rejected before access. Passwords and usernames are not part of the serialized type.

The advisory `.session.lock` file also stores a fixed-width hexadecimal monotonic revision. Snapshot plus revision are read while holding the lock. Every runtime save/clear compare-exchanges the loaded revision, synchronizes the incremented revision first, then replaces or removes `session.json`. Synchronizing the revision first deliberately prefers a recoverable false conflict after a crash over allowing a stale write; it also prevents an equal-snapshot ABA after delete/recreate. Unconditional `SessionStore::save` and `clear` remain convenience operations implemented as retrying CAS loops, while `ClientRuntime` uses the exact revision and returns a fixed retryable internal error on conflict.

The response transport has a separate 8 MiB cap for fully buffered authentication and User Center bodies and rejects oversized known-length or streamed responses before exposing them to parsers. Larger future business payloads require a dedicated streaming port rather than increasing this authentication safety budget.

Windows does not receive an owner-only ACL from the standard library permission APIs used here. The application therefore relies on the inherited ACL of the user-selected configuration directory, exercises replacement and locking in the Windows CI matrix, and keeps a release audit item for custom configuration directories. The lock remains advisory against non-cooperating writers. Revision CAS protects local persistence only; remote logout concurrency is not inferred from these file guarantees.
