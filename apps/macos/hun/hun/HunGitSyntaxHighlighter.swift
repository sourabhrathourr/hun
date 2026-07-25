import Foundation

nonisolated enum HunGitSyntaxLanguage: Equatable, Sendable {
    case swift
    case typeScript
    case javaScript
    case go
    case python
    case rust
    case cFamily
    case ruby
    case shell
    case json
    case yaml
    case configuration
    case markdown
    case html
    case css
    case sql
    case plainText

    init(path: String) {
        let fileName = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        let fileExtension = URL(fileURLWithPath: path).pathExtension.lowercased()

        switch fileExtension {
        case "swift": self = .swift
        case "ts", "tsx": self = .typeScript
        case "js", "jsx", "mjs", "cjs": self = .javaScript
        case "go": self = .go
        case "py", "pyi": self = .python
        case "rs": self = .rust
        case "c", "h", "cc", "cpp", "cxx", "hh", "hpp", "hxx", "m", "mm",
             "java", "kt", "kts", "cs", "dart", "php":
            self = .cFamily
        case "rb", "rake", "gemspec": self = .ruby
        case "sh", "bash", "zsh", "fish": self = .shell
        case "json", "jsonc": self = .json
        case "yaml", "yml": self = .yaml
        case "toml", "ini", "conf", "properties": self = .configuration
        case "md", "mdx", "markdown": self = .markdown
        case "html", "htm", "xml", "svg": self = .html
        case "css", "scss", "sass", "less": self = .css
        case "sql": self = .sql
        default:
            switch fileName {
            case "dockerfile", "makefile": self = .shell
            default: self = .plainText
            }
        }
    }

    fileprivate var keywords: Set<String> {
        switch self {
        case .swift:
            return [
                "actor", "associatedtype", "async", "await", "break", "case", "catch", "class",
                "continue", "default", "defer", "do", "else", "enum", "extension", "fallthrough",
                "false", "fileprivate", "for", "func", "guard", "if", "import", "in", "init",
                "inout", "internal", "is", "let", "nil", "nonisolated", "open", "private",
                "protocol", "public", "repeat", "return", "self", "some", "static", "struct",
                "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias",
                "var", "where", "while"
            ]
        case .typeScript, .javaScript:
            return [
                "as", "async", "await", "break", "case", "catch", "class", "const", "continue",
                "debugger", "declare", "default", "delete", "do", "else", "enum", "export",
                "extends", "false", "finally", "for", "from", "function", "if", "implements",
                "import", "in", "instanceof", "interface", "keyof", "let", "new", "null", "of",
                "private", "protected", "public", "readonly", "return", "satisfies", "static",
                "super", "switch", "this", "throw", "true", "try", "type", "typeof", "undefined",
                "var", "void", "while", "with", "yield"
            ]
        case .go:
            return [
                "break", "case", "chan", "const", "continue", "default", "defer", "else",
                "fallthrough", "false", "for", "func", "go", "goto", "if", "import", "interface",
                "map", "nil", "package", "range", "return", "select", "struct", "switch", "true",
                "type", "var"
            ]
        case .python:
            return [
                "and", "as", "assert", "async", "await", "break", "case", "class", "continue",
                "def", "del", "elif", "else", "except", "False", "finally", "for", "from",
                "global", "if", "import", "in", "is", "lambda", "match", "None", "nonlocal",
                "not", "or", "pass", "raise", "return", "True", "try", "while", "with", "yield"
            ]
        case .rust:
            return [
                "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else",
                "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop",
                "match", "mod", "move", "mut", "pub", "ref", "return", "self", "static",
                "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while"
            ]
        case .cFamily:
            return [
                "abstract", "as", "async", "await", "base", "bool", "break", "case", "catch",
                "char", "class", "const", "continue", "default", "delegate", "do", "double",
                "dynamic", "else", "enum", "explicit", "export", "extends", "extern", "false",
                "final", "finally", "float", "for", "foreach", "friend", "fun", "function",
                "goto", "if", "implements", "import", "in", "inline", "int", "interface",
                "internal", "is", "long", "namespace", "native", "new", "null", "operator",
                "out", "override", "package", "private", "protected", "public", "readonly",
                "record", "ref", "return", "sealed", "short", "signed", "sizeof", "static",
                "string", "struct", "super", "switch", "template", "this", "throw", "throws",
                "true", "try", "typedef", "typename", "uint", "ulong", "union", "unsigned",
                "using", "var", "virtual", "void", "volatile", "when", "while", "yield"
            ]
        case .ruby:
            return [
                "alias", "and", "begin", "break", "case", "class", "def", "defined", "do",
                "else", "elsif", "end", "ensure", "false", "for", "if", "in", "module", "next",
                "nil", "not", "or", "redo", "rescue", "retry", "return", "self", "super",
                "then", "true", "undef", "unless", "until", "when", "while", "yield"
            ]
        case .shell:
            return [
                "case", "do", "done", "elif", "else", "esac", "export", "fi", "for", "function",
                "if", "in", "local", "readonly", "return", "select", "then", "until", "while"
            ]
        case .sql:
            return [
                "alter", "and", "as", "asc", "begin", "between", "by", "case", "commit",
                "create", "delete", "desc", "distinct", "drop", "else", "end", "from", "group",
                "having", "in", "insert", "into", "is", "join", "limit", "not", "null", "on",
                "or", "order", "outer", "returning", "rollback", "select", "set", "table",
                "then", "union", "update", "values", "when", "where", "with"
            ]
        case .json:
            return ["false", "null", "true"]
        case .yaml, .configuration, .markdown, .html, .css, .plainText:
            return []
        }
    }

    fileprivate var hashStartsComment: Bool {
        switch self {
        case .python, .ruby, .shell, .yaml, .configuration: true
        default: false
        }
    }

    fileprivate var slashStartsComment: Bool {
        switch self {
        case .swift, .typeScript, .javaScript, .go, .rust, .cFamily, .json: true
        default: false
        }
    }

    fileprivate var dashStartsComment: Bool {
        self == .sql
    }

    fileprivate var blockCommentDelimiters: (start: [UInt16], end: [UInt16])? {
        switch self {
        case .swift, .typeScript, .javaScript, .go, .rust, .cFamily, .json, .css:
            return ([47, 42], [42, 47])
        case .html:
            return ([60, 33, 45, 45], [45, 45, 62])
        default:
            return nil
        }
    }
}

nonisolated enum HunGitSyntaxTokenKind: Equatable, Sendable {
    case keyword
    case string
    case number
    case comment
    case type
    case property
    case heading
}

nonisolated struct HunGitSyntaxToken: Equatable, Sendable {
    let range: NSRange
    let kind: HunGitSyntaxTokenKind
}

nonisolated enum HunGitSyntaxState: Equatable, Sendable {
    case normal
    case blockComment
}

nonisolated struct HunGitSyntaxLine: Equatable, Sendable {
    let tokens: [HunGitSyntaxToken]
    let endState: HunGitSyntaxState
}

nonisolated struct HunGitSyntaxHighlighter: Sendable {
    let language: HunGitSyntaxLanguage
    private let keywords: Set<String>

    init(path: String) {
        let language = HunGitSyntaxLanguage(path: path)
        self.language = language
        keywords = language.keywords
    }

    func tokens(in line: String) -> [HunGitSyntaxToken] {
        tokenize(line, startingIn: .normal).tokens
    }

    func tokenize(
        _ line: String,
        startingIn initialState: HunGitSyntaxState
    ) -> HunGitSyntaxLine {
        guard language != .plainText else {
            return HunGitSyntaxLine(tokens: [], endState: .normal)
        }
        guard !line.isEmpty else {
            return HunGitSyntaxLine(tokens: [], endState: initialState)
        }
        if language == .markdown {
            return HunGitSyntaxLine(tokens: markdownTokens(in: line), endState: .normal)
        }

        let units = Array(line.utf16)
        var tokens: [HunGitSyntaxToken] = []
        tokens.reserveCapacity(8)
        var index = 0
        var state = initialState

        if state == .blockComment {
            guard let delimiters = language.blockCommentDelimiters else {
                state = .normal
                return HunGitSyntaxLine(tokens: [], endState: state)
            }
            if let end = endOfSequence(delimiters.end, in: units, from: 0) {
                tokens.append(
                    HunGitSyntaxToken(
                        range: NSRange(location: 0, length: end),
                        kind: .comment
                    )
                )
                index = end
                state = .normal
            } else {
                return HunGitSyntaxLine(
                    tokens: [
                        HunGitSyntaxToken(
                            range: NSRange(location: 0, length: units.count),
                            kind: .comment
                        )
                    ],
                    endState: .blockComment
                )
            }
        }

        while index < units.count {
            if let delimiters = language.blockCommentDelimiters,
               sequence(delimiters.start, matches: units, at: index) {
                if let end = endOfSequence(
                    delimiters.end,
                    in: units,
                    from: index + delimiters.start.count
                ) {
                    tokens.append(
                        HunGitSyntaxToken(
                            range: NSRange(location: index, length: end - index),
                            kind: .comment
                        )
                    )
                    index = end
                    continue
                }
                tokens.append(
                    HunGitSyntaxToken(
                        range: NSRange(location: index, length: units.count - index),
                        kind: .comment
                    )
                )
                state = .blockComment
                break
            }

            if isCommentStart(units, at: index) {
                tokens.append(
                    HunGitSyntaxToken(
                        range: NSRange(location: index, length: units.count - index),
                        kind: .comment
                    )
                )
                break
            }

            let unit = units[index]
            if unit == 34 || unit == 39 || unit == 96 {
                let end = stringEnd(in: units, from: index, delimiter: unit)
                tokens.append(
                    HunGitSyntaxToken(
                        range: NSRange(location: index, length: end - index),
                        kind: .string
                    )
                )
                index = end
                continue
            }

            if isDigit(unit) {
                let start = index
                index += 1
                while index < units.count,
                      isDigit(units[index]) || units[index] == 46 || units[index] == 95 {
                    index += 1
                }
                tokens.append(
                    HunGitSyntaxToken(
                        range: NSRange(location: start, length: index - start),
                        kind: .number
                    )
                )
                continue
            }

            if isIdentifierStart(unit) {
                let start = index
                index += 1
                while index < units.count, isIdentifierBody(units[index]) {
                    index += 1
                }
                let range = NSRange(location: start, length: index - start)
                let word = (line as NSString).substring(with: range)
                let normalized = language == .sql ? word.lowercased() : word
                if keywords.contains(normalized) {
                    tokens.append(HunGitSyntaxToken(range: range, kind: .keyword))
                } else if word.first?.isUppercase == true {
                    tokens.append(HunGitSyntaxToken(range: range, kind: .type))
                } else if nextNonWhitespaceUnit(in: units, after: index) == 58 {
                    tokens.append(HunGitSyntaxToken(range: range, kind: .property))
                }
                continue
            }

            index += 1
        }

        return HunGitSyntaxLine(tokens: tokens, endState: state)
    }

    func endState(
        after line: String,
        startingIn initialState: HunGitSyntaxState
    ) -> HunGitSyntaxState {
        guard let delimiters = language.blockCommentDelimiters else {
            return .normal
        }
        guard !line.isEmpty else { return initialState }
        let units = Array(line.utf16)
        var index = 0

        if initialState == .blockComment {
            guard let end = endOfSequence(delimiters.end, in: units, from: 0) else {
                return .blockComment
            }
            index = end
        }

        while index < units.count {
            if isCommentStart(units, at: index) {
                return .normal
            }
            let unit = units[index]
            if unit == 34 || unit == 39 || unit == 96 {
                index = stringEnd(in: units, from: index, delimiter: unit)
                continue
            }
            if sequence(delimiters.start, matches: units, at: index) {
                guard let end = endOfSequence(
                    delimiters.end,
                    in: units,
                    from: index + delimiters.start.count
                ) else {
                    return .blockComment
                }
                index = end
                continue
            }
            index += 1
        }

        return .normal
    }

    private func markdownTokens(in line: String) -> [HunGitSyntaxToken] {
        let units = Array(line.utf16)
        let firstContent = units.firstIndex(where: { $0 != 32 && $0 != 9 })
        if let firstContent, units[firstContent] == 35 {
            return [
                HunGitSyntaxToken(
                    range: NSRange(location: firstContent, length: units.count - firstContent),
                    kind: .heading
                )
            ]
        }

        var tokens: [HunGitSyntaxToken] = []
        var index = 0
        while index < units.count {
            if units[index] == 96 {
                let end = stringEnd(in: units, from: index, delimiter: 96)
                tokens.append(
                    HunGitSyntaxToken(
                        range: NSRange(location: index, length: end - index),
                        kind: .string
                    )
                )
                index = end
            } else {
                index += 1
            }
        }
        return tokens
    }

    private func isCommentStart(_ units: [UInt16], at index: Int) -> Bool {
        if language.hashStartsComment, units[index] == 35 {
            return true
        }
        guard index + 1 < units.count else { return false }
        if language.slashStartsComment, units[index] == 47, units[index + 1] == 47 {
            return true
        }
        return language.dashStartsComment && units[index] == 45 && units[index + 1] == 45
    }

    private func endOfSequence(
        _ sequence: [UInt16],
        in units: [UInt16],
        from start: Int
    ) -> Int? {
        guard !sequence.isEmpty, start < units.count else { return nil }
        var index = start
        while index + sequence.count <= units.count {
            if self.sequence(sequence, matches: units, at: index) {
                return index + sequence.count
            }
            index += 1
        }
        return nil
    }

    private func sequence(_ sequence: [UInt16], matches units: [UInt16], at index: Int) -> Bool {
        guard index >= 0, index + sequence.count <= units.count else { return false }
        for offset in sequence.indices where units[index + offset] != sequence[offset] {
            return false
        }
        return true
    }

    private func stringEnd(in units: [UInt16], from start: Int, delimiter: UInt16) -> Int {
        var index = start + 1
        while index < units.count {
            if units[index] == 92 {
                index = min(units.count, index + 2)
            } else if units[index] == delimiter {
                return index + 1
            } else {
                index += 1
            }
        }
        return units.count
    }

    private func nextNonWhitespaceUnit(in units: [UInt16], after index: Int) -> UInt16? {
        var cursor = index
        while cursor < units.count, units[cursor] == 32 || units[cursor] == 9 {
            cursor += 1
        }
        return cursor < units.count ? units[cursor] : nil
    }

    private func isIdentifierStart(_ unit: UInt16) -> Bool {
        (65...90).contains(unit) || (97...122).contains(unit) || unit == 95 || unit == 36
    }

    private func isIdentifierBody(_ unit: UInt16) -> Bool {
        isIdentifierStart(unit) || isDigit(unit)
    }

    private func isDigit(_ unit: UInt16) -> Bool {
        (48...57).contains(unit)
    }
}
