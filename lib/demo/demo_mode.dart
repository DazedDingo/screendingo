/// Demo-mode build flag and constants.
///
/// Set at compile time with `--dart-define=DEMO_MODE=true`. When enabled:
/// - The router treats every user as signed-in (no Firebase Auth call).
/// - All Firestore-coupled providers in `lib/providers/` are overridden
///   with hardcoded mock data from [demoData] (see `demo_data.dart`).
/// - Firebase still initializes (cheap, doesn't hit the network for the
///   call itself) so any code that touches `FirebaseAuth.instance` or
///   `FirebaseFirestore.instance` defensively doesn't throw, but no
///   real reads/writes hit Google's servers because the providers that
///   would do them are overridden upstream.
///
/// Used by the GitHub Actions `screenshots.yml` workflow to build a
/// marketing-grade APK with curated household state, run it on an
/// emulator, and capture Play Store screenshots without any auth
/// flow or backend dependency.
const bool kDemoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: false);

/// Synthetic uid for the "viewer" in demo mode. Hardcoded so providers
/// that filter by current uid (e.g. ratings.where(uid == X), per-user
/// solo scores) resolve to a real user in the curated data set.
const String kDemoUid = 'demo_uid_alex';

/// The "partner" uid in the demo household. Pair with [kDemoUid] for
/// "Together" mode rendering — the data set populates ratings and
/// watch history under both uids so the Stats screen + household
/// counters show non-empty values.
const String kDemoPartnerUid = 'demo_uid_jamie';

/// Synthetic household id. Most Firestore-coupled providers gate on
/// `householdIdProvider.value != null` — the demo override returns
/// this constant.
const String kDemoHouseholdId = 'demo_household_1';
