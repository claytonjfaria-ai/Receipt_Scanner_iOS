import Foundation

/// Supabase project URL + anon key, injected via XcodeGen's `${VAR}` substitution in
/// `project.yml` (see the comment there) rather than a bundled plist — `xcodegen generate`
/// reads these from the shell environment at generate time, matching the Android app's
/// `local.properties` → `BuildConfig` pattern (main plan's Secrets management section).
///
/// When the environment variable was never set — every CI build, and any local build before
/// `export SUPABASE_URL=... SUPABASE_ANON_KEY=...` has been run — XcodeGen leaves the literal
/// placeholder string in the Info.plist rather than failing (confirmed behavior, not assumed;
/// this is why `isPlaceholder` exists rather than trusting any non-empty string).
enum Secrets {
    static var supabaseURL: URL? {
        guard let raw = value(for: "SUPABASE_URL"), let url = URL(string: raw) else { return nil }
        return url
    }

    static var supabaseAnonKey: String? {
        value(for: "SUPABASE_ANON_KEY")
    }

    /// True once both values are present and look real — used to show a clear
    /// "not configured" state instead of a confusing network failure.
    static var isConfigured: Bool {
        supabaseURL != nil && supabaseAnonKey != nil
    }

    private static func value(for key: String) -> String? {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
            !raw.isEmpty,
            !isPlaceholder(raw)
        else { return nil }
        return raw
    }

    /// An unsubstituted `${VAR}` left by XcodeGen when the environment variable wasn't set.
    private static func isPlaceholder(_ value: String) -> Bool {
        value.hasPrefix("${") && value.hasSuffix("}")
    }
}
