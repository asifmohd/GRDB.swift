#if !USING_BUILTIN_SQLITE
    #if os(OSX)
        import SQLiteMacOSX
    #elseif os(iOS)
        #if (arch(i386) || arch(x86_64))
            import SQLiteiPhoneSimulator
        #else
            import SQLiteiPhoneOS
        #endif
    #endif
#endif

/// AdaptedColumnsDescription is a type that supports the RowAdapter protocol.
public struct AdaptedColumnsDescription {
    let columns: [(Int, String)]         // [(baseRowIndex, adaptedColumn), ...]
    let lowercaseColumnIndexes: [String: Int]   // [adaptedColumn: adaptedRowIndex]

    /// Creates an AdaptedColumnsDescription from an array of (index, name)
    /// pairs. In each pair:
    ///
    /// - index is the index of a column in an original row
    /// - name is the name of the column in an adapted row
    ///
    /// For example, the following AdaptedColumnsDescription defines two
    /// columns, "foo" and "bar", that load from the original columns at
    /// indexes 1 and 2:
    ///
    ///     AdaptedColumnsDescription([(1, "foo"), (2, "bar")])
    ///
    /// Use it in your custom RowAdapter type:
    ///
    ///     struct FooBarAdapter : RowAdapter {
    ///         func concreteRowAdapter(with statement: SelectStatement) throws -> ConcreteRowAdapter {
    ///             return AdaptedColumnsDescription([(1, "foo"), (2, "bar")])
    ///         }
    ///     }
    ///
    ///     // <Row foo:2 bar: 3>
    ///     Row.fetchOne(db, "SELECT 1, 2, 3", adapter: FooBarAdapter())
    public init(columns: [(Int, String)]) {
        self.columns = columns
        self.lowercaseColumnIndexes = Dictionary(keyValueSequence: columns.enumerate().map { ($1.1.lowercaseString, $0) }.reverse())
    }

    var count: Int {
        return columns.count
    }

    func baseColumIndex(adaptedIndex index: Int) -> Int {
        return columns[index].0
    }

    func columnName(adaptedIndex index: Int) -> String {
        return columns[index].1
    }

    func adaptedIndexOfColumn(named name: String) -> Int? {
        if let index = lowercaseColumnIndexes[name] {
            return index
        }
        return lowercaseColumnIndexes[name.lowercaseString]
    }
}

/// AdaptedColumnsDescription adopts ConcreteRowAdapter
extension AdaptedColumnsDescription : ConcreteRowAdapter {
    /// Part of the ConcreteRowAdapter protocol; returns self.
    public var adaptedColumnsDescription: AdaptedColumnsDescription {
        return self
    }
    
    /// Part of the ConcreteRowAdapter protocol; returns the empty dictionary.
    public var scopes: [String: ConcreteRowAdapter] {
        return [:]
    }
}

struct ConcreteScopeAdapter : ConcreteRowAdapter {
    let adaptedColumnsDescription: AdaptedColumnsDescription
    let scopes: [String: ConcreteRowAdapter]
}

/// ConcreteRowAdapter is a protocol that supports the RowAdapter protocol.
///
/// GRBD ships with a concrete type that adopts the ConcreteRowAdapter protocol:
/// AdaptedColumnsDescription.
///
/// It is unlikely that you need to write your custom type that adopts
/// this protocol.
public protocol ConcreteRowAdapter {
    // An AdaptedColumnsDescription
    var adaptedColumnsDescription: AdaptedColumnsDescription { get }
    
    /// A dictionary whose keys are scope names.
    var scopes: [String: ConcreteRowAdapter] { get }
}

/// RowAdapter is a protocol that helps two incompatible row interfaces working
/// together.
///
/// GRDB ships with three concrete types that adopt the RowAdapter protocol:
///
/// - ColumnMapping: renames row columns
/// - SuffixRowAdapter: hides the first columns of a row
/// - ScopeAdapter: groups several adapters together to define named scopes
///
/// If the built-in adapters don't fit your needs, you can implement your own
/// type that adopts RowAdapter.
///
/// To use a row adapter, provide it to any method that fetches:
///
///     let adapter = SuffixRowAdapter(fromIndex: 2)
///     let sql = "SELECT 1 AS foo, 2 AS bar, 3 AS baz"
///
///     // <Row baz:3>
///     Row.fetchOne(db, sql, adapter: adapter)
public protocol RowAdapter {
    
    /// You never call this method directly. It is called for you whenever an
    /// adapter has to be applied.
    ///
    /// The result is a value that adopts ConcreteRowAdapter, such as
    /// AdaptedColumnsDescription.
    ///
    /// For example:
    ///
    ///     // An adapter that turns any row to a row that contains a single
    ///     // column named "foo" whose value is the leftmost value of the
    ///     // original row.
    ///     struct FirstColumnAdapter : RowAdapter {
    ///         func concreteRowAdapter(with statement: SelectStatement) throws -> ConcreteRowAdapter {
    ///             return AdaptedColumnsDescription(columns: [(0, "foo")])
    ///         }
    ///     }
    ///
    ///     // <Row foo:1>
    ///     Row.fetchOne(db, "SELECT 1, 2, 3", adapter: FirstColumnAdapter())
    func concreteRowAdapter(with statement: SelectStatement) throws -> ConcreteRowAdapter
}

extension RowAdapter {
    /// Returns an adapter based on self, with added scopes.
    ///
    /// If self already defines scopes, the added scopes replace
    /// eventual existing scopes with the same name.
    ///
    /// - parameter scopes: A dictionary that maps scope names to
    ///   row adapters.
    public func addingScopes(scopes: [String: RowAdapter]) -> RowAdapter {
        return ScopeAdapter(mainAdapter: self, scopes: scopes)
    }
}

/// ColumnMapping is a row adapter that maps column names.
///
///     let adapter = ColumnMapping(["foo": "bar"])
///     let sql = "SELECT 'foo' AS foo, 'bar' AS bar, 'baz' AS baz"
///
///     // <Row foo:"bar">
///     Row.fetchOne(db, sql, adapter: adapter)
public struct ColumnMapping : RowAdapter {
    /// The column names mapping, from adapted names to original names.
    let mapping: [String: String]
    
    /// Creates a ColumnMapping with a dictionary that maps adapted column names
    /// to original column names.
    public init(_ mapping: [String: String]) {
        self.mapping = mapping
    }
    
    /// Part of the RowAdapter protocol
    public func concreteRowAdapter(with statement: SelectStatement) throws -> ConcreteRowAdapter {
        let columns = try mapping
            .map { (mappedColumn, baseColumn) -> (Int, String) in
                guard let index = statement.indexOfColumn(named: baseColumn) else {
                    throw DatabaseError(code: SQLITE_MISUSE, message: "Mapping references missing column \(baseColumn). Valid column names are: \(statement.columnNames.joinWithSeparator(", ")).")
                }
                return (index, mappedColumn)
            }
            .sort { $0.0 < $1.0 }
        return AdaptedColumnsDescription(columns: columns)
    }
}

/// SuffixRowAdapter is a row adapter that hides the first columns in a row.
///
///     let adapter = SuffixRowAdapter(fromIndex: 2)
///     let sql = "SELECT 1 AS foo, 2 AS bar, 3 AS baz"
///
///     // <Row baz:3>
///     Row.fetchOne(db, sql, adapter: adapter)
public struct SuffixRowAdapter : RowAdapter {
    /// The suffix index
    let index: Int
    
    /// Creates a SuffixRowAdapter that hides all columns before the
    /// provided index.
    ///
    /// If index is 0, the adapted row is identical to the original row.
    public init(fromIndex index: Int) {
        GRDBPrecondition(index >= 0, "Negative column index is out of range")
        self.index = index
    }
    
    /// Part of the RowAdapter protocol
    public func concreteRowAdapter(with statement: SelectStatement) throws -> ConcreteRowAdapter {
        GRDBPrecondition(index <= statement.columnCount, "Column index is out of range")
        return AdaptedColumnsDescription(columns: statement.columnNames.suffixFrom(index).enumerate().map { ($0 + index, $1) })
    }
}

/// ScopeAdapter is a row adapter that lets you add scoped adaptations to rows.
///
///     // Two adapters
///     let fooAdapter = ColumnMapping(["value": "foo"])
///     let barAdapter = ColumnMapping(["value": "bar"])
///
///     // An adapter with named scopes
///     let adapter = ScopeAdapter([
///         "foo": fooAdapter,
///         "bar": barAdapter])
///
///     // Fetch a row
///     let sql = "SELECT 'foo' AS foo, 'bar' AS bar"
///     let row = Row.fetchOne(db, sql, adapter: adapter)!
///
///     // Two scoped rows:
///     if let fooRow = row.scoped(on: "foo") {
///         fooRow.value(named: "value")    // "foo"
///     }
///     if let barRow = row.scopeed(on: "bar") {
///         barRow.value(named: "value")    // "bar"
///     }
public struct ScopeAdapter : RowAdapter {
    
    /// The main adapter
    let mainAdapter: RowAdapter
    
    /// The scope adapters
    let scopes: [String: RowAdapter]
    
    /// Creates a scoped adapter.
    ///
    /// - parameter scopes: A dictionary that maps scope names to
    ///   row adapters.
    public init(_ scopes: [String: RowAdapter]) {
        self.mainAdapter = SuffixRowAdapter(fromIndex: 0)
        self.scopes = scopes
    }
    
    init(mainAdapter: RowAdapter, scopes: [String: RowAdapter]) {
        self.mainAdapter = mainAdapter
        self.scopes = scopes
    }
    
    /// Part of the RowAdapter protocol
    public func concreteRowAdapter(with statement: SelectStatement) throws -> ConcreteRowAdapter {
        let mainConcreteAdapter = try mainAdapter.concreteRowAdapter(with: statement)
        var concreteAdapterScopes = mainConcreteAdapter.scopes
        for (name, adapter) in scopes {
            try concreteAdapterScopes[name] = adapter.concreteRowAdapter(with: statement)
        }
        return ConcreteScopeAdapter(
            adaptedColumnsDescription: mainConcreteAdapter.adaptedColumnsDescription,
            scopes: concreteAdapterScopes)
    }
}

extension Row {
    /// Builds a row from a base row and a statement adapter
    convenience init(baseRow: Row, concreteRowAdapter: ConcreteRowAdapter) {
        self.init(impl: AdapterRowImpl(baseRow: baseRow, concreteRowAdapter: concreteRowAdapter))
    }

    /// Returns self if adapter is nil
    func adaptedRow(adapter adapter: RowAdapter?, statement: SelectStatement) throws -> Row {
        guard let adapter = adapter else {
            return self
        }
        return try Row(baseRow: self, concreteRowAdapter: adapter.concreteRowAdapter(with: statement))
    }
}

struct AdapterRowImpl : RowImpl {
    let baseRow: Row
    let concreteRowAdapter: ConcreteRowAdapter
    let adaptedColumnsDescription: AdaptedColumnsDescription

    init(baseRow: Row, concreteRowAdapter: ConcreteRowAdapter) {
        self.baseRow = baseRow
        self.concreteRowAdapter = concreteRowAdapter
        self.adaptedColumnsDescription = concreteRowAdapter.adaptedColumnsDescription
    }

    var count: Int {
        return adaptedColumnsDescription.count
    }

    func databaseValue(atIndex index: Int) -> DatabaseValue {
        return baseRow.databaseValue(atIndex: adaptedColumnsDescription.baseColumIndex(adaptedIndex: index))
    }

    func dataNoCopy(atIndex index:Int) -> NSData? {
        return baseRow.dataNoCopy(atIndex: adaptedColumnsDescription.baseColumIndex(adaptedIndex: index))
    }

    func columnName(atIndex index: Int) -> String {
        return adaptedColumnsDescription.columnName(adaptedIndex: index)
    }

    func indexOfColumn(named name: String) -> Int? {
        return adaptedColumnsDescription.adaptedIndexOfColumn(named: name)
    }

    func scoped(on name: String) -> Row? {
        guard let concreteRowAdapter = concreteRowAdapter.scopes[name] else {
            return nil
        }
        return Row(baseRow: baseRow, concreteRowAdapter: concreteRowAdapter)
    }
    
    var scopeNames: Set<String> {
        return Set(concreteRowAdapter.scopes.keys)
    }
    
    func copy(row: Row) -> Row {
        return Row(baseRow: baseRow.copy(), concreteRowAdapter: concreteRowAdapter)
    }
}
