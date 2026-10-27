/// Later-phase switches stay disabled until their owning modules provide the UI and persistence.
public enum HomeFutureFeatures {
    // TODO(Q6-05): P1 favorites and an optional combined Up Next row.
    public static let favoritesRowEnabled = false
    public static let combinedUpNextEnabled = false
    // TODO(Q6-06): P1 row order/visibility settings, then P2 server DisplayPreferences.
    public static let customRowOrderEnabled = false
    public static let serverDisplayPreferencesEnabled = false
    // TODO(Q6-08): M11 supplies the P1 iOS layout; the shared screen remains buildable.
    public static let iOSTouchLayoutEnabled = false
}
