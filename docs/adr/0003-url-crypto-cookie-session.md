# ADR 0003: URL, WebVPN Crypto, Cookie and Session Dependencies

Date: 2026-08-17

Status: accepted

The connection layer uses `url` for standards-based absolute and relative URL resolution and `aes` for the AES-128 block primitive required by the frozen BUAA WebVPN AES/CFB/NoPadding host encoding. The CFB chaining is kept in the narrow WebVPN codec module and covered by round-trip and protocol-segment tests. `httpdate` parses the standard `Expires` Cookie attribute.

The project does not use a browser Cookie store because the Core must serialize, inspect and test the exact filtering policy independent of a host. The custom jar covers the contract's host-only/domain, path, Secure, Max-Age, Expires and replacement rules. It intentionally does not expose Cookie values through logging APIs.

Session persistence uses standard-library files and atomic rename. On Unix it enforces 0700 for the configuration directory and 0600 for `session.json`. Passwords and usernames are not part of the serialized type.
