# MoonCache

MoonCache is a transport-independent, explainable HTTP cache policy and
runtime toolkit for MoonBit. It models the HTTP caching lifecycle described by
RFC 9111 without implementing an HTTP protocol stack.

The `0.1.0` acceptance target covers:

- normalized request, response, header, and time models;
- private/shared cacheability and freshness decisions;
- corrected age calculation and conservative overflow handling;
- `Vary` variants and normalized cache keys;
- ETag/Last-Modified revalidation and `304 Not Modified` merging;
- an HTTP-specific in-memory store;
- a transport-independent runtime with deterministic fake transports;
- stable reason codes, text/JSON traces, and a scenario CLI.

## Status

The repository is being implemented milestone by milestone. The public API is
not considered stable before the `0.1.0` acceptance milestone is complete.

## Quick start

```bash
moon check --deny-warn
moon test --deny-warn
moon run cmd/main -- explain examples/scenarios/basic-cache.json
```

The library never reads the system clock in its policy core. Callers supply all
request, response, storage, and evaluation timestamps, which keeps tests and
cross-target behavior deterministic.

## Design

- [Scope and boundaries](docs/SCOPE.md)
- [Architecture and dependency rules](docs/DESIGN.md)
- [Upstream specifications and references](REFERENCES.md)
- [AI-assisted development record](AI_USAGE.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)

## License

Apache-2.0. See [LICENSE](LICENSE).
