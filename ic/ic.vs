package ic

import (
    "js/object"
    "js/value"
)

/// CacheEntry caches a known Shape and its slot index.
public struct CacheEntry {
    public let CachedShape: object.Shape
    public let Slot: int

    public init(shape: object.Shape, slot: int) {
        self.CachedShape = shape
        self.Slot = slot
    }
}

/// FeedbackState represents the state of an inline cache site.
public enum FeedbackState: Equatable {
    case uninitialized
    case monomorphic
    case polymorphic
    case megamorphic
}

/// FeedbackSlot tracks property access shapes at a specific bytecode site.
public final class FeedbackSlot {
    public var State: FeedbackState = .uninitialized
    public var Entries: [CacheEntry] = []

    public init() {}

    /// Lookup returns the slot offset if the shape is cached.
    public func Lookup(_ shape: object.Shape) -> int? {
        for entry in Entries {
            if entry.CachedShape === shape {
                return entry.Slot
            }
        }
        return nil
    }

    /// Update records a new shape transition at this call site.
    public func Update(shape: object.Shape, slot: int) {
        if State == .megamorphic {
            return
        }
        for entry in Entries {
            if entry.CachedShape === shape {
                return
            }
        }
        if Entries.isEmpty {
            State = .monomorphic
            Entries.append(CacheEntry(shape: shape, slot: slot))
        } else if Entries.count < 4 {
            State = .polymorphic
            Entries.append(CacheEntry(shape: shape, slot: slot))
        } else {
            State = .megamorphic
            Entries.removeAll()
        }
    }
}

/// FeedbackVector holds all feedback slots for a function.
public final class FeedbackVector {
    public var Slots: [FeedbackSlot] = []

    public init(slotCount: int = 0) {
        for _ in 0..<slotCount {
            Slots.append(FeedbackSlot())
        }
    }

    public subscript(index: int) -> FeedbackSlot {
        if index >= 0 && index < Slots.count {
            return Slots[index]
        }
        let newSlot = FeedbackSlot()
        while Slots.count <= index {
            Slots.append(FeedbackSlot())
        }
        return Slots[index]
    }
}
