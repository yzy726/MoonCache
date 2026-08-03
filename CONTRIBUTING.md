# Contributing

Contributions should stay within the boundaries in `docs/SCOPE.md` and preserve
the dependency direction in `docs/DESIGN.md`.

Before submitting a change, run:

```bash
moon info
moon fmt
moon check --deny-warn
moon test --deny-warn
```

For core changes, also check all portable targets:

```bash
moon check --target native --deny-warn
moon check --target js --deny-warn
moon check --target wasm-gc --deny-warn
```

Add stable assertion tests for well-defined results. Snapshot tests are reserved
for structured diagnostic output. New cache rules should identify the relevant
RFC section and use or add a stable `MC_*` reason code.

Keep MoonBit blocks small and separated by `///|`. Public API changes must be
intentional and visible in generated `.mbti` diffs.
