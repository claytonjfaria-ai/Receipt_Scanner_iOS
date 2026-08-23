# Receipt Scanner — Bills (iOS)

The real native iOS Bills-capture app described in [`PLAN-MOBILE-BILLS-CAPTURE.md` §8](../Receipt_Scanner/PLAN-MOBILE-BILLS-CAPTURE.md) — not
[`dev/iOs_Test`](../iOs_Test) (`BillsCaptureTest`), which is a throwaway proof that the
GitHub Actions → unsigned `.ipa` → iLoader/SideStore build-and-sideload pipeline actually
works (confirmed 2026-08-18). This repo is the product; that one stays as infrastructure
proof and a reference for the setup steps below.

Two separate codebases by design (plan §8: "two separate codebases, no code reuse" —
KMP was rejected). This mirrors nothing from the Android `Receipt_Scanner` repo's Kotlin;
Swift/SwiftUI only.

## Status

**Milestone 3, part 2 — Drive OAuth sign-in, confirmed working end to end
2026-08-23.** Capture (VisionKit → durable on-device PDF, plan §4.1) → review + a real
`extract-bill` call (plan §4.2, §4.3) → Drive sign-in, all device-tested together in one
real session: a scanned Citi bill correctly extracted company/amount/date
(`Citi`/`148.61`/date all correct), and "Connect Google Drive" completed a real Google
OAuth consent flow and returned "Connected." First real evidence any of `extract-bill`,
Supabase sign-in, or Drive OAuth actually work on iOS, not just that they compile.

**What's still a stand-in, on purpose:** Review's Save does **not** file to Drive yet — it
persists confirmed company/amount/billing-date to a local JSON sidecar
(`BillMetadataStore`) next to the staged PDF, visible in the "Saved, not yet filed" section
on the main Bills screen. Being connected to Drive and actually filing into it are two
separate pieces; only sign-in is built. The folder picker and the real upload (plan §4.4's
remaining piece — the part that would move a bill into `Scans/<Company>/`) are next.

Getting to this point took three real on-device bugs, each caught by an actual sign-in/
connect attempt rather than by CI (which can't drive a live OAuth consent screen or a
Supabase login):
1. **CI builds were permanently stuck at "not configured"** — `secrets.env` only helps on a
   machine that can run `xcodegen`/`xcodebuild` locally, and there's no local Mac, so CI was
   the *only* build path and had no real secrets. Fixed by moving `SUPABASE_URL`/
   `SUPABASE_ANON_KEY` into this repo's own GitHub Actions secrets instead.
2. **"Connect Google Drive" silently killed the app**, straight to the Home Screen, no
   error. Root cause: `presentationAnchor(for:)` used an unconditional
   `DispatchQueue.main.sync`, which self-deadlocks when (as here) the framework calls it
   already on the main thread — the app hangs, iOS's watchdog kills it, and that looks
   exactly like the app just closing.
3. **The first fix attempt didn't compile** — a plain `nonisolated` on the helper function
   wasn't enough, since `UIApplication.shared` is itself `@MainActor`-isolated in current
   SDKs. `MainActor.assumeIsolated` is the actual purpose-built escape hatch for "this
   synchronous callback is known to run on the main thread, but the type system can't
   verify that statically."

Build order from here, matching the Android build order in the main plan:

1. ~~Capture — VisionKit → local PDF~~ (milestone 1)
2. ~~Review screen + `extract-bill` call~~ (milestone 2)
3. Drive OAuth (**sign-in confirmed working 2026-08-23**) + filing (folder picker, real
   upload — not yet built)
4. PII redaction (plan §4.7)
5. Reliability tiers (plan §4.6) — currently just Tier 1 (durable local save) and a partial
   Tier 2 (bounded retry on extraction); no Tier 3 persist-until-filed yet, since there's
   nothing to file to

## Bundle-ID stability — resolved 2026-08-23

Sideloading (SideStore, free Apple ID) rewrites this app's bundle ID at install time —
`com.tap2know.receiptscanner.bills` becomes `com.tap2know.receiptscanner.bills.XXXXXXXXXX`
with a suffix that isn't knowable until after the first install. That mattered because a
Google OAuth client is bound to a bundle identifier: if the suffix regenerated on every
reinstall or every 7-day certificate refresh, the OAuth client would have needed
re-creating just as often.

First tested on `BillsCaptureTest` (`dev/iOs_Test`), not this app directly — same signing
account and sideloading path, so the result was expected to transfer. A SideStore-managed
reinstall left `BillsCaptureTest`'s bundle ID unchanged, and — stronger evidence than the
string match — a `UserDefaults`-backed counter survived the reinstall too, which only
happens if iOS treated it as a continuation of the same app rather than a fresh install
with its own empty data container. Full result: `dev/iOs_Test/docs/iPad-iPhone-Setup.md`
§9/§11.

**Confirmed directly on this app, same day.** Sideloaded via the same SideStore pipeline
and read off the sign-in screen's Diagnostics section:

```
com.tap2know.receiptscanner.bills.7HKHVWJDHC
```

The suffix, `7HKHVWJDHC`, is **identical** to `BillsCaptureTest`'s — settling the one
nuance the `BillsCaptureTest`-only result couldn't: the suffix is tied to the **signing
account**, not computed per-app. Every app sideloaded with this same free Apple ID gets
this same suffix, not a fresh random one each time. This is the value to register as an
iOS-type OAuth client in Google Cloud Console.

## Why this exists before Android Bills is formally "trusted"

The plan's own §7 sequencing says iOS comes after Android Bills ships and is trusted —
and the golden-set validation run for `extract-bill` (10 samples, 80% field accuracy)
that establishes "trusted" hadn't been run as of this repo's creation. Built in parallel
anyway, by explicit choice — the golden set is still a real open item, tracked in the
main plan, not silently dropped.

## Building

**CI is the only real build path — there's no local Mac.** Every build that matters comes
from `.github/workflows/ios-build.yml` on a GitHub Actions macOS runner, triggered by a
push or `workflow_dispatch`. Real Supabase credentials are supplied there via this repo's
own **Actions secrets** (`Settings → Secrets and variables → Actions`: `SUPABASE_URL`,
`SUPABASE_ANON_KEY`) — **not** `secrets.env`, which only helps on a machine that can run
`xcodegen`/`xcodebuild` locally. Get this wrong once already, 2026-08-23: an early version
of this doc assumed a local-build fallback existed and pointed at `secrets.env` as "the"
way to get a working build — every CI `.ipa` was silently stuck at "not configured" until
this was fixed. Safe to bake real values into a public-repo CI build: `SUPABASE_ANON_KEY`
is designed to be public-safe (RLS is the real access boundary), and `SUPABASE_URL` is
just a project identifier, same reasoning already established for Android's own
`BuildConfig`-embedded anon key.

`secrets.env`/`secrets.env.example` are kept for the hypothetical case of building on an
actual Mac someday:

```bash
brew install xcodegen      # macOS only
cp secrets.env.example secrets.env   # fill in real values, then:
source secrets.env
export BUILD_NUMBER=0      # any value — CI uses its own run number instead
xcodegen generate
xcodebuild -project ReceiptScannerBills.xcodeproj -scheme ReceiptScannerBills \
  -configuration Release -sdk iphoneos -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
```

## Versioning

`MARKETING_VERSION` (currently `0.1.0`, in `project.yml`) is the human milestone marker,
bumped by feel — same split the main plan uses for Android's `versionName`. The build
number (`CURRENT_PROJECT_VERSION`) is never hand-set: CI sets it to the GitHub Actions run
number automatically, so every CI build gets a real, unique, monotonically-increasing
number with no bookkeeping. The packaged `.ipa`'s filename embeds both
(`ReceiptScannerBills-0.1.0-b47-unsigned.ipa`), read back from the actual built app rather
than recomputed — so the file on disk, the artifact on GitHub, and the Version row on the
sign-in screen's Diagnostics section always agree on exactly what build you're looking at.

In practice this runs on a GitHub Actions macOS runner (`.github/workflows/ios-build.yml`,
`workflow_dispatch` or push to `main`) — no local Mac needed. Sign and install the
resulting unsigned `.ipa` via iLoader/SideStore following
[`dev/iOs_Test/docs/iPad-iPhone-Setup.md`](../iOs_Test/docs/iPad-iPhone-Setup.md), which is
the tested procedure, not a sketch.

`Support/Info.plist` is generated by `xcodegen` from `project.yml` — never hand-edited,
never committed.

## Bundle ID

`com.tap2know.receiptscanner.bills` as declared in `project.yml` — a placeholder in the
sense that sideloading rewrites it on-device with a random suffix (plan §4.4's iOS
caveat), and the real Drive OAuth client can't be registered until that rewritten value
is known and confirmed stable across reinstalls (open item, plan §8).
