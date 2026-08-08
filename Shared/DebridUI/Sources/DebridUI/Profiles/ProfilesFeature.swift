/// The profiles feature is **temporarily switched off**, not removed.
///
/// With it off there is no "Who's Watching?" gate at launch, no profile row in the tvOS side menu,
/// no avatar on iPhone Home, no chip in the iPad sidebar, and no Profile section in either
/// Settings screen. The app resolves silently to the oldest profile — the owner row
/// `ProfileStore.ensureOwnerProfileAndMigrate` creates on first launch — so watch history, Continue
/// Watching, resume positions, ratings and My List all keep the profile id they already use.
///
/// Everything behind those surfaces is still compiled and still syncs: `WhoIsWatchingScreen`,
/// `AddProfileScreen`, the roster, CloudKit. **Set this to `true` and the whole feature returns**,
/// with every profile and its history intact. That is the only edit required.
public enum ProfilesFeature {
    public static let isEnabled = false
}
