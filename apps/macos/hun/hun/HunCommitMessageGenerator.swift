import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

nonisolated enum HunCommitMessageGenerationAvailability: Equatable, Sendable {
    case available
    case unavailable(String)

    var unavailableReason: String? {
        guard case let .unavailable(reason) = self else { return nil }
        return reason
    }
}

nonisolated protocol HunCommitMessageGenerating: Sendable {
    var availability: HunCommitMessageGenerationAvailability { get }
    func generate(from context: HunCommitMessageContext) async throws -> String
}

nonisolated enum HunCommitMessageGenerationError: LocalizedError {
    case unavailable(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case let .unavailable(reason):
            reason
        case .emptyResponse:
            "Apple Intelligence did not return a commit message. Try again."
        }
    }
}

nonisolated struct HunCommitMessageSuggestion: Equatable, Sendable {
    let type: String
    let scope: String
    let subject: String
}

nonisolated enum HunConventionalCommitFormatter {
    private static let typeAliases = [
        "build": "build",
        "chore": "chore",
        "ci": "ci",
        "docs": "docs",
        "documentation": "docs",
        "feat": "feat",
        "feature": "feat",
        "fix": "fix",
        "performance": "perf",
        "perf": "perf",
        "refactor": "refactor",
        "style": "style",
        "test": "test",
        "tests": "test"
    ]

    static func message(from suggestion: HunCommitMessageSuggestion) -> String {
        let typeKey = suggestion.type
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let type = typeAliases[typeKey] ?? "chore"
        let scope = normalizedScope(suggestion.scope)
        let prefix = scope.isEmpty ? "\(type): " : "\(type)(\(scope)): "
        let subject = normalizedSubject(suggestion.subject)
        return prefix + shortened(subject, maximumLength: max(1, 72 - prefix.count))
    }

    private static func normalizedScope(_ rawScope: String) -> String {
        let lowercase = rawScope
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        var result = ""
        var needsSeparator = false

        for scalar in lowercase.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || "._-".unicodeScalars.contains(scalar) {
                if needsSeparator, !result.isEmpty, !result.hasSuffix("-") {
                    result.append("-")
                }
                result.unicodeScalars.append(scalar)
                needsSeparator = false
            } else {
                needsSeparator = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
    }

    private static func normalizedSubject(_ rawSubject: String) -> String {
        var subject = rawSubject
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? ""
        subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)

        if let colon = subject.firstIndex(of: ":") {
            let candidatePrefix = subject[..<colon].lowercased()
            let candidateType = candidatePrefix
                .split(separator: "(", maxSplits: 1)
                .first
                .map(String.init) ?? ""
            if typeAliases[candidateType] != nil {
                subject = String(subject[subject.index(after: colon)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        subject = subject.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines
                .union(CharacterSet(charactersIn: ".!;:"))
        )
        guard let first = subject.first else { return "update staged changes" }
        return first.lowercased() + subject.dropFirst()
    }

    private static func shortened(_ value: String, maximumLength: Int) -> String {
        guard value.count > maximumLength else { return value }
        let candidate = String(value.prefix(maximumLength))
        if let lastSpace = candidate.lastIndex(of: " "),
           candidate.distance(from: candidate.startIndex, to: lastSpace) >= maximumLength / 2 {
            return String(candidate[..<lastSpace])
        }
        return candidate
    }
}

nonisolated struct HunCommitMessageContext: Equatable, Sendable {
    let stagedFileCount: Int
    let prompt: String
    let wasTruncated: Bool

    static func build(
        stagedChanges: [HunGitFileChange],
        diffs: [HunGitDiff],
        characterLimit: Int = 12_000
    ) -> HunCommitMessageContext {
        let safeLimit = max(1, characterLimit)
        let stagedPaths = Set(stagedChanges.map(\.path))
        let stagedDiffs = diffs.filter { $0.staged && stagedPaths.contains($0.path) }

        var content = """
        Staged files (\(stagedChanges.count)):
        \(stagedChanges.map { "\($0.indexState.displayLetter) \($0.path)" }.joined(separator: "\n"))

        Staged diff excerpts:
        """

        for diff in stagedDiffs {
            content += "\n\n--- \(diff.path)"
            if diff.binary {
                content += "\nBinary file changed."
            } else {
                content += "\n\(diff.content)"
            }
            if diff.truncated {
                content += "\n[Git diff was truncated.]"
            }
        }

        let wasTruncated = content.count > safeLimit
        let prompt = wasTruncated ? String(content.prefix(safeLimit)) : content
        return HunCommitMessageContext(
            stagedFileCount: stagedChanges.count,
            prompt: prompt,
            wasTruncated: wasTruncated
        )
    }
}

nonisolated enum HunCommitMessageGeneratorFactory {
    static func makeDefault() -> any HunCommitMessageGenerating {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return HunAppleCommitMessageGenerator()
        }
        #endif
        return HunUnavailableCommitMessageGenerator(
            reason: "On-device commit suggestions require macOS 26 or later."
        )
    }
}

nonisolated struct HunUnavailableCommitMessageGenerator: HunCommitMessageGenerating {
    let reason: String

    var availability: HunCommitMessageGenerationAvailability {
        .unavailable(reason)
    }

    func generate(from context: HunCommitMessageContext) async throws -> String {
        throw HunCommitMessageGenerationError.unavailable(reason)
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable(description: "A concise Conventional Commit suggestion.")
private struct HunFoundationModelCommitSuggestion {
    @Guide(description: "Exactly one type: feat, fix, refactor, perf, docs, test, build, ci, chore, or style.")
    var type: String

    @Guide(description: "A short lowercase component scope, or an empty string when no useful scope is clear.")
    var scope: String

    @Guide(description: "An imperative, lowercase summary without a prefix or trailing punctuation.")
    var subject: String
}

@available(macOS 26.0, *)
nonisolated final class HunAppleCommitMessageGenerator: HunCommitMessageGenerating, @unchecked Sendable {
    private let model = SystemLanguageModel.default

    var availability: HunCommitMessageGenerationAvailability {
        switch model.availability {
        case .available:
            .available
        case .unavailable(.deviceNotEligible):
            .unavailable("Apple Intelligence is not available on this Mac.")
        case .unavailable(.appleIntelligenceNotEnabled):
            .unavailable("Turn on Apple Intelligence in System Settings.")
        case .unavailable(.modelNotReady):
            .unavailable("Apple Intelligence is still preparing its on-device model.")
        @unknown default:
            .unavailable("Apple Intelligence is unavailable on this system.")
        }
    }

    func generate(from context: HunCommitMessageContext) async throws -> String {
        guard case .available = availability else {
            throw HunCommitMessageGenerationError.unavailable(
                availability.unavailableReason ?? "Apple Intelligence is unavailable."
            )
        }

        let instructions = """
        You write high-quality Git commit messages from staged changes only.
        Return one Conventional Commit suggestion. Select the most accurate type.
        Describe the user-visible intent, not an inventory of files.
        Keep the subject imperative, specific, and concise. Do not invent changes.
        """
        let session = LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(
            to: context.prompt,
            generating: HunFoundationModelCommitSuggestion.self
        )
        let suggestion = HunCommitMessageSuggestion(
            type: response.content.type,
            scope: response.content.scope,
            subject: response.content.subject
        )
        let message = HunConventionalCommitFormatter.message(from: suggestion)
        guard !message.isEmpty else {
            throw HunCommitMessageGenerationError.emptyResponse
        }
        return message
    }
}
#endif
