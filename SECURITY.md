# Security Policy

Do not submit passwords, cookies, tokens, authorization headers, captcha images, raw authentication responses, or complete personal records. `.env.local`, runtime state, live artifacts, and reference repositories are ignored by design.

The CLI must read passwords through hidden terminal input or standard input and must never accept a plaintext password argument. Session files contain only cookies, connection mode, and non-secret timestamps, and are restricted to the current user. Logs and normal output must redact phone and identity-card values.

TLS verification is mandatory. Report vulnerabilities privately to the repository maintainers rather than attaching sensitive reproduction data to a public issue.

