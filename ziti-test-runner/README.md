# ziti-test-runner

End-to-end integration test tool for the CZiti Swift SDK. Drives real enrollment
and context bring-up against a live Ziti controller, returning a pass/fail exit
code suitable for CI.

Used by the CI workflow (`.github/workflows/CI.yml`) against a
`ziti edge quickstart` controller.

## What it does

**Default mode** - enroll, save, load, run, verify:

1. Enrolls a Ziti identity from a one-time JWT file (OTT by default)
2. Saves the resulting identity to a `.zid` file
3. Loads the identity back from the `.zid` file via `Ziti(fromFile:)`
4. Runs the Ziti context
5. Waits for a `ContextEvent` with status OK (auth success)
6. Waits for a `ServiceEvent` with at least one service (service channel works)
7. Exits 0

**`--only-run` mode** - load an existing `.zid` file and verify auth+services,
no enrollment. Useful for verifying persistence across process boundaries.

## Usage

```
ziti-test-runner [options] <jwt-file>             # enroll, save, load, run, verify
ziti-test-runner --only-run [options] <zid-file>  # load an existing zid and run
```

Options:
- `--mode <ott|cert-jwt|token-jwt>` - enrollment mode (default: `ott`)
- `--timeout <seconds>` - total test timeout (default: 60)
- `--keep-zid <path>` - keep the enrolled `.zid` at this path
- `--log-level <level>` - `WTF|ERROR|WARN|INFO|DEBUG|VERBOSE|TRACE` (default: `INFO`)
- `--only-run` - input is a `.zid` file; skip enrollment

Exit codes:
- `0` - success
- `1` - enrollment failed
- `2` - identity load / run failed
- `3` - context status != OK, service timeout, or overall timeout
- `64` - usage error

## Building with the insecure-keys test flag

macOS enrollment in this SDK uses the data protection keychain
(`kSecUseDataProtectionKeychain = true` in `ZitiKeychain.createPrivateKey()`),
which requires a provisioning-profile-backed `application-identifier`
entitlement. Ad-hoc signed CLI tools don't have that, so enrollment fails with
`errSecMissingEntitlement` (-34018) - both in CI and on dev machines using
"Sign to Run Locally".

To work around this **in test builds only**, the SDK supports the compile-time
condition `CZITI_TEST_INSECURE_KEYS`. When set:

- `ZitiKeychain.createPrivateKey()` generates an ephemeral RSA key with no
  keychain interaction.
- `Ziti.enroll()` skips `storeCertificate()` in the keychain and writes the
  ephemeral private key PEM into `ZitiIdentity.key` instead.
- `Ziti.run()` prefers `id.key` if present, over calling
  `ZitiKeychain.getPrivateKey()`.
- A one-shot `⚠️ CZITI_TEST_INSECURE_KEYS build` warning prints to stderr the
  first time a key is minted in the process.

**This flag must never be used in a release build.** Keys end up in plaintext
in the `.zid` file on disk, with none of the OS-level isolation the keychain
provides.

### Command-line usage

```bash
xcodebuild build -scheme ziti-test-runner \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) CZITI_TEST_INSECURE_KEYS'
```

The flag propagates to the `CZiti-macOS` dependency automatically (xcodebuild
applies command-line build settings across the whole build graph).

### Running locally

```bash
# 1. Start a quickstart
ziti edge quickstart --home /tmp/qs &

# 2. Log in and create an identity + service + dial policy
ziti edge login localhost:1280 -u admin -p admin -y
ziti edge create identity ztr -a ztr -o /tmp/ztr.jwt
ziti edge create service ztr-svc -a ztr-svc
ziti edge create service-policy ztr-dial Dial \
  --identity-roles '#ztr' --service-roles '#ztr-svc'

# 3. Run the tool (built with the flag)
./DerivedData/CZiti/Build/Products/Debug/ziti-test-runner /tmp/ztr.jwt
```

## Scope

Only OTT enrollment is exercised end-to-end. The `cert-jwt` and `token-jwt`
modes compile under the flag but aren't wired through CI because:

- `Ziti.enrollToCert(jwtFile:)` / `enrollToToken(jwtFile:)` use the OIDC flow,
  which can't be driven non-interactively in CI without a mock JWT signer.
- The `runEnrollTo(mode:)` path in `lib/Ziti.swift` has a keychain retag step
  (`retagPrivateKey(to:)`) that isn't bracketed by `CZITI_TEST_INSECURE_KEYS`
  and would likely fail under the flag.

Fixing either is a legitimate follow-up.
