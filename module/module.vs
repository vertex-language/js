package module

import (
    "js/object"
    "js/bytecode"
    "js/value"
)

/// ModuleStatus tracks the lifecycle of an ECMAScript module.
public enum ModuleStatus: Equatable {
    case unlinked
    case linking
    case linked
    case evaluating
    case evaluated
}

/// ImportEntry describes one imported binding.
public struct ImportEntry: Equatable {
    public let ModuleRequest: string
    public let ImportName: string
    public let LocalName: string

    public init(moduleRequest: string, importName: string, localName: string) {
        self.ModuleRequest = moduleRequest
        self.ImportName = importName
        self.LocalName = localName
    }
}

/// ExportEntry describes one exported binding.
public struct ExportEntry: Equatable {
    public let ExportName: string
    public let LocalName: string

    public init(exportName: string, localName: string) {
        self.ExportName = exportName
        self.LocalName = localName
    }
}

/// SourceTextModuleRecord implements ECMA-262 §16.2.1.5.
public final class SourceTextModuleRecord {
    public let Realm: object.Realm
    public let Source: string
    public var Status: ModuleStatus = .unlinked
    public var Bytecode: bytecode.BytecodeFunction?
    public var Namespace: object.JSObject?
    public var ImportEntries: [ImportEntry] = []
    public var ExportEntries: [ExportEntry] = []

    public init(realm: object.Realm, source: string) {
        self.Realm = realm
        self.Source = source
    }

    /// Link resolves dependencies and prepares the module environment.
    public func Link() throws {
        if Status == .linked || Status == .evaluated { return }
        Status = .linking
        Namespace = Realm.NewObject()
        Namespace?.InternalTag = "ModuleNamespace"
        Status = .linked
    }
}
