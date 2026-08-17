# Contributing

Use focused branches and conventional, reviewable commits. Every behavior change starts with a failing test and includes its contract or migration documentation update.

Before opening a review, run `just refs` and `just check`. Authentication changes also require the explicit local live gates; CI never receives real credentials.

Fixtures must use unmistakably synthetic identities and placeholder Cookie/token values. Never derive fixtures by committing raw upstream responses. Preserve only the minimal protocol shape and scan staged changes for account data, credentials, cookies, tokens, and captcha content.

Add future campus capabilities behind `ubaa-core` feature/facade boundaries. Document their authoritative old implementation and tests in the migration status before implementation. Hosts must not call upstream modules directly.

