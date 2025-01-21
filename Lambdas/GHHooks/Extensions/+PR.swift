import GitHubAPI

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension PullRequest {

    enum KnownLabel: String {
        case semVerMajor = "semver-major"
        case semVerMinor = "semver-minor"
        case semVerPatch = "semver-patch"
        case semVerNoOp = "semver-noop"
        case release = "release"
        case noReleaseNeeded = "no-release-needed"
        case translationUpdate = "translation-update"
        case noTranslationNeeded = "no-translation-needed"

        func toBump() -> SemVerBump? {
            switch self {
            case .semVerMajor: return .major
            case .semVerMinor: return .minor
            case .semVerPatch: return .patch
            case .release: return .releaseStage
            case .semVerNoOp, .noReleaseNeeded, .translationUpdate, .noTranslationNeeded: return nil
            }
        }
    }

    var knownLabels: [KnownLabel] {
        self.labels.compactMap {
            KnownLabel(rawValue: $0.name)
        }
    }

    var isIgnorableDoNotMergePR: Bool {
        let isTrustedUser = Constants.trustedGitHubUserIds.contains(self.user.id)
        guard isTrustedUser || self.authorAssociation.isContributorOrHigher else {
            return false
        }
        return self.title.hasDoNotMergePrefix
    }
}

extension SimplePullRequest {
    var knownLabels: [PullRequest.KnownLabel] {
        self.labels.compactMap {
            PullRequest.KnownLabel(rawValue: $0.name)
        }
    }
}

extension AuthorAssociation {
    fileprivate var isContributorOrHigher: Bool {
        switch self {
        case .collaborator, .contributor, .owner: return true
        case .member, .firstTimer, .firstTimeContributor, .mannequin, .none: return false
        }
    }
}

extension String {
    fileprivate var hasDoNotMergePrefix: Bool {
        let folded = self.lowercased()
            .filter { !$0.isPunctuation }
            .folding(options: .caseInsensitive, locale: nil)
            .folding(options: .diacriticInsensitive, locale: nil)
        return folded.hasPrefix("dnm") || folded.hasPrefix("do not merge")
    }
}
