# ADR 0003: URL, WebVPN Crypto, Cookie and Session Dependencies

Date: 2026-08-17

Status: accepted

The connection layer uses `url` for standards-based absolute and relative URL resolution and `aes` for the AES-128 block primitive required by the frozen BUAA WebVPN AES/CFB/NoPadding host encoding. The CFB chaining is kept in the narrow WebVPN codec module and covered by round-trip and protocol-segment tests. `httpdate` parses the standard `Expires` Cookie attribute.

The project does not use a browser Cookie store because the Core must serialize, inspect and test the exact filtering policy independent of a host. The custom jar covers the contract's host-only/domain, path, Secure, Max-Age, Expires and replacement rules. It intentionally does not expose Cookie values through logging APIs.

Session persistence uses standard-library files, an advisory sidecar lock, unique exclusively-created temporary files, and an atomic rename. Each fully buffered session JSON document is capped at 1 MiB; this is an internal safety budget, not an upstream protocol limit. Writes are flushed and synchronized before replacement, and failed writes remove their temporary file. The JSON schema remains unchanged. On Unix it enforces 0700 for the configuration directory and 0600 for the session and lock files. Symlinks and non-regular configuration/session targets are rejected before access. Passwords and usernames are not part of the serialized type.

The response transport has a separate 8 MiB cap for fully buffered authentication and User Center bodies and rejects oversized known-length or streamed responses before exposing them to parsers. Larger future business payloads require a dedicated streaming port rather than increasing this authentication safety budget.

Windows does not receive an owner-only ACL from the standard library permission APIs used here. The application therefore relies on the inherited ACL of the user-selected configuration directory, exercises replacement and locking in the Windows CI matrix, and keeps a release audit item for custom configuration directories.
