import Foundation

nonisolated enum HunGitDiffLineKind: Equatable, Sendable {
    case context
    case addition
    case deletion
    case separator
}

nonisolated enum HunGitDiffBlockPosition: Equatable, Sendable {
    case none
    case single
    case first
    case middle
    case last
}

nonisolated enum HunGitDiffSide: Sendable {
    case left
    case right
}

nonisolated struct HunGitDiffLine: Equatable, Sendable {
    let kind: HunGitDiffLineKind
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?

    func displayContent(showWhitespace: Bool) -> String {
        guard showWhitespace else { return content }

        var result = ""
        result.reserveCapacity(content.count)
        for character in content {
            switch character {
            case " ":
                result.append("·")
            case "\t":
                result.append("→")
                result.append("   ")
            default:
                result.append(character)
            }
        }
        return result
    }
}

nonisolated struct HunGitSplitDiffRow: Equatable, Sendable {
    let leftIndex: Int?
    let rightIndex: Int?
    let isSeparator: Bool

    init(leftIndex: Int?, rightIndex: Int?, isSeparator: Bool = false) {
        self.leftIndex = leftIndex
        self.rightIndex = rightIndex
        self.isSeparator = isSeparator
    }

    func left(in lines: [HunGitDiffLine]) -> HunGitDiffLine? {
        leftIndex.map { lines[$0] }
    }

    func right(in lines: [HunGitDiffLine]) -> HunGitDiffLine? {
        rightIndex.map { lines[$0] }
    }
}

nonisolated struct HunGitDiffDocument: Sendable {
    let id = UUID()
    let lines: [HunGitDiffLine]
    let splitRows: [HunGitSplitDiffRow]
    let longestUnifiedLine: Int
    let longestSplitLine: Int
    private let oldSyntaxStates: [HunGitSyntaxState]
    private let newSyntaxStates: [HunGitSyntaxState]

    init(
        patch: String,
        syntaxPath: String = "",
        shouldCancel: @escaping @Sendable () -> Bool = { false }
    ) {
        let parsed = Self.parse(patch: patch, shouldCancel: shouldCancel)
        let rows = Self.makeSplitRows(from: parsed.lines, shouldCancel: shouldCancel)
        let syntaxStates = Self.makeSyntaxStates(
            for: parsed.lines,
            path: syntaxPath,
            shouldCancel: shouldCancel
        )

        lines = parsed.lines
        splitRows = rows
        longestUnifiedLine = parsed.longestLine
        longestSplitLine = parsed.longestLine
        oldSyntaxStates = syntaxStates.old
        newSyntaxStates = syntaxStates.new
    }

    func blockPosition(at index: Int) -> HunGitDiffBlockPosition {
        guard lines.indices.contains(index) else { return .none }
        let kind = lines[index].kind
        guard kind == .addition || kind == .deletion else { return .none }

        let matchesPrevious = index > lines.startIndex && lines[index - 1].kind == kind
        let matchesNext = index < lines.index(before: lines.endIndex) && lines[index + 1].kind == kind
        return Self.blockPosition(matchesPrevious: matchesPrevious, matchesNext: matchesNext)
    }

    func splitBlockPosition(
        at rowIndex: Int,
        side: HunGitDiffSide
    ) -> HunGitDiffBlockPosition {
        guard splitRows.indices.contains(rowIndex),
              let line = splitLine(at: rowIndex, side: side),
              line.kind == .addition || line.kind == .deletion
        else {
            return .none
        }

        let matchesPrevious =
            rowIndex > splitRows.startIndex &&
            splitLine(at: rowIndex - 1, side: side)?.kind == line.kind
        let matchesNext =
            rowIndex < splitRows.index(before: splitRows.endIndex) &&
            splitLine(at: rowIndex + 1, side: side)?.kind == line.kind
        return Self.blockPosition(matchesPrevious: matchesPrevious, matchesNext: matchesNext)
    }

    func syntaxState(at lineIndex: Int, side: HunGitDiffSide) -> HunGitSyntaxState {
        guard lines.indices.contains(lineIndex) else { return .normal }
        switch side {
        case .left:
            return oldSyntaxStates[lineIndex]
        case .right:
            return newSyntaxStates[lineIndex]
        }
    }

    func unifiedSyntaxState(at lineIndex: Int) -> HunGitSyntaxState {
        guard lines.indices.contains(lineIndex) else { return .normal }
        return lines[lineIndex].kind == .deletion
            ? oldSyntaxStates[lineIndex]
            : newSyntaxStates[lineIndex]
    }

    private func splitLine(at rowIndex: Int, side: HunGitDiffSide) -> HunGitDiffLine? {
        guard splitRows.indices.contains(rowIndex) else { return nil }
        switch side {
        case .left:
            return splitRows[rowIndex].left(in: lines)
        case .right:
            return splitRows[rowIndex].right(in: lines)
        }
    }

    private static func blockPosition(
        matchesPrevious: Bool,
        matchesNext: Bool
    ) -> HunGitDiffBlockPosition {
        switch (matchesPrevious, matchesNext) {
        case (false, false): .single
        case (false, true): .first
        case (true, true): .middle
        case (true, false): .last
        }
    }

    private static func makeSyntaxStates(
        for lines: [HunGitDiffLine],
        path: String,
        shouldCancel: @escaping @Sendable () -> Bool
    ) -> (old: [HunGitSyntaxState], new: [HunGitSyntaxState]) {
        let highlighter = HunGitSyntaxHighlighter(path: path)
        var oldStates = [HunGitSyntaxState](repeating: .normal, count: lines.count)
        var newStates = [HunGitSyntaxState](repeating: .normal, count: lines.count)
        guard highlighter.language != .plainText else {
            return (oldStates, newStates)
        }
        var oldState = HunGitSyntaxState.normal
        var newState = HunGitSyntaxState.normal

        for index in lines.indices {
            if index.isMultiple(of: 1_024), shouldCancel() {
                return (oldStates, newStates)
            }

            let line = lines[index]
            oldStates[index] = oldState
            newStates[index] = newState

            switch line.kind {
            case .context:
                oldState = highlighter.endState(after: line.content, startingIn: oldState)
                newState = highlighter.endState(after: line.content, startingIn: newState)
            case .deletion:
                oldState = highlighter.endState(after: line.content, startingIn: oldState)
            case .addition:
                newState = highlighter.endState(after: line.content, startingIn: newState)
            case .separator:
                oldState = .normal
                newState = .normal
                oldStates[index] = .normal
                newStates[index] = .normal
            }
        }

        return (oldStates, newStates)
    }

    private static func parse(
        patch: String,
        shouldCancel: @escaping @Sendable () -> Bool
    ) -> (lines: [HunGitDiffLine], longestLine: Int) {
        var result: [HunGitDiffLine] = []
        result.reserveCapacity(max(32, patch.utf8.count / 48))
        var longestLine = 0

        var oldLineNumber = 0
        var newLineNumber = 0
        var isInsideHunk = false
        var hasSeenHunk = false

        patch.enumerateLines { rawLine, stop in
            if result.count.isMultiple(of: 1_024), shouldCancel() {
                result.removeAll(keepingCapacity: false)
                stop = true
                return
            }
            if let ranges = hunkRanges(from: rawLine) {
                if hasSeenHunk {
                    result.append(
                        HunGitDiffLine(
                            kind: .separator,
                            content: "",
                            oldLineNumber: nil,
                            newLineNumber: nil
                        )
                    )
                }
                hasSeenHunk = true
                isInsideHunk = true
                oldLineNumber = ranges.oldStart
                newLineNumber = ranges.newStart
                return
            }

            guard isInsideHunk, let prefix = rawLine.first else { return }
            let content = String(rawLine.dropFirst())

            switch prefix {
            case " ":
                longestLine = max(longestLine, content.utf16.count)
                result.append(
                    HunGitDiffLine(
                        kind: .context,
                        content: content,
                        oldLineNumber: oldLineNumber,
                        newLineNumber: newLineNumber
                    )
                )
                oldLineNumber += 1
                newLineNumber += 1
            case "-":
                longestLine = max(longestLine, content.utf16.count)
                result.append(
                    HunGitDiffLine(
                        kind: .deletion,
                        content: content,
                        oldLineNumber: oldLineNumber,
                        newLineNumber: nil
                    )
                )
                oldLineNumber += 1
            case "+":
                longestLine = max(longestLine, content.utf16.count)
                result.append(
                    HunGitDiffLine(
                        kind: .addition,
                        content: content,
                        oldLineNumber: nil,
                        newLineNumber: newLineNumber
                    )
                )
                newLineNumber += 1
            case "\\":
                break
            default:
                isInsideHunk = false
            }
        }

        return (result, longestLine)
    }

    private static func hunkRanges(from line: String) -> (oldStart: Int, newStart: Int)? {
        guard line.hasPrefix("@@") else { return nil }
        let fields = line.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 3,
              let oldStart = rangeStart(from: fields[1], prefix: "-"),
              let newStart = rangeStart(from: fields[2], prefix: "+") else {
            return nil
        }
        return (oldStart, newStart)
    }

    private static func rangeStart(from field: Substring, prefix: Character) -> Int? {
        guard field.first == prefix else { return nil }
        let range = field.dropFirst()
        let start = range.split(separator: ",", maxSplits: 1).first ?? range
        return Int(start)
    }

    private static func makeSplitRows(
        from lines: [HunGitDiffLine],
        shouldCancel: @escaping @Sendable () -> Bool
    ) -> [HunGitSplitDiffRow] {
        var result: [HunGitSplitDiffRow] = []
        result.reserveCapacity(lines.count)

        var index = 0
        while index < lines.count {
            if result.count.isMultiple(of: 1_024), shouldCancel() {
                result.removeAll(keepingCapacity: false)
                return result
            }

            let line = lines[index]

            switch line.kind {
            case .context:
                result.append(HunGitSplitDiffRow(leftIndex: index, rightIndex: index))
                index += 1
            case .separator:
                result.append(
                    HunGitSplitDiffRow(leftIndex: nil, rightIndex: nil, isSeparator: true)
                )
                index += 1
            case .deletion:
                let deletionsStart = index
                while index < lines.count, lines[index].kind == .deletion {
                    index += 1
                    if index.isMultiple(of: 1_024), shouldCancel() {
                        result.removeAll(keepingCapacity: false)
                        return result
                    }
                }
                let deletionsCount = index - deletionsStart

                let additionsStart = index
                while index < lines.count, lines[index].kind == .addition {
                    index += 1
                    if index.isMultiple(of: 1_024), shouldCancel() {
                        result.removeAll(keepingCapacity: false)
                        return result
                    }
                }
                let additionsCount = index - additionsStart

                let count = max(deletionsCount, additionsCount)
                for offset in 0..<count {
                    if offset.isMultiple(of: 1_024), shouldCancel() {
                        result.removeAll(keepingCapacity: false)
                        return result
                    }
                    result.append(
                        HunGitSplitDiffRow(
                            leftIndex: offset < deletionsCount ? deletionsStart + offset : nil,
                            rightIndex: offset < additionsCount ? additionsStart + offset : nil
                        )
                    )
                }
            case .addition:
                while index < lines.count, lines[index].kind == .addition {
                    result.append(HunGitSplitDiffRow(leftIndex: nil, rightIndex: index))
                    index += 1
                    if index.isMultiple(of: 1_024), shouldCancel() {
                        result.removeAll(keepingCapacity: false)
                        return result
                    }
                }
            }
        }

        return result
    }
}
