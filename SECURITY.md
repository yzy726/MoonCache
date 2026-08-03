# Security policy

HTTP caches can expose one user's response to another user when cacheability or
variant rules are wrong. Security reports should therefore avoid public issue
details until a fix is available.

Until a private reporting address is published, open a GitHub security advisory
for the repository owner. Include a minimal deterministic reproduction without
real credentials or personal data.

The `0.1.x` line is pre-stable. Security fixes target the latest `0.1.x`
release. The project does not claim production reverse-proxy suitability.

Important invariants include:

- never store `no-store` responses;
- never reuse `Vary: *`;
- reject private responses in a shared cache;
- protect shared caches from authorized-request disclosure;
- distinguish missing and empty `Vary` request fields;
- redact Authorization, Cookie, Proxy-Authorization, and Set-Cookie values;
- saturate age arithmetic and never produce a negative age.

The integration trust boundaries and maintainer responsibilities are documented
in [docs/SECURITY_MODEL.md](docs/SECURITY_MODEL.md).
