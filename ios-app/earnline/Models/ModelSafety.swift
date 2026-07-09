import SwiftData

extension PersistentModel {
    /// True once this model can no longer be read safely: it was deleted from
    /// its context (a sync pass applying a remote tombstone, a store reset)
    /// or already invalidated by the save that followed. SwiftUI views that
    /// hold a model directly can re-render once more inside that window — a
    /// preference update during the same transaction is enough — and any
    /// attribute getter then traps inside SwiftData ("backing data could no
    /// longer be found"). That trap was the switch-workspaces-twice crash.
    /// Views gate their body on this instead of reading doomed rows.
    ///
    /// `isDeleted` and `modelContext` only touch registration metadata, so
    /// unlike attribute getters they are safe on an invalidated instance.
    var isInvalidated: Bool {
        isDeleted || modelContext == nil
    }
}
