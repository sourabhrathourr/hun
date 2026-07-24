import Foundation

nonisolated enum HunGitDiffLineKind: Equatable, Sendable {
    case context
    case addition
    case deletion
    case separator
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

    init(
        patch: String,
        shouldCancel: @escaping @Sendable () -> Bool = { false }
    ) {
        let parsed = Self.parse(patch: patch, shouldCancel: shouldCancel)
        let rows = Self.makeSplitRows(from: parsed.lines, shouldCancel: shouldCancel)

        lines = parsed.lines
        splitRows = rows
        longestUnifiedLine = parsed.longestLine
        longestSplitLine = parsed.longestLine
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
