import Foundation

/// Preloaded Supabase connection details shipped with the app, one project per
/// environment. Production and Test each have their own Supabase database so a
/// test write can never land in the production project. These seed the editable
/// fields in Settings on first launch (per environment); whatever the user
/// types afterwards wins and is stored per environment in `UserDefaults`.
///
/// Publishable keys are safe to embed in the client — they only grant the
/// row-level access the workspace RLS policies allow. Never ship a service_role
/// key here.
enum SupabaseProjectDefaults {
    struct ProjectConfig {
        let url: String
        let publishableKey: String
    }

    static let production = ProjectConfig(
        url: "https://qpjfaapipwjultzvuxrm.supabase.co",
        publishableKey: "sb_publishable_c7mz4q_q12pX2RksZqd2zg_Bh7soeV0"
    )

    static let test = ProjectConfig(
        url: "https://djbddfxdmorslzsnkpxd.supabase.co",
        publishableKey: "sb_publishable_oMUEtoV8lkomkOHwGn33WA_Upo3YTFX"
    )
}
