//
//  AdminCommunityControlCenter.swift
//  PurePetsAdmin
//
//  Server-authoritative operations console for Community adoption and
//  missing/found workflows. All mutations go through audited Cloud Functions;
//  exact locations and private organization details are opt-in, permission-
//  gated reads whose backend access is itself audited.
//

import FirebaseAuth
import FirebaseFunctions
import MapKit
import SwiftUI
import UIKit

// MARK: - Color Utilities

fileprivate extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Backend value model

struct CommunityAdminRecord: Identifiable {
    let id: String
    let values: [String: Any]
    let source: CommunityAdminLane

    init?(values: [String: Any], source: CommunityAdminLane) {
        guard let id = values["id"] as? String,
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        self.id = id
        self.values = values
        self.source = source
    }

    func value(_ path: String) -> Any? {
        var current: Any = values
        for component in path.split(separator: ".").map(String.init) {
            if let dictionary = current as? [String: Any], let next = dictionary[component] {
                current = next
            } else if let dictionary = current as? NSDictionary, let next = dictionary[component] {
                current = next
            } else {
                return nil
            }
        }
        return current
    }

    func string(_ paths: String...) -> String {
        for path in paths {
            if let value = value(path) as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return ""
    }

    func integer(_ path: String) -> Int {
        if let value = value(path) as? NSNumber { return value.intValue }
        if let value = value(path) as? Int { return value }
        if let value = value(path) as? String { return Int(value) ?? 0 }
        return 0
    }

    func decimal(_ path: String) -> Double? {
        if let value = value(path) as? NSNumber { return value.doubleValue }
        if let value = value(path) as? Double { return value }
        if let value = value(path) as? String { return Double(value) }
        return nil
    }

    func boolean(_ path: String) -> Bool {
        if let value = value(path) as? Bool { return value }
        if let value = value(path) as? NSNumber { return value.boolValue }
        return false
    }

    func strings(_ path: String) -> [String] {
        if let values = value(path) as? [String] { return values }
        if let values = value(path) as? [Any] { return values.compactMap { $0 as? String } }
        return []
    }

    var version: Int { integer("version") }

    var status: String {
        string("status", "verificationStatus", "moderationStatus").lowercased()
    }

    var moderationStatus: String { string("moderationStatus").lowercased() }

    var title: String {
        let resolved = string(
            "pet.name", "pet.displayName", "petName", "name", "title", "organizationName",
            "moderationCaseId", "alertType", "type", "action"
        )
        return resolved.isEmpty ? shortID : resolved
    }

    var subtitle: String {
        let area = [string("area.district"), string("area.city"), string("area.countryCode")]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        if !area.isEmpty { return area }
        let candidate = string("description", "latestReason", "reason", "ownerUid", "reporterUid", "applicantUid")
        return candidate.isEmpty ? shortID : candidate
    }

    var shortID: String {
        guard id.count > 14 else { return id }
        return "\(id.prefix(7))…\(id.suffix(5))"
    }

    var contextID: String {
        if source == .sightings {
            let caseID = string("caseId")
            return caseID.isEmpty ? id : "\(caseID)~\(id)"
        }
        return id
    }

    var primaryMediaURL: URL? {
        mediaURL(
            "media.0.thumbnailUrl", "media.0.previewUrl", "media.0.url",
            "pet.media.0.thumbnailUrl", "pet.media.0.url", "logo.thumbnailUrl", "logo.url"
        )
    }

    var missingComparisonMediaURL: URL? {
        mediaURL(
            "comparison.missing.media.0.thumbnailUrl", "comparison.missing.media.0.previewUrl", "comparison.missing.media.0.url",
            "comparison.missing.pet.media.0.thumbnailUrl", "comparison.missing.pet.media.0.url"
        )
    }

    var foundComparisonMediaURL: URL? {
        mediaURL(
            "comparison.found.media.0.thumbnailUrl", "comparison.found.media.0.previewUrl", "comparison.found.media.0.url"
        )
    }

    private func mediaURL(_ paths: String...) -> URL? {
        for path in paths {
            if let raw = indexedValue(path) as? String,
               let url = URL(string: raw),
               ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                return url
            }
        }
        return nil
    }

    private func indexedValue(_ path: String) -> Any? {
        var current: Any = values
        for component in path.split(separator: ".").map(String.init) {
            if let index = Int(component), let array = current as? [Any], array.indices.contains(index) {
                current = array[index]
            } else if let dictionary = current as? [String: Any], let next = dictionary[component] {
                current = next
            } else if let dictionary = current as? NSDictionary, let next = dictionary[component] {
                current = next
            } else {
                return nil
            }
        }
        return current
    }

    func coordinate(prefersPrecise: Bool) -> CLLocationCoordinate2D? {
        let roots = prefersPrecise
            ? ["private.exactLocation", "private.location", "publicLocation"]
            : ["publicLocation"]
        for root in roots {
            let latitude = decimal("\(root).latitude") ?? decimal("\(root).lat")
            let longitude = decimal("\(root).longitude") ?? decimal("\(root).lng")
            if let latitude, let longitude,
               (-90...90).contains(latitude), (-180...180).contains(longitude) {
                return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
        }
        return nil
    }

    var lastUpdatedText: String {
        CommunityAdminDateFormatter.text(value("updatedAt") ?? value("createdAt"))
    }
}

private enum CommunityAdminDateFormatter {
    static func text(_ value: Any?) -> String {
        guard let date = date(value) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: Language.isRTL() ? "ar" : "en")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func date(_ value: Any?) -> Date? {
        if let date = value as? Date { return date }
        if let string = value as? String {
            let iso = ISO8601DateFormatter()
            if let parsed = iso.date(from: string) { return parsed }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fractional.date(from: string)
        }
        if let number = value as? NSNumber { return Date(timeIntervalSince1970: number.doubleValue) }
        if let dictionary = value as? [String: Any] {
            let seconds = (dictionary["_seconds"] as? NSNumber)?.doubleValue
                ?? (dictionary["seconds"] as? NSNumber)?.doubleValue
            if let seconds { return Date(timeIntervalSince1970: seconds) }
        }
        return nil
    }
}

struct CommunityAdminDossierEvidence: Identifiable {
    let id: String
    private let rawID: String
    private let values: [String: Any]

    init?(values: [String: Any], sectionID: String) {
        guard let rawID = values["id"] as? String,
              !rawID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        self.id = "\(sectionID):\(rawID)"
        self.rawID = rawID
        self.values = values
    }

    private func value(_ path: String) -> Any? {
        var current: Any = values
        for component in path.split(separator: ".").map(String.init) {
            if let dictionary = current as? [String: Any], let next = dictionary[component] {
                current = next
            } else if let dictionary = current as? NSDictionary, let next = dictionary[component] {
                current = next
            } else {
                return nil
            }
        }
        return current
    }

    private func string(_ paths: String...) -> String {
        for path in paths {
            if let raw = value(path) as? String {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return ""
    }

    var title: String {
        let resolved = string("type", "action", "eventType", "contextType", "targetType", "pet.name", "organizationName", "name")
        return resolved.isEmpty ? rawID : resolved
    }

    var subtitle: String {
        let resolved = string("description", "latestReason", "reason", "statusReason", "contextId", "targetId", "actorUid", "userId")
        return resolved.isEmpty ? rawID : resolved
    }

    var status: String { string("status", "verificationStatus", "moderationStatus").lowercased() }

    var timestampText: String {
        CommunityAdminDateFormatter.text(value("updatedAt") ?? value("createdAt") ?? value("timestamp") ?? value("lastMessageAt"))
    }
}

struct CommunityAdminDossierSection: Identifiable {
    let id: String
    let titleKey: String
    let fallbackTitle: String
    let symbol: String
    let evidence: [CommunityAdminDossierEvidence]
}

enum CommunityAdminLane: String, CaseIterable, Identifiable {
    case overview
    case adoptionListings
    case adoptionApplications
    case missingCases
    case foundReports
    case sightings
    case operationsMap
    case matches
    case moderation
    case media
    case organizations
    case alerts
    case configuration
    case analytics
    case audit

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .overview: return "Community_Admin_Overview"
        case .adoptionListings: return "Community_Admin_Adoptions"
        case .adoptionApplications: return "Community_Admin_Applications"
        case .missingCases: return "Community_Admin_MissingCases"
        case .foundReports: return "Community_Admin_FoundReports"
        case .sightings: return "Community_Admin_Sightings"
        case .operationsMap: return "Community_Admin_OperationsMap"
        case .matches: return "Community_Admin_Matches"
        case .moderation: return "Community_Admin_Moderation"
        case .media: return "Community_Admin_MediaReview"
        case .organizations: return "Community_Admin_Organizations"
        case .alerts: return "Community_Admin_Alerts"
        case .configuration: return "Community_Admin_Configuration"
        case .analytics: return "Community_Admin_Analytics"
        case .audit: return "Community_Admin_Audit"
        }
    }

    var fallbackTitle: String {
        switch self {
        case .overview: return "نظرة عامة"
        case .adoptionListings: return "التبني"
        case .adoptionApplications: return "طلبات التبني"
        case .missingCases: return "حالات الفقدان"
        case .foundReports: return "بلاغات العثور"
        case .sightings: return "المشاهدات"
        case .operationsMap: return "خريطة العمليات"
        case .matches: return "المطابقات"
        case .moderation: return "الثقة والسلامة"
        case .media: return "مراجعة الوسائط"
        case .organizations: return "المنظمات"
        case .alerts: return "التنبيهات التشغيلية"
        case .configuration: return "الإعدادات"
        case .analytics: return "التحليلات"
        case .audit: return "سجل التدقيق"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .adoptionListings: return "heart.fill"
        case .adoptionApplications: return "doc.text.fill"
        case .missingCases: return "magnifyingglass"
        case .foundReports: return "hand.raised.fill"
        case .sightings: return "eye.fill"
        case .operationsMap: return "map.fill"
        case .matches: return "sparkles"
        case .moderation: return "shield.lefthalf.filled"
        case .media: return "photo.stack.fill"
        case .organizations: return "building.2.fill"
        case .alerts: return "exclamationmark.triangle.fill"
        case .configuration: return "slider.horizontal.3"
        case .analytics: return "chart.xyaxis.line"
        case .audit: return "checkmark.seal.fill"
        }
    }

    var permission: String {
        switch self {
        case .overview, .adoptionListings, .missingCases, .foundReports, .organizations, .operationsMap:
            return "community.dashboard.view"
        case .adoptionApplications: return "community.application.view"
        case .sightings: return "community.sighting.review"
        case .matches: return "community.match.review"
        case .moderation, .media: return "community.moderation.review"
        case .alerts, .analytics: return "community.analytics.view"
        case .configuration: return "community.configuration.manage"
        case .audit: return "community.audit.view"
        }
    }

    var readAction: String? {
        switch self {
        case .overview: return "overview"
        case .adoptionListings: return "adoption_listings"
        case .adoptionApplications: return "adoption_applications"
        case .missingCases: return "missing_cases"
        case .foundReports: return "found_reports"
        case .sightings: return "sightings"
        case .matches: return "matches"
        case .moderation: return "moderation"
        case .media: return "media"
        case .organizations: return "organizations"
        case .alerts: return "alerts"
        case .configuration: return "configuration"
        case .analytics: return "analytics"
        case .audit: return "audit"
        case .operationsMap: return nil
        }
    }

    var supportsStatusFilter: Bool {
        ![.overview, .operationsMap, .configuration, .analytics, .audit].contains(self)
    }

    var accentColor: Color {
        switch self {
        case .adoptionListings: return Color(hex: "#E11D48")
        case .missingCases: return Color(hex: "#F59E0B")
        case .foundReports: return Color(hex: "#0D9488")
        case .sightings: return Color(hex: "#06B6D4")
        case .matches: return Color(hex: "#6366F1")
        case .adoptionApplications: return Color(hex: "#8B5CF6")
        case .moderation, .alerts: return Color(hex: "#DC2626")
        case .organizations: return Color(hex: "#2563EB")
        case .media: return Color(hex: "#EC4899")
        case .operationsMap: return Color(hex: "#10B981")
        case .analytics: return Color(hex: "#3B82F6")
        case .audit: return Color(hex: "#64748B")
        default: return AdminSurface.primary
        }
    }
}

// MARK: - Configuration model

struct CommunityConfigurationCatalogEntry: Identifiable {
    var id: UUID = UUID()
    var key: String
    var labelAr: String
    var labelEn: String
    var speciesID: String = ""

    init(dictionary: [String: Any]) {
        key = dictionary["id"] as? String ?? ""
        labelAr = dictionary["labelAr"] as? String ?? ""
        labelEn = dictionary["labelEn"] as? String ?? ""
        speciesID = dictionary["speciesId"] as? String ?? ""
    }

    init() {
        key = ""
        labelAr = ""
        labelEn = ""
    }

    func payload(includesSpecies: Bool) -> [String: Any]? {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedKey.range(of: "^[a-z0-9][a-z0-9_-]{1,79}$", options: .regularExpression) != nil,
              !labelAr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !labelEn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var result: [String: Any] = [
            "id": normalizedKey,
            "labelAr": String(labelAr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180)),
            "labelEn": String(labelEn.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180))
        ]
        if includesSpecies {
            result["speciesId"] = String(speciesID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(80))
        }
        return result
    }
}

struct CommunityConfigurationQuestionOption: Identifiable {
    var id: UUID = UUID()
    var key: String
    var labelAr: String
    var labelEn: String

    init(dictionary: [String: Any]) {
        key = dictionary["id"] as? String ?? ""
        labelAr = dictionary["labelAr"] as? String ?? ""
        labelEn = dictionary["labelEn"] as? String ?? ""
    }

    init() {
        key = ""
        labelAr = ""
        labelEn = ""
    }

    func payload() -> [String: Any]? {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedKey.range(of: "^[a-z0-9][a-z0-9_-]{1,79}$", options: .regularExpression) != nil,
              !labelAr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !labelEn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return [
            "id": normalizedKey,
            "labelAr": String(labelAr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180)),
            "labelEn": String(labelEn.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180))
        ]
    }
}

struct CommunityConfigurationQuestion: Identifiable {
    var id: UUID = UUID()
    var key: String
    var titleAr: String
    var titleEn: String
    var type: String
    var required: Bool
    var options: [CommunityConfigurationQuestionOption]

    init(dictionary: [String: Any]) {
        key = dictionary["id"] as? String ?? ""
        titleAr = dictionary["labelAr"] as? String ?? ""
        titleEn = dictionary["labelEn"] as? String ?? ""
        type = dictionary["type"] as? String ?? "text"
        required = (dictionary["required"] as? Bool) ?? false
        let rawOptions = dictionary["options"] as? [[String: Any]] ??
            (dictionary["options"] as? [NSDictionary])?.compactMap { $0 as? [String: Any] } ?? []
        options = rawOptions.map(CommunityConfigurationQuestionOption.init)
    }

    init() {
        key = ""
        titleAr = ""
        titleEn = ""
        type = "text"
        required = false
        options = []
    }

    func payload() -> [String: Any]? {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let supportedTypes = ["text", "long_text", "yes_no", "single_choice", "multiple_choice"]
        guard normalizedKey.range(of: "^[a-z0-9][a-z0-9_-]{1,79}$", options: .regularExpression) != nil,
              !titleAr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !titleEn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              supportedTypes.contains(type),
              options.count <= 20 else { return nil }
        let needsOptions = ["single_choice", "multiple_choice"].contains(type)
        let optionPayload = options.compactMap { $0.payload() }
        if needsOptions && optionPayload.count < 2 { return nil }
        return [
            "id": normalizedKey,
            "labelAr": String(titleAr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180)),
            "labelEn": String(titleEn.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180)),
            "type": type,
            "required": required,
            "options": needsOptions ? optionPayload : []
        ]
    }
}

struct CommunityNotificationTemplateDraft: Identifiable {
    var id: UUID = UUID()
    var key: String
    var arabicTitle: String
    var arabicBody: String
    var englishTitle: String
    var englishBody: String

    init(key: String, dictionary: [String: Any]) {
        self.key = key
        let arabic = dictionary["ar"] as? [String: Any] ?? [:]
        let english = dictionary["en"] as? [String: Any] ?? [:]
        arabicTitle = arabic["title"] as? String ?? ""
        arabicBody = arabic["body"] as? String ?? ""
        englishTitle = english["title"] as? String ?? ""
        englishBody = english["body"] as? String ?? ""
    }

    init() {
        key = ""
        arabicTitle = ""
        arabicBody = ""
        englishTitle = ""
        englishBody = ""
    }

    func payload() -> (String, [String: Any])? {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedKey.range(of: "^[a-z][a-z0-9_]{2,119}$", options: .regularExpression) != nil,
              !arabicTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !arabicBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !englishTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !englishBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return (normalizedKey, [
            "ar": ["title": arabicTitle, "body": arabicBody],
            "en": ["title": englishTitle, "body": englishBody]
        ])
    }
}

struct CommunityConfigurationDraft {
    var version = 0
    var communityEnabled = false
    var adoptionEnabled = false
    var adoptionApplicationsEnabled = false
    var missingPetsEnabled = false
    var foundPetReportsEnabled = false
    var sightingsEnabled = false
    var matchingEnabled = false
    var communityMessagingEnabled = false
    var aiImageMatchingEnabled = false
    var organizationsEnabled = false
    var organizationVerificationEnabled = false
    var adminOperationsMapEnabled = false
    var supportedCountries = ""
    var enabledRegions = ""
    var defaultMissingRadiusKM = 20.0
    var autoMatchThreshold = 0.58
    var mediumMatchConfidenceThreshold = 0.68
    var highMatchConfidenceThreshold = 0.82
    var rolloutStage = "internal"
    var listingExpirationDays = 90.0
    var caseExpirationDays = 90.0
    var applicationPolicy = "owner_managed"
    var sightingPhotoRequired = false
    var highRiskReportThreshold = 3.0
    var autoHideReportThreshold = 5.0
    var requiredOrganizationDocuments = ""
    var species: [CommunityConfigurationCatalogEntry] = []
    var breeds: [CommunityConfigurationCatalogEntry] = []
    var colors: [CommunityConfigurationCatalogEntry] = []
    var sizes: [CommunityConfigurationCatalogEntry] = []
    var temperamentTags: [CommunityConfigurationCatalogEntry] = []
    var adoptionQuestions: [CommunityConfigurationQuestion] = []
    var templates: [CommunityNotificationTemplateDraft] = []

    init() {}

    init(dictionary: [String: Any]) {
        func bool(_ key: String) -> Bool {
            (dictionary[key] as? Bool) ?? (dictionary[key] as? NSNumber)?.boolValue ?? false
        }
        func number(_ key: String, fallback: Double) -> Double {
            (dictionary[key] as? NSNumber)?.doubleValue ?? (dictionary[key] as? Double) ?? fallback
        }
        func dictionaries(_ value: Any?) -> [[String: Any]] {
            value as? [[String: Any]] ?? (value as? [NSDictionary])?.map { $0 as? [String: Any] ?? [:] } ?? []
        }
        version = (dictionary["version"] as? NSNumber)?.intValue ?? (dictionary["version"] as? Int) ?? 0
        communityEnabled = bool("communityEnabled")
        adoptionEnabled = bool("adoptionEnabled")
        adoptionApplicationsEnabled = bool("adoptionApplicationsEnabled")
        missingPetsEnabled = bool("missingPetsEnabled")
        foundPetReportsEnabled = bool("foundPetReportsEnabled")
        sightingsEnabled = bool("sightingsEnabled")
        matchingEnabled = bool("matchingEnabled")
        communityMessagingEnabled = bool("communityMessagingEnabled")
        aiImageMatchingEnabled = bool("aiImageMatchingEnabled")
        organizationsEnabled = bool("organizationsEnabled")
        organizationVerificationEnabled = bool("organizationVerificationEnabled")
        adminOperationsMapEnabled = bool("adminOperationsMapEnabled")
        supportedCountries = (dictionary["supportedCountryCodes"] as? [String] ?? []).joined(separator: ", ")
        enabledRegions = (dictionary["enabledRegionCodes"] as? [String] ?? []).joined(separator: ", ")
        defaultMissingRadiusKM = number("defaultMissingRadiusKm", fallback: 20)
        autoMatchThreshold = number("autoMatchThreshold", fallback: 0.58)
        let calibration = dictionary["matchConfidenceCalibration"] as? [String: Any] ?? [:]
        let requestedMediumThreshold = (calibration["mediumMin"] as? NSNumber)?.doubleValue ?? (calibration["mediumMin"] as? Double) ?? 0.68
        mediumMatchConfidenceThreshold = max(0.5, min(0.94, requestedMediumThreshold))
        let requestedHighThreshold = (calibration["highMin"] as? NSNumber)?.doubleValue ?? (calibration["highMin"] as? Double) ?? 0.82
        highMatchConfidenceThreshold = max(mediumMatchConfidenceThreshold + 0.01, min(0.99, requestedHighThreshold))
        rolloutStage = dictionary["rolloutStage"] as? String ?? "internal"

        let taxonomy = dictionary["taxonomy"] as? [String: Any] ?? [:]
        species = dictionaries(taxonomy["species"]).map(CommunityConfigurationCatalogEntry.init)
        breeds = dictionaries(taxonomy["breeds"]).map(CommunityConfigurationCatalogEntry.init)
        colors = dictionaries(taxonomy["colors"]).map(CommunityConfigurationCatalogEntry.init)
        sizes = dictionaries(taxonomy["sizes"]).map(CommunityConfigurationCatalogEntry.init)
        temperamentTags = dictionaries(taxonomy["temperamentTags"]).map(CommunityConfigurationCatalogEntry.init)

        let adoption = dictionary["adoptionPolicy"] as? [String: Any] ?? [:]
        listingExpirationDays = (adoption["listingExpirationDays"] as? NSNumber)?.doubleValue ?? 90
        applicationPolicy = adoption["applicationPolicy"] as? String ?? "owner_managed"
        adoptionQuestions = dictionaries(adoption["questions"]).map(CommunityConfigurationQuestion.init)

        let lostFound = dictionary["lostFoundPolicy"] as? [String: Any] ?? [:]
        caseExpirationDays = (lostFound["caseExpirationDays"] as? NSNumber)?.doubleValue ?? 90
        sightingPhotoRequired = (lostFound["sightingPhotoRequired"] as? Bool) ?? false

        let moderation = dictionary["moderationPolicy"] as? [String: Any] ?? [:]
        highRiskReportThreshold = (moderation["highRiskReportThreshold"] as? NSNumber)?.doubleValue ?? 3
        autoHideReportThreshold = (moderation["autoHideReportThreshold"] as? NSNumber)?.doubleValue ?? 5

        let organization = dictionary["organizationPolicy"] as? [String: Any] ?? [:]
        requiredOrganizationDocuments = (organization["requiredDocumentTypes"] as? [String] ?? []).joined(separator: ", ")

        let templateDictionary = dictionary["notificationTemplates"] as? [String: Any] ?? [:]
        templates = templateDictionary.compactMap { key, value in
            guard let item = value as? [String: Any] else { return nil }
            return CommunityNotificationTemplateDraft(key: key, dictionary: item)
        }.sorted { $0.key < $1.key }
    }

    private func codeList(_ text: String, max limit: Int, uppercased: Bool = true) -> [String] {
        var seen = Set<String>()
        let items = text
            .components(separatedBy: CharacterSet(charactersIn: ",\n;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { uppercased ? $0.uppercased() : $0 }
            .filter { seen.insert($0).inserted }
        return Array(items.prefix(limit))
    }

    func validationError() -> String? {
        let catalogs: [[CommunityConfigurationCatalogEntry]] = [species, breeds, colors, sizes, temperamentTags]
        if catalogs.contains(where: { $0.count > 500 || $0.contains(where: { $0.payload(includesSpecies: false) == nil }) }) {
            return Language.get("Community_Admin_Config_Error_Catalog", alter: "أكمل معرّفات وتسميات العربية والإنجليزية لكل عنصر تصنيف.")
        }
        for catalog in catalogs {
            let keys = catalog.map { $0.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            if Set(keys).count != keys.count {
                return Language.get("Community_Admin_Config_Error_Duplicate", alter: "توجد معرّفات مكررة في إعدادات المجتمع.")
            }
        }
        let speciesKeys = Set(species.map { $0.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        if breeds.contains(where: {
            let parent = $0.speciesID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return parent.isEmpty || !speciesKeys.contains(parent) || $0.payload(includesSpecies: true) == nil
        }) {
            return Language.get("Community_Admin_Config_Error_BreedParent", alter: "اربط كل سلالة بمعرّف نوع صالح.")
        }
        if adoptionQuestions.count > 40 || adoptionQuestions.contains(where: { $0.payload() == nil }) {
            return Language.get("Community_Admin_Config_Error_Questions", alter: "أكمل كل سؤال بالعربية والإنجليزية، وأضف خيارين صالحين على الأقل لأسئلة الاختيار.")
        }
        let questionKeys = adoptionQuestions.map { $0.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if Set(questionKeys).count != questionKeys.count || adoptionQuestions.contains(where: { question in
            let keys = question.options.map { $0.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            return Set(keys).count != keys.count
        }) {
            return Language.get("Community_Admin_Config_Error_Duplicate", alter: "توجد معرّفات مكررة في إعدادات المجتمع.")
        }
        if templates.count > 30 || templates.contains(where: { $0.payload() == nil }) {
            return Language.get("Community_Admin_Config_Error_Templates", alter: "أكمل مفاتيح وعناوين ونصوص العربية والإنجليزية لكل قالب إشعار.")
        }
        let templateKeys = templates.map { $0.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if Set(templateKeys).count != templateKeys.count {
            return Language.get("Community_Admin_Config_Error_Duplicate", alter: "توجد معرّفات مكررة في إعدادات المجتمع.")
        }
        return nil
    }

    func payload() -> [String: Any] {
        var templatePayload: [String: Any] = [:]
        for template in templates.prefix(30) {
            if let (key, value) = template.payload() { templatePayload[key] = value }
        }
        return [
            "communityEnabled": communityEnabled,
            "adoptionEnabled": adoptionEnabled,
            "adoptionApplicationsEnabled": adoptionApplicationsEnabled,
            "missingPetsEnabled": missingPetsEnabled,
            "foundPetReportsEnabled": foundPetReportsEnabled,
            "sightingsEnabled": sightingsEnabled,
            "matchingEnabled": matchingEnabled,
            "communityMessagingEnabled": communityMessagingEnabled,
            "aiImageMatchingEnabled": aiImageMatchingEnabled,
            "organizationsEnabled": organizationsEnabled,
            "organizationVerificationEnabled": organizationVerificationEnabled,
            "adminOperationsMapEnabled": adminOperationsMapEnabled,
            "supportedCountryCodes": codeList(supportedCountries, max: 30),
            "enabledRegionCodes": codeList(enabledRegions, max: 100),
            "defaultMissingRadiusKm": max(1, min(100, defaultMissingRadiusKM)),
            "autoMatchThreshold": max(0.5, min(0.95, autoMatchThreshold)),
            "matchConfidenceCalibration": [
                "mediumMin": max(0.5, min(0.94, mediumMatchConfidenceThreshold)),
                "highMin": max(max(0.51, mediumMatchConfidenceThreshold + 0.01), min(0.99, highMatchConfidenceThreshold))
            ],
            "rolloutStage": rolloutStage,
            "taxonomy": [
                "species": species.compactMap { $0.payload(includesSpecies: false) },
                "breeds": breeds.compactMap { $0.payload(includesSpecies: true) },
                "colors": colors.compactMap { $0.payload(includesSpecies: false) },
                "sizes": sizes.compactMap { $0.payload(includesSpecies: false) },
                "temperamentTags": temperamentTags.compactMap { $0.payload(includesSpecies: false) }
            ],
            "adoptionPolicy": [
                "questions": adoptionQuestions.compactMap { $0.payload() },
                "listingExpirationDays": max(7, min(365, listingExpirationDays)),
                "applicationPolicy": applicationPolicy
            ],
            "lostFoundPolicy": [
                "caseExpirationDays": max(7, min(365, caseExpirationDays)),
                "sightingPhotoRequired": sightingPhotoRequired
            ],
            "moderationPolicy": [
                "highRiskReportThreshold": max(1, min(20, highRiskReportThreshold)),
                "autoHideReportThreshold": max(2, min(50, autoHideReportThreshold))
            ],
            "organizationPolicy": [
                "requiredDocumentTypes": codeList(requiredOrganizationDocuments, max: 30, uppercased: false)
            ],
            "notificationTemplates": templatePayload
        ]
    }
}

// MARK: - Callable service

enum AdminCommunityServiceError: LocalizedError {
    case unauthenticated
    case permissionDenied
    case stale
    case invalidResponse
    case server(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return Language.get("Community_Admin_Error_Unauthenticated", alter: "انتهت الجلسة. سجّل الدخول مجددًا.")
        case .permissionDenied:
            return Language.get("Community_Admin_Error_Permission", alter: "لا تملك الصلاحية المطلوبة لهذه العملية.")
        case .stale:
            return Language.get("Community_Admin_Error_Stale", alter: "تغيّر السجل على الخادم. أعد التحميل قبل المتابعة.")
        case .invalidResponse:
            return Language.get("Community_Admin_Error_Response", alter: "وصلت استجابة غير صالحة من خادم المجتمع.")
        case .server(let message), .transport(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.caseInsensitiveCompare("INTERNAL") == .orderedSame ||
               trimmed.localizedCaseInsensitiveContains("internal") ||
               trimmed.contains("FIRFunctionsErrorDomain") {
                return Language.get("Community_Admin_Error_ServerSync", alter: "تعذرت المزامنة مع الخادم مؤقتاً. يجري تجهيز البيانات.")
            }
            if trimmed.caseInsensitiveCompare("UNAVAILABLE") == .orderedSame ||
               trimmed.localizedCaseInsensitiveContains("unavailable") {
                return Language.get("Community_Admin_Error_Unavailable", alter: "الخدمة غير متوفرة حالياً. يرجى المحاولة بعد قليل.")
            }
            return trimmed.isEmpty ? Language.get("Community_Admin_Error_Generic", alter: "حدث خطأ غير متوقع. أعد المحاولة.") : trimmed
        }
    }
}

@MainActor
final class AdminCommunityService {
    static let shared = AdminCommunityService()

    private let functions = Functions.functions(region: "us-central1")
    private let commandStore = UserDefaults.standard
    private let timeout: TimeInterval = 30

    private struct SendablePayload: @unchecked Sendable {
        let value: [String: Any]
    }

    private init() {}

    func read(
        action: String,
        status: String = "",
        cursor: String? = nil,
        ownerUID: String = "",
        limit: Int = 60,
        includePreciseLocation: Bool = false,
        includePrivateOrganization: Bool = false,
        includeSensitiveMatchEvidence: Bool = false,
        privateAccessReason: String = ""
    ) async throws -> [String: Any] {
        var payload: [String: Any] = ["action": action, "limit": max(1, min(200, limit))]
        if !status.isEmpty { payload["status"] = status }
        if let cursor, !cursor.isEmpty { payload["cursor"] = cursor }
        if !ownerUID.isEmpty { payload["ownerUid"] = ownerUID }
        if includePreciseLocation { payload["includePreciseLocation"] = true }
        if includePrivateOrganization { payload["includePrivateOrganization"] = true }
        if includeSensitiveMatchEvidence { payload["includeSensitiveMatchEvidence"] = true }
        if includePreciseLocation || includePrivateOrganization || includeSensitiveMatchEvidence {
            payload["privateAccessReason"] = privateAccessReason
        }
        return try await call(name: "communityAdminRead", payload: payload)
    }

    func dossier(
        targetType: String,
        targetID: String,
        includePreciseLocation: Bool,
        includePrivateOrganization: Bool,
        includeSensitiveMatchEvidence: Bool = false,
        privateAccessReason: String = ""
    ) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "action": "dossier",
            "targetType": targetType,
            "targetId": targetID
        ]
        if includePreciseLocation { payload["includePreciseLocation"] = true }
        if includePrivateOrganization { payload["includePrivateOrganization"] = true }
        if includeSensitiveMatchEvidence { payload["includeSensitiveMatchEvidence"] = true }
        if includePreciseLocation || includePrivateOrganization || includeSensitiveMatchEvidence {
            payload["privateAccessReason"] = privateAccessReason
        }
        return try await call(name: "communityAdminRead", payload: payload)
    }

    func moderate(
        targetType: String,
        targetID: String,
        action: String,
        expectedVersion: Int,
        reason: String,
        duplicateOfID: String = ""
    ) async throws -> [String: Any] {
        var payload: [String: Any] = [
            "targetType": targetType,
            "targetId": targetID,
            "action": action,
            "expectedVersion": expectedVersion,
            "reason": reason
        ]
        if !duplicateOfID.isEmpty { payload["duplicateOfId"] = duplicateOfID }
        return try await mutation(name: "communityModerationCommand", action: "\(targetType):\(action)", payload: payload)
    }

    func updateConfiguration(_ draft: CommunityConfigurationDraft, reason: String) async throws -> [String: Any] {
        try await mutation(
            name: "communityConfigurationCommand",
            action: "save",
            payload: ["expectedVersion": draft.version, "configuration": draft.payload(), "reason": reason]
        )
    }

    func updateAlert(_ record: CommunityAdminRecord, action: String, reason: String) async throws -> [String: Any] {
        try await mutation(
            name: "communityOperationalAlertCommand",
            action: action,
            payload: ["alertId": record.id, "action": action, "expectedVersion": record.version, "reason": reason]
        )
    }

    private func mutation(name: String, action: String, payload: [String: Any]) async throws -> [String: Any] {
        let fingerprint = commandFingerprint(name: name, action: action, payload: payload)
        let key = "pp.community.admin.command.\(fingerprint)"
        let commandID = commandStore.string(forKey: key)
            ?? "community-admin-\(UUID().uuidString.lowercased())"
        commandStore.set(commandID, forKey: key)
        var body = payload
        body["commandId"] = commandID
        do {
            let response = try await call(name: name, payload: body)
            commandStore.removeObject(forKey: key)
            return response
        } catch {
            // Keeping the command ID is intentional. A transport timeout may
            // occur after the transaction committed, so retry must reconcile
            // through the exact same server receipt.
            throw error
        }
    }

    private func commandFingerprint(name: String, action: String, payload: [String: Any]) -> String {
        let envelope: [String: Any] = [
            "uid": Auth.auth().currentUser?.uid ?? "",
            "name": name,
            "action": action,
            "payload": payload
        ]
        let data = (try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])) ?? Data()
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func call(name: String, payload: [String: Any]) async throws -> [String: Any] {
        let callable = functions.httpsCallable(name)
        callable.timeoutInterval = timeout
        let boxed = SendablePayload(value: payload)
        do {
            let result = try await callable.call(boxed.value)
            guard let response = result.data as? [String: Any] else {
                throw AdminCommunityServiceError.invalidResponse
            }
            guard response["ok"] as? Bool == true else {
                if let message = response["message"] as? String,
                   !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw AdminCommunityServiceError.server(message)
                }
                throw AdminCommunityServiceError.invalidResponse
            }
            return response
        } catch let known as AdminCommunityServiceError {
            throw known
        } catch let error as NSError {
            guard error.domain == FunctionsErrorDomain else {
                throw AdminCommunityServiceError.transport(error.localizedDescription)
            }
            switch FunctionsErrorCode(rawValue: error.code) {
            case .unauthenticated: throw AdminCommunityServiceError.unauthenticated
            case .permissionDenied: throw AdminCommunityServiceError.permissionDenied
            case .aborted: throw AdminCommunityServiceError.stale
            case .cancelled, .unknown, .deadlineExceeded, .internal, .unavailable, .dataLoss:
                throw AdminCommunityServiceError.transport(error.localizedDescription)
            default:
                throw AdminCommunityServiceError.server(error.localizedDescription)
            }
        }
    }
}

// MARK: - State owner

@MainActor
final class AdminCommunityWorkspaceStore: ObservableObject {
    @Published private(set) var selectedLane: CommunityAdminLane = .overview
    @Published private(set) var records: [CommunityAdminRecord] = []
    @Published var selectedRecord: CommunityAdminRecord?
    @Published private(set) var dossierRecord: CommunityAdminRecord?
    @Published private(set) var dossierSections: [CommunityAdminDossierSection] = []
    @Published private(set) var overview: [String: Int] = [:]
    @Published private(set) var attentionRecords: [CommunityAdminRecord] = []
    @Published private(set) var diagnostics: [String: Any] = [:]
    @Published private(set) var analytics: [String: Any] = [:]
    @Published private(set) var operationsMapEnabled = false
    @Published var configuration = CommunityConfigurationDraft()
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isLoadingDossier = false
    @Published private(set) var isMutating = false
    @Published private(set) var hasMore = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var dossierErrorMessage: String?
    @Published private(set) var successMessage: String?
    @Published var statusFilter = ""
    @Published var searchText = ""
    @Published var includePreciseLocation = false
    @Published var includePrivateOrganization = false
    @Published var includeSensitiveMatchEvidence = false
    @Published var privateAccessReason = ""

    let session: AdminSession
    private let service: AdminCommunityService
    private var nextCursor: String?
    private var loadGeneration = UUID()
    private var dossierGeneration = UUID()

    init(
        session: AdminSession,
        initialLane: CommunityAdminLane = .overview,
        service: AdminCommunityService = .shared
    ) {
        self.session = session
        self.service = service
        self.selectedLane = initialLane
    }

    var availableLanes: [CommunityAdminLane] {
        CommunityAdminLane.allCases.filter { lane in
            canAccess(lane) && (lane != .operationsMap || operationsMapEnabled)
        }
    }

    func canAccess(_ lane: CommunityAdminLane) -> Bool {
        if session.isAdmin || session.grantsAllPermissions {
            return true
        }
        let hasLanePermission: Bool
        switch lane {
        case .overview:
            hasLanePermission = session.hasPermission("community.dashboard.view") ||
                                session.hasPermission("community.adoption.moderate") ||
                                session.hasPermission("moderation.view") ||
                                session.hasPermission("moderation.manage") ||
                                session.hasPermission("listings.moderate")
        case .adoptionListings:
            hasLanePermission = session.hasPermission("community.dashboard.view") ||
                                session.hasPermission("community.adoption.moderate") ||
                                session.hasPermission("moderation.view") ||
                                session.hasPermission("moderation.manage") ||
                                session.hasPermission("listings.moderate") ||
                                session.hasPermission("listings.view") ||
                                session.hasPermission("listings.manage") ||
                                session.hasPermission("Adoption")
        case .adoptionApplications:
            hasLanePermission = session.hasPermission("community.application.view") ||
                                session.hasPermission("community.adoption.moderate") ||
                                session.hasPermission("moderation.view") ||
                                session.hasPermission("moderation.manage")
        case .missingCases, .foundReports:
            hasLanePermission = session.hasPermission("community.dashboard.view") ||
                                session.hasPermission("community.missing.moderate") ||
                                session.hasPermission("moderation.view") ||
                                session.hasPermission("moderation.manage")
        case .moderation, .media:
            hasLanePermission = session.hasPermission(lane.permission) ||
                                session.hasPermission("moderation.view") ||
                                session.hasPermission("moderation.manage") ||
                                session.hasPermission("listings.moderate")
        default:
            hasLanePermission = session.hasPermission(lane.permission)
        }
        return hasLanePermission && (session.hasGlobalScope || session.isAdmin || lane == .adoptionListings)
    }

    var canViewPreciseLocation: Bool {
        session.isAdmin || session.grantsAllPermissions || (session.hasPermission("community.location.precise") && (session.hasGlobalScope || session.isAdmin))
    }

    var canViewSensitiveMatchEvidence: Bool {
        session.isAdmin || session.grantsAllPermissions || (session.hasPermission("community.match.sensitive_evidence") && (session.hasGlobalScope || session.isAdmin))
    }

    var canResolveModeration: Bool {
        session.isAdmin || session.grantsAllPermissions || (session.hasPermission("community.moderation.resolve") && (session.hasGlobalScope || session.isAdmin)) || session.hasPermission("moderation.manage")
    }

    var filteredRecords: [CommunityAdminRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return records }
        return records.filter { record in
            [record.id, record.title, record.subtitle, record.status,
             record.string("ownerUid"), record.string("reporterUid"), record.string("applicantUid")]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    func start() async {
        guard let first = availableLanes.first else {
            errorMessage = Language.get("Community_Admin_Error_NoAccess", alter: "لا توجد صلاحيات مجتمع متاحة لهذه الجلسة.")
            return
        }
        if !availableLanes.contains(selectedLane) { selectedLane = first }
        await load(reset: true)
    }

    func select(_ lane: CommunityAdminLane) {
        guard canAccess(lane), lane != selectedLane else { return }
        selectedLane = lane
        statusFilter = ""
        searchText = ""
        includePreciseLocation = false
        includePrivateOrganization = false
        includeSensitiveMatchEvidence = false
        privateAccessReason = ""
        Task { await load(reset: true) }
    }

    func refresh() async { await load(reset: true) }

    func applyFilters() async { await load(reset: true) }

    func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        await load(reset: false)
    }

    func setPreciseLocation(_ enabled: Bool) async {
        guard canViewPreciseLocation else {
            includePreciseLocation = false
            errorMessage = AdminCommunityServiceError.permissionDenied.localizedDescription
            return
        }
        guard !enabled || hasPrivateAccessReason else {
            includePreciseLocation = false
            errorMessage = privateAccessReasonRequiredMessage
            return
        }
        includePreciseLocation = enabled
        await load(reset: true)
        refreshOpenDossierIfNeeded()
    }

    func setPrivateOrganization(_ enabled: Bool) async {
        guard session.hasPermission("community.organization.verify"), session.hasGlobalScope else {
            includePrivateOrganization = false
            errorMessage = AdminCommunityServiceError.permissionDenied.localizedDescription
            return
        }
        guard !enabled || hasPrivateAccessReason else {
            includePrivateOrganization = false
            errorMessage = privateAccessReasonRequiredMessage
            return
        }
        includePrivateOrganization = enabled
        await load(reset: true)
        refreshOpenDossierIfNeeded()
    }

    func setSensitiveMatchEvidence(_ enabled: Bool) async {
        guard canViewSensitiveMatchEvidence else {
            includeSensitiveMatchEvidence = false
            errorMessage = AdminCommunityServiceError.permissionDenied.localizedDescription
            return
        }
        guard !enabled || hasPrivateAccessReason else {
            includeSensitiveMatchEvidence = false
            errorMessage = privateAccessReasonRequiredMessage
            return
        }
        includeSensitiveMatchEvidence = enabled
        if selectedLane == .matches { await load(reset: true) }
        refreshOpenDossierIfNeeded()
    }

    private var hasPrivateAccessReason: Bool {
        privateAccessReason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }

    private var privateAccessReasonRequiredMessage: String {
        Language.get(
            "Community_Admin_Private_Access_Reason_Required",
            alter: "اكتب سببًا واضحًا قبل إظهار البيانات الخاصة."
        )
    }

    private func refreshOpenDossierIfNeeded() {
        if let selectedRecord { loadDossier(selectedRecord) }
    }

    func openDossier(_ record: CommunityAdminRecord) {
        selectedRecord = record
        loadDossier(record)
    }

    func loadDossier(_ record: CommunityAdminRecord) {
        guard let targetType = dossierTargetType(for: record.source) else {
            dossierErrorMessage = AdminCommunityServiceError.server(
                Language.get("Community_Admin_Error_Unsupported", alter: "هذه العملية غير مدعومة لهذا السجل.")
            ).localizedDescription
            return
        }
        let generation = UUID()
        dossierGeneration = generation
        dossierRecord = nil
        dossierSections = []
        dossierErrorMessage = nil
        isLoadingDossier = true
        let shouldIncludePreciseLocation = includePreciseLocation && canViewPreciseLocation &&
            [.missingCases, .foundReports, .sightings].contains(record.source)
        let shouldIncludePrivateOrganization = includePrivateOrganization &&
            session.hasPermission("community.organization.verify") && session.hasGlobalScope &&
            record.source == .organizations
        let shouldIncludeSensitiveMatchEvidence = includeSensitiveMatchEvidence &&
            canViewSensitiveMatchEvidence && record.source == .matches
        Task {
            await fetchDossier(
                record,
                targetType: targetType,
                includePreciseLocation: shouldIncludePreciseLocation,
                includePrivateOrganization: shouldIncludePrivateOrganization,
                includeSensitiveMatchEvidence: shouldIncludeSensitiveMatchEvidence,
                generation: generation
            )
        }
    }

    func dismissDossier() {
        dossierGeneration = UUID()
        dossierRecord = nil
        dossierSections = []
        dossierErrorMessage = nil
        isLoadingDossier = false
    }

    func perform(
        record: CommunityAdminRecord,
        action: String,
        reason: String,
        duplicateOfID: String = ""
    ) async -> Bool {
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedReason.count >= 3 else {
            errorMessage = Language.get("Community_Admin_Error_Reason", alter: "اكتب سببًا واضحًا لا يقل عن 3 أحرف.")
            return false
        }
        guard record.version > 0 else {
            errorMessage = Language.get("Community_Admin_Error_Version", alter: "إصدار السجل غير صالح. أعد التحميل.")
            return false
        }
        isMutating = true
        errorMessage = nil
        successMessage = nil
        defer { isMutating = false }
        do {
            if record.source == .alerts {
                _ = try await service.updateAlert(record, action: action, reason: normalizedReason)
            } else {
                guard let targetType = targetType(for: record.source) else {
                    throw AdminCommunityServiceError.server(Language.get("Community_Admin_Error_Unsupported", alter: "هذه العملية غير مدعومة لهذا السجل."))
                }
                _ = try await service.moderate(
                    targetType: targetType,
                    targetID: record.contextID,
                    action: action,
                    expectedVersion: record.version,
                    reason: normalizedReason,
                    duplicateOfID: duplicateOfID.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            successMessage = Language.get("Community_Admin_Action_Succeeded", alter: "تم تنفيذ العملية وتسجيلها في سجل التدقيق.")
            selectedRecord = nil
            dismissDossier()
            await load(reset: true)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            errorMessage = humanizedMessage(for: error)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
    }

    func saveConfiguration(reason: String) async -> Bool {
        if let validationError = configuration.validationError() {
            errorMessage = validationError
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedReason.count >= 3 else {
            errorMessage = Language.get("Community_Admin_Config_Reason_Required", alter: "اكتب سببًا واضحًا لتغيير إعدادات المجتمع.")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
        isMutating = true
        errorMessage = nil
        successMessage = nil
        defer { isMutating = false }
        do {
            _ = try await service.updateConfiguration(configuration, reason: normalizedReason)
            successMessage = Language.get("Community_Admin_Config_Saved", alter: "حُفظت إعدادات المجتمع بأمان.")
            await load(reset: true)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            errorMessage = humanizedMessage(for: error)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
    }

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }

    private func humanizedMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.caseInsensitiveCompare("INTERNAL") == .orderedSame ||
           message.localizedCaseInsensitiveContains("internal") ||
           message.contains("FIRFunctionsErrorDomain") {
            return Language.get("Community_Admin_Error_ServerSync", alter: "تعذرت المزامنة مع الخادم مؤقتاً. يجري تجهيز البيانات.")
        }
        if message.caseInsensitiveCompare("UNAVAILABLE") == .orderedSame ||
           message.localizedCaseInsensitiveContains("unavailable") {
            return Language.get("Community_Admin_Error_Unavailable", alter: "الخدمة غير متوفرة حالياً. يرجى المحاولة بعد قليل.")
        }
        return message.isEmpty ? Language.get("Community_Admin_Error_Generic", alter: "حدث خطأ غير متوقع. أعد المحاولة.") : message
    }

    private func load(reset: Bool) async {
        guard canAccess(selectedLane) else {
            errorMessage = AdminCommunityServiceError.permissionDenied.localizedDescription
            return
        }
        if reset {
            guard !isLoading else { return }
            isLoading = true
        } else {
            guard !isLoadingMore else { return }
            isLoadingMore = true
        }
        let generation = reset ? UUID() : loadGeneration
        if reset { loadGeneration = generation }
        errorMessage = nil
        if reset { nextCursor = nil; hasMore = false }
        defer {
            if reset { isLoading = false } else { isLoadingMore = false }
        }

        do {
            switch selectedLane {
            case .overview:
                let response = try await service.read(action: "overview")
                guard generation == loadGeneration else { return }
                overview = Self.integerDictionary(response["overview"])
                operationsMapEnabled = Self.dictionary(response["configuration"])["adminOperationsMapEnabled"] as? Bool == true
                if canAccess(.analytics) {
                    let diagnosticResponse = try await service.read(action: "diagnostics")
                    guard generation == loadGeneration else { return }
                    diagnostics = Self.dictionary(diagnosticResponse["diagnostics"])
                } else {
                    diagnostics = [:]
                }
                var attention: [CommunityAdminRecord] = []
                if let pendingMissing = try? await service.read(action: "missing_cases", status: "pending_review", limit: 8) {
                    attention += Self.recordArray(pendingMissing["items"], source: .missingCases)
                }
                if canAccess(.matches),
                   let pendingMatches = try? await service.read(action: "matches", status: "pending_review", limit: 8) {
                    attention += Self.recordArray(pendingMatches["items"], source: .matches)
                }
                if canAccess(.moderation),
                   let highRisk = try? await service.read(action: "moderation", status: "open", limit: 8) {
                    attention += Self.recordArray(highRisk["items"], source: .moderation)
                        .filter { $0.string("priority") == "high" }
                }
                if canAccess(.alerts),
                   let openAlerts = try? await service.read(action: "alerts", status: "open", limit: 8) {
                    attention += Self.recordArray(openAlerts["items"], source: .alerts)
                }
                guard generation == loadGeneration else { return }
                attentionRecords = Array(Self.deduplicated(attention).prefix(12))
                records = []
            case .configuration:
                let response = try await service.read(action: "configuration")
                guard generation == loadGeneration else { return }
                configuration = CommunityConfigurationDraft(dictionary: Self.dictionary(response["configuration"]))
                operationsMapEnabled = configuration.adminOperationsMapEnabled
                records = []
            case .analytics:
                let response = try await service.read(action: "analytics")
                guard generation == loadGeneration else { return }
                analytics = Self.dictionary(response["analytics"])
                records = []
            case .operationsMap:
                try await loadOperationsMap(generation: generation)
            default:
                guard let action = selectedLane.readAction else { return }
                let response = try await service.read(
                    action: action,
                    status: statusFilter,
                    cursor: reset ? nil : nextCursor,
                    includePreciseLocation: includePreciseLocation,
                    includePrivateOrganization: includePrivateOrganization,
                    includeSensitiveMatchEvidence: includeSensitiveMatchEvidence && selectedLane == .matches,
                    privateAccessReason: privateAccessReason.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                guard generation == loadGeneration else { return }
                let page = Self.recordArray(response["items"], source: selectedLane)
                records = reset ? page : Self.deduplicated(records + page)
                nextCursor = response["nextCursor"] as? String
                hasMore = (response["hasMore"] as? Bool) == true && nextCursor != nil
            }
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = humanizedMessage(for: error)
        }
    }

    private func fetchDossier(
        _ sourceRecord: CommunityAdminRecord,
        targetType: String,
        includePreciseLocation: Bool,
        includePrivateOrganization: Bool,
        includeSensitiveMatchEvidence: Bool,
        generation: UUID
    ) async {
        defer {
            if generation == dossierGeneration { isLoadingDossier = false }
        }
        do {
            let response = try await service.dossier(
                targetType: targetType,
                targetID: sourceRecord.contextID,
                includePreciseLocation: includePreciseLocation,
                includePrivateOrganization: includePrivateOrganization,
                includeSensitiveMatchEvidence: includeSensitiveMatchEvidence,
                privateAccessReason: privateAccessReason.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            guard generation == dossierGeneration else { return }
            guard let canonicalRecord = CommunityAdminRecord(
                values: Self.dictionary(response["record"]),
                source: sourceRecord.source
            ) else {
                throw AdminCommunityServiceError.invalidResponse
            }
            dossierRecord = canonicalRecord
            dossierSections = Self.dossierSections(response["related"])
        } catch {
            guard generation == dossierGeneration else { return }
            dossierErrorMessage = humanizedMessage(for: error)
        }
    }

    private func loadOperationsMap(generation: UUID) async throws {
        let precise = includePreciseLocation && canViewPreciseLocation
        let sightingsAllowed = canAccess(.sightings)
        let reason = privateAccessReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let missing = try await service.read(action: "missing_cases", limit: 200, includePreciseLocation: precise, privateAccessReason: reason)
        let found = try await service.read(action: "found_reports", limit: 200, includePreciseLocation: precise, privateAccessReason: reason)
        var all = Self.recordArray(missing["items"], source: .missingCases)
            + Self.recordArray(found["items"], source: .foundReports)
        if sightingsAllowed {
            let sightings = try await service.read(action: "sightings", limit: 200, includePreciseLocation: precise, privateAccessReason: reason)
            all += Self.recordArray(sightings["items"], source: .sightings)
        }
        guard generation == loadGeneration else { return }
        records = Self.deduplicated(all)
        hasMore = false
        nextCursor = nil
    }

    private func targetType(for lane: CommunityAdminLane) -> String? {
        switch lane {
        case .adoptionListings: return "adoption_listing"
        case .missingCases: return "missing_case"
        case .foundReports: return "found_report"
        case .sightings: return "sighting"
        case .matches: return "match"
        case .moderation: return "moderation_case"
        case .media: return "media_asset"
        case .organizations: return "organization"
        default: return nil
        }
    }

    private func dossierTargetType(for lane: CommunityAdminLane) -> String? {
        switch lane {
        case .adoptionListings: return "adoption_listing"
        case .adoptionApplications: return "adoption_application"
        case .missingCases: return "missing_case"
        case .foundReports: return "found_report"
        case .sightings: return "sighting"
        case .matches: return "match"
        case .moderation: return "moderation_case"
        case .media: return "media_asset"
        case .organizations: return "organization"
        case .alerts: return "operational_alert"
        default: return nil
        }
    }

    private static func dictionary(_ value: Any?) -> [String: Any] {
        if let value = value as? [String: Any] { return value }
        if let value = value as? NSDictionary { return value as? [String: Any] ?? [:] }
        return [:]
    }

    private static func integerDictionary(_ value: Any?) -> [String: Int] {
        dictionary(value).reduce(into: [:]) { result, pair in
            if let number = pair.value as? NSNumber { result[pair.key] = number.intValue }
            else if let number = pair.value as? Int { result[pair.key] = number }
        }
    }

    private static func recordArray(_ value: Any?, source: CommunityAdminLane) -> [CommunityAdminRecord] {
        let dictionaries: [[String: Any]]
        if let typed = value as? [[String: Any]] {
            dictionaries = typed
        } else if let raw = value as? [NSDictionary] {
            dictionaries = raw.compactMap { $0 as? [String: Any] }
        } else {
            dictionaries = []
        }
        return dictionaries.compactMap { CommunityAdminRecord(values: $0, source: source) }
    }

    private static func dossierSections(_ value: Any?) -> [CommunityAdminDossierSection] {
        let related = dictionary(value)
        let definitions: [(String, String, String, String)] = [
            ("events", "Community_Admin_Dossier_Events", "سجل الأحداث", "clock.arrow.circlepath"),
            ("applications", "Community_Admin_Dossier_Applications", "طلبات مرتبطة", "doc.text.fill"),
            ("listing", "Community_Admin_Dossier_Listing", "إعلان مرتبط", "heart.fill"),
            ("sightings", "Community_Admin_Dossier_Sightings", "مشاهدات مرتبطة", "eye.fill"),
            ("matches", "Community_Admin_Dossier_Matches", "مطابقات مرتبطة", "sparkles"),
            ("missingCase", "Community_Admin_Dossier_MissingCase", "حالة فقدان مرتبطة", "magnifyingglass"),
            ("foundReport", "Community_Admin_Dossier_FoundReport", "بلاغ العثور المرتبط", "hand.raised.fill"),
            ("reportedTarget", "Community_Admin_Dossier_ReportedTarget", "المحتوى المُبلّغ عنه", "exclamationmark.shield.fill"),
            ("moderationCases", "Community_Admin_Dossier_Moderation", "سجل الإشراف", "shield.lefthalf.filled"),
            ("userReports", "Community_Admin_Dossier_Reports", "بلاغات المستخدمين", "flag.fill"),
            ("audit", "Community_Admin_Dossier_Audit", "أثر التدقيق", "checkmark.seal.fill"),
            ("conversations", "Community_Admin_Dossier_Conversations", "بيانات المحادثات", "bubble.left.and.bubble.right.fill")
        ]
        return definitions.compactMap { definition in
            let dictionaries: [[String: Any]]
            if let typed = related[definition.0] as? [[String: Any]] {
                dictionaries = typed
            } else if let raw = related[definition.0] as? [NSDictionary] {
                dictionaries = raw.compactMap { $0 as? [String: Any] }
            } else {
                dictionaries = []
            }
            let evidence = dictionaries.compactMap {
                CommunityAdminDossierEvidence(values: $0, sectionID: definition.0)
            }
            guard !evidence.isEmpty else { return nil }
            return CommunityAdminDossierSection(
                id: definition.0,
                titleKey: definition.1,
                fallbackTitle: definition.2,
                symbol: definition.3,
                evidence: evidence
            )
        }
    }

    private static func deduplicated(_ records: [CommunityAdminRecord]) -> [CommunityAdminRecord] {
        var seen = Set<String>()
        return records.filter { seen.insert("\($0.source.rawValue):\($0.id)").inserted }
    }
}

// MARK: - Action policy

private struct CommunityAdminActionDescriptor: Identifiable {
    let action: String
    let titleKey: String
    let fallbackTitle: String
    let symbol: String
    let tone: Tone
    let requiresCanonicalCase: Bool

    enum Tone { case normal, warning, destructive }
    var id: String { action }

    init(
        _ action: String,
        _ titleKey: String,
        _ fallbackTitle: String,
        symbol: String,
        tone: Tone = .normal,
        requiresCanonicalCase: Bool = false
    ) {
        self.action = action
        self.titleKey = titleKey
        self.fallbackTitle = fallbackTitle
        self.symbol = symbol
        self.tone = tone
        self.requiresCanonicalCase = requiresCanonicalCase
    }
}

private enum CommunityAdminActionPolicy {
    static func actions(for record: CommunityAdminRecord, session: AdminSession) -> [CommunityAdminActionDescriptor] {
        let status = record.status
        switch record.source {
        case .adoptionListings where (session.isAdmin || session.grantsAllPermissions || session.hasPermission("community.adoption.moderate") || session.hasPermission("moderation.manage") || session.hasPermission("listings.moderate")):
            if ["pending_review", "needs_changes"].contains(status) {
                return [
                    .init("approve", "Community_Admin_Action_Approve", "اعتماد", symbol: "checkmark.seal.fill"),
                    .init("request_changes", "Community_Admin_Action_RequestChanges", "طلب تعديلات", symbol: "pencil.and.list.clipboard", tone: .warning),
                    .init("reject", "Community_Admin_Action_Reject", "رفض", symbol: "xmark.octagon.fill", tone: .destructive),
                    .init("investigate", "Community_Admin_Action_Investigate", "فتح تحقيق", symbol: "magnifyingglass.circle.fill", tone: .warning)
                ]
            }
            if status == "published" {
                var actions: [CommunityAdminActionDescriptor] = [
                    .init("pause", "Community_Admin_Action_Pause", "إيقاف مؤقت", symbol: "pause.circle.fill", tone: .warning),
                    .init("investigate", "Community_Admin_Action_Investigate", "فتح تحقيق", symbol: "magnifyingglass.circle.fill", tone: .warning),
                    .init("remove", "Community_Admin_Action_Archive", "أرشفة", symbol: "archivebox.fill", tone: .destructive)
                ]
                actions.insert(
                    record.boolean("featured")
                        ? .init("unfeature", "Community_Admin_Action_Unfeature", "إلغاء التمييز", symbol: "star.slash")
                        : .init("feature", "Community_Admin_Action_Feature", "تمييز الإعلان", symbol: "star.fill"),
                    at: 0
                )
                return actions
            }
            if status == "paused" {
                return [
                    .init("resume", "Community_Admin_Action_Resume", "استئناف النشر", symbol: "play.circle.fill"),
                    .init("unfeature", "Community_Admin_Action_Unfeature", "إلغاء التمييز", symbol: "star.slash"),
                    .init("remove", "Community_Admin_Action_Archive", "أرشفة", symbol: "archivebox.fill", tone: .destructive)
                ]
            }
            if ["applications_closed", "match_in_progress"].contains(status) {
                return [
                    .init("investigate", "Community_Admin_Action_Investigate", "فتح تحقيق", symbol: "magnifyingglass.circle.fill", tone: .warning),
                    .init("remove", "Community_Admin_Action_Archive", "أرشفة", symbol: "archivebox.fill", tone: .destructive)
                ]
            }
        case .missingCases where session.hasPermission("community.missing.moderate"):
            if status == "pending_review" {
                return [
                    .init("approve", "Community_Admin_Action_Approve", "اعتماد", symbol: "checkmark.seal.fill"),
                    .init("reject", "Community_Admin_Action_Reject", "رفض", symbol: "xmark.octagon.fill", tone: .destructive),
                    .init("duplicate", "Community_Admin_Action_Duplicate", "تحديد كمكرر", symbol: "doc.on.doc.fill", tone: .warning, requiresCanonicalCase: true),
                    .init("merge", "Community_Admin_Action_Merge", "دمج مع حالة", symbol: "arrow.triangle.merge", tone: .warning, requiresCanonicalCase: true),
                    .init("escalate", "Community_Admin_Action_Escalate", "تصعيد", symbol: "exclamationmark.arrow.triangle.2.circlepath", tone: .warning)
                ]
            }
            if ["active", "searching", "sighting_received", "possibly_found"].contains(status) {
                var actions: [CommunityAdminActionDescriptor] = [
                    .init("escalate", "Community_Admin_Action_Escalate", "تصعيد", symbol: "exclamationmark.arrow.triangle.2.circlepath", tone: .warning),
                    .init("duplicate", "Community_Admin_Action_Duplicate", "تحديد كمكرر", symbol: "doc.on.doc.fill", tone: .warning, requiresCanonicalCase: true),
                    .init("merge", "Community_Admin_Action_Merge", "دمج مع حالة", symbol: "arrow.triangle.merge", tone: .warning, requiresCanonicalCase: true),
                    .init("close", "Community_Admin_Action_Close", "إغلاق الحالة", symbol: "checkmark.circle", tone: .destructive)
                ]
                let isRestricted = record.string("visibility") == "private" && !record.string("visibilityRestrictionStatus").isEmpty
                actions.insert(
                    isRestricted
                        ? .init("restore_visibility", "Community_Admin_Action_RestoreVisibility", "استعادة الظهور", symbol: "eye.fill")
                        : .init("suspend_visibility", "Community_Admin_Action_SuspendVisibility", "تعليق الظهور", symbol: "eye.slash.fill", tone: .warning),
                    at: 0
                )
                return actions
            }
            if ["closed", "invalid", "duplicate"].contains(status) {
                return [.init("reopen", "Community_Admin_Action_Reopen", "إعادة فتح", symbol: "arrow.counterclockwise.circle.fill")]
            }
        case .foundReports where session.hasPermission("community.missing.moderate"):
            if status == "pending_review" {
                return [
                    .init("approve", "Community_Admin_Action_Approve", "اعتماد", symbol: "checkmark.seal.fill"),
                    .init("reject", "Community_Admin_Action_Reject", "رفض", symbol: "xmark.octagon.fill", tone: .destructive)
                ]
            }
            if ["active", "possible_match", "matched"].contains(status) {
                var actions: [CommunityAdminActionDescriptor] = [
                    .init("close", "Community_Admin_Action_Close", "إغلاق البلاغ", symbol: "checkmark.circle", tone: .destructive)
                ]
                let isRestricted = record.string("visibility") == "private" && !record.string("visibilityRestrictionStatus").isEmpty
                actions.insert(
                    isRestricted
                        ? .init("restore_visibility", "Community_Admin_Action_RestoreVisibility", "استعادة الظهور", symbol: "eye.fill")
                        : .init("restrict", "Community_Admin_Action_Restrict", "تقييد الظهور", symbol: "eye.slash.fill", tone: .warning),
                    at: 0
                )
                return actions
            }
            if ["closed", "rejected", "withdrawn"].contains(status) {
                return [.init("reopen", "Community_Admin_Action_Reopen", "إعادة فتح", symbol: "arrow.counterclockwise.circle.fill")]
            }
        case .sightings where session.hasPermission("community.sighting.review"):
            if status == "pending" {
                return [
                    .init("verify", "Community_Admin_Action_Verify", "توثيق المشاهدة", symbol: "checkmark.seal.fill"),
                    .init("reject", "Community_Admin_Action_Reject", "رفض", symbol: "xmark.octagon.fill", tone: .destructive)
                ]
            }
        case .matches where session.hasPermission("community.match.review"):
            if ["pending_review", "needs_information", "likely_match"].contains(status) {
                var actions: [CommunityAdminActionDescriptor] = [
                    .init("reject", "Community_Admin_Action_NotMatch", "ليست مطابقة", symbol: "xmark.circle", tone: .destructive),
                    .init("escalate", "Community_Admin_Action_Escalate", "تصعيد", symbol: "exclamationmark.arrow.triangle.2.circlepath", tone: .warning)
                ]
                if status != "likely_match" {
                    actions.insert(.init("likely", "Community_Admin_Action_LikelyMatch", "مطابقة مرجحة", symbol: "sparkles"), at: 0)
                }
                if status == "pending_review" {
                    actions.insert(.init("needs_info", "Community_Admin_Action_NeedsInfo", "معلومات إضافية", symbol: "questionmark.bubble.fill", tone: .warning), at: 1)
                }
                return actions
            }
        case .moderation where session.hasPermission("community.moderation.resolve"):
            if ["open", "reopened", "escalated"].contains(status) {
                var actions: [CommunityAdminActionDescriptor] = [
                    .init("approve", "Community_Admin_Action_DismissReport", "رفض البلاغ", symbol: "checkmark.shield.fill"),
                    .init("request_changes", "Community_Admin_Action_RequestChanges", "طلب تعديلات", symbol: "pencil.and.list.clipboard", tone: .warning),
                    .init("restrict", "Community_Admin_Action_Restrict", "تقييد المحتوى", symbol: "lock.shield.fill", tone: .warning),
                    .init("hide", "Community_Admin_Action_Hide", "إخفاء المحتوى", symbol: "eye.slash.fill", tone: .warning),
                    .init("remove", "Community_Admin_Action_Remove", "إزالة المحتوى", symbol: "trash.fill", tone: .destructive)
                ]
                if session.hasPermission("users.restrictions.manage") {
                    actions.append(
                        .init("suspend_owner", "Community_Admin_Action_SuspendOwner", "تعليق صاحب المحتوى", symbol: "person.crop.circle.badge.xmark", tone: .destructive)
                    )
                }
                if status != "escalated" {
                    actions.append(.init("escalate", "Community_Admin_Action_Escalate", "تصعيد", symbol: "exclamationmark.arrow.triangle.2.circlepath", tone: .warning))
                }
                return actions
            }
        case .media where session.hasPermission("community.moderation.resolve"):
            if status == "manual_review" {
                return [
                    .init("approve", "Community_Admin_Action_Approve", "اعتماد", symbol: "checkmark.seal.fill"),
                    .init("reject", "Community_Admin_Action_Reject", "رفض", symbol: "xmark.octagon.fill", tone: .destructive)
                ]
            }
        case .organizations:
            if ["pending", "needs_information"].contains(status), session.hasPermission("community.organization.verify") {
                return [
                    .init("verify", "Community_Admin_Action_Verify", "توثيق المنظمة", symbol: "checkmark.seal.fill"),
                    .init("request_info", "Community_Admin_Action_RequestDocuments", "طلب مستندات", symbol: "doc.badge.ellipsis", tone: .warning),
                    .init("reject", "Community_Admin_Action_Reject", "رفض", symbol: "xmark.octagon.fill", tone: .destructive)
                ]
            }
            if session.hasPermission("community.organization.suspend") {
                if status == "active" {
                    return [
                        .init("restrict", "Community_Admin_Action_Restrict", "تقييد", symbol: "lock.shield.fill", tone: .warning),
                        .init("suspend", "Community_Admin_Action_Suspend", "تعليق", symbol: "pause.octagon.fill", tone: .destructive),
                        .init("revoke", "Community_Admin_Action_Revoke", "سحب التوثيق", symbol: "xmark.seal.fill", tone: .destructive)
                    ]
                }
                if ["restricted", "suspended"].contains(status) {
                    return [
                        .init("restore", "Community_Admin_Action_Restore", "استعادة", symbol: "arrow.counterclockwise.circle.fill"),
                        .init("revoke", "Community_Admin_Action_Revoke", "سحب التوثيق", symbol: "xmark.seal.fill", tone: .destructive)
                    ]
                }
            }
        case .alerts where session.hasPermission("community.moderation.resolve"):
            if status == "open" {
                return [
                    .init("acknowledge", "Community_Admin_Action_Acknowledge", "استلام التنبيه", symbol: "hand.raised.fill"),
                    .init("resolve", "Community_Admin_Action_Resolve", "حل التنبيه", symbol: "checkmark.circle.fill")
                ]
            }
            if status == "acknowledged" {
                return [.init("resolve", "Community_Admin_Action_Resolve", "حل التنبيه", symbol: "checkmark.circle.fill")]
            }
            if status == "resolved" {
                return [.init("reopen", "Community_Admin_Action_Reopen", "إعادة فتح", symbol: "arrow.counterclockwise.circle.fill", tone: .warning)]
            }
        default:
            break
        }
        return []
    }
}

// MARK: - Root workspace

@MainActor
struct AdminCommunityControlCenterView: View {
    let onDismiss: () -> Void
    @StateObject private var store: AdminCommunityWorkspaceStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        session: AdminSession,
        initialLane: CommunityAdminLane = .overview,
        onDismiss: @escaping () -> Void
    ) {
        self.onDismiss = onDismiss
        _store = StateObject(
            wrappedValue: AdminCommunityWorkspaceStore(session: session, initialLane: initialLane)
        )
    }

    private var isWide: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
    }

    private var activeLaneColor: Color {
        store.selectedLane.accentColor
    }

    private func laneColor(for lane: CommunityAdminLane) -> Color {
        lane.accentColor
    }

    var body: some View {
        GeometryReader { geometry in
            // Strictly compute safe area top to ensure the navigation bar starts below the status bar
            let safeTop = max(geometry.safeAreaInsets.top, PPStatusBarHelper.statusBarHeight, 47)
            VStack(spacing: 0) {
                header(safeTop: safeTop)
                
                if isWide {
                    HStack(spacing: 0) {
                        laneSidebar
                            .frame(width: 260)
                        Divider().overlay(AdminSurface.hairline)
                        workspace
                    }
                } else {
                    laneRail
                    workspace
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                ZStack {
                    AdminSurface.background
                    // Subtle dynamic ambient atmosphere
                    RadialGradient(
                        colors: [activeLaneColor.opacity(0.045), Color.clear],
                        center: .top,
                        startRadius: 20,
                        endRadius: 520
                    )
                }
                .ignoresSafeArea()
            )
        }
        .ignoresSafeArea()
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .task { await store.start() }
        .sheet(item: $store.selectedRecord, onDismiss: {
            store.dismissDossier()
        }) { record in
            AdminCommunityRecordDetailView(record: record, store: store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert(
            Language.get("Community_Admin_Notice", alter: "تنبيه"),
            isPresented: Binding(
                get: { store.successMessage != nil },
                set: { if !$0 { store.clearMessages() } }
            )
        ) {
            Button(Language.get("OK", alter: "حسنًا"), role: .cancel) { store.clearMessages() }
        } message: {
            Text(store.successMessage ?? "")
        }
    }

    private func header(safeTop: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Status bar clearance spacer - guarantees navigation bar begins below status bar
            Color.clear.frame(height: safeTop)

            HStack(spacing: 12) {
                Button(action: onDismiss) {
                    Image(systemName: Language.isRTL() ? "chevron.right" : "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AdminSurface.primaryText)
                        .frame(width: 40, height: 40)
                        .background(AdminSurface.surface, in: Circle())
                        .overlay(Circle().stroke(AdminSurface.hairline, lineWidth: 0.8))
                        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Language.get("Back", alter: "رجوع"))

                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [activeLaneColor.opacity(0.18), AdminSurface.primary.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(activeLaneColor.opacity(0.25), lineWidth: 0.8)
                        )
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(activeLaneColor)
                        .frame(width: 40, height: 40)

                    Circle()
                        .fill(store.isLoading ? Color.orange : AdminSurface.emerald)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(AdminSurface.surface, lineWidth: 1.8))
                        .offset(x: 2, y: 2)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Community_Admin_Title", alter: "مركز عمليات المجتمع"))
                        .font(PPBrandFont.bold(size: 17))
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(laneSubtitle)
                            .font(PPBrandFont.medium(size: 11.5))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .lineLimit(1)
                        if store.isLoading {
                            Text("· " + Language.get("Community_Admin_Syncing", alter: "جارٍ المزامنة…"))
                                .font(PPBrandFont.regular(size: 11))
                                .foregroundStyle(Color.orange)
                        }
                    }
                }

                Spacer(minLength: 6)

                if store.isMutating {
                    ProgressView()
                        .tint(activeLaneColor)
                        .scaleEffect(0.85)
                        .accessibilityLabel(Language.get("Community_Admin_Working", alter: "جارٍ تنفيذ العملية"))
                }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(store.isLoading ? activeLaneColor : AdminSurface.primaryText)
                        .frame(width: 40, height: 40)
                        .background(AdminSurface.surface, in: Circle())
                        .overlay(Circle().stroke(AdminSurface.hairline, lineWidth: 0.8))
                        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                        .rotationEffect(.degrees(store.isLoading ? 360 : 0))
                        .animation(store.isLoading ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: store.isLoading)
                }
                .buttonStyle(.plain)
                .disabled(store.isLoading || store.isMutating)
                .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
            }
            .padding(.horizontal, isWide ? 24 : 16)
            .padding(.bottom, 12)
            .padding(.top, 6)
        }
        .background(
            AdminSurface.surface
                .overlay(
                    LinearGradient(
                        colors: [activeLaneColor.opacity(0.04), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 3)
                .ignoresSafeArea(edges: .top)
        )
    }

    private var laneSubtitle: String {
        switch store.selectedLane {
        case .overview:
            return Language.get("Community_Admin_Overview_Subtitle_Short", alter: "نبض المجتمع والعمليات الحية")
        case .adoptionListings:
            let count = store.overview["activeAdoptions", default: store.records.count]
            return String(format: Language.get("Community_Admin_Adoption_Subtitle_Short", alter: "التبني ورعاية الألياف · %d إعلان نشط"), count)
        case .adoptionApplications:
            return Language.get("Community_Admin_Applications_Subtitle_Short", alter: "طلبات التبني ومطابقة الأسر")
        case .missingCases:
            let count = store.overview["activeMissing", default: 0]
            return String(format: Language.get("Community_Admin_Missing_Subtitle_Short", alter: "رادار المفقودات · %d بلاغ نشط"), count)
        case .foundReports:
            return Language.get("Community_Admin_Found_Subtitle_Short", alter: "بلاغات العثور على ألياف")
        case .matches:
            return Language.get("Community_Admin_Matches_Subtitle_Short", alter: "المطابقات الذكية للمفقودات")
        case .moderation:
            return Language.get("Community_Admin_Moderation_Subtitle_Short", alter: "الثقة والسلامة وحماية المحتوى")
        case .organizations:
            return Language.get("Community_Admin_Org_Subtitle_Short", alter: "توثيق واعتماد الملاجئ والجمعيات")
        case .alerts:
            return Language.get("Community_Admin_Alerts_Subtitle_Short", alter: "التنبيهات التشغيلية الحرجة")
        default:
            return Language.get("Community_Admin_Subtitle", alter: "التبني · المفقودات · الثقة والسلامة")
        }
    }

    private var laneRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.availableLanes) { lane in
                    laneButton(lane, compact: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(AdminSurface.surface.opacity(0.75))
        .overlay(Divider().overlay(AdminSurface.hairline), alignment: .bottom)
    }

    private var laneSidebar: some View {
        ScrollView {
            LazyVStack(spacing: 7) {
                ForEach(store.availableLanes) { lane in
                    laneButton(lane, compact: false)
                }
            }
            .padding(14)
        }
        .background(AdminSurface.surface)
    }

    private func laneBadgeCount(for lane: CommunityAdminLane) -> Int {
        switch lane {
        case .adoptionListings: return store.overview["activeAdoptions", default: 0]
        case .missingCases: return store.overview["activeMissing", default: 0]
        case .foundReports: return store.overview["activeFoundReports", default: 0]
        case .matches: return store.overview["pendingMatches", default: 0]
        case .moderation: return store.overview["pendingModeration", default: 0]
        case .organizations: return store.overview["pendingOrganizations", default: 0]
        case .alerts: return (store.diagnostics["openAlerts"] as? NSNumber)?.intValue ?? 0
        default: return 0
        }
    }

    private func laneButton(_ lane: CommunityAdminLane, compact: Bool) -> some View {
        let selected = store.selectedLane == lane
        let badgeCount = laneBadgeCount(for: lane)
        let color = laneColor(for: lane)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.26)) {
                store.select(lane)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: lane.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : color)
                Text(Language.get(lane.titleKey, alter: lane.fallbackTitle))
                    .font(selected ? PPBrandFont.bold(size: 13) : PPBrandFont.medium(size: 13))
                    .lineLimit(1)
                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(PPBrandFont.bold(size: 11).monospacedDigit())
                        .foregroundStyle(selected ? color : Color.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(selected ? Color.white : color, in: Capsule())
                }
                if !compact { Spacer(minLength: 0) }
            }
            .foregroundStyle(selected ? Color.white : AdminSurface.primaryText)
            .padding(.horizontal, compact ? 14 : 12)
            .frame(minHeight: 38)
            .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
            .background(
                selected
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [color, color.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    : AnyShapeStyle(AdminSurface.surface),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(selected ? Color.clear : AdminSurface.hairline, lineWidth: 0.8)
            )
            .shadow(color: selected ? color.opacity(0.28) : Color.black.opacity(0.03), radius: selected ? 6 : 2, x: 0, y: selected ? 3 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var workspace: some View {
        ZStack {
            AdminSurface.background
            if store.isLoading {
                VStack(spacing: 14) {
                    ProgressView().tint(activeLaneColor).scaleEffect(1.1)
                    Text(Language.get("Community_Admin_Loading", alter: "جارٍ تحميل بيانات المجتمع الآمنة…"))
                        .font(PPBrandFont.medium(size: 14))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
            } else {
                switch store.selectedLane {
                case .overview:
                    AdminCommunityOverviewView(store: store)
                case .adoptionListings:
                    AdminCommunityAdoptionWorkspace(store: store)
                case .operationsMap:
                    AdminCommunityOperationsMapView(store: store)
                case .configuration:
                    AdminCommunityConfigurationView(store: store)
                case .analytics:
                    AdminCommunityAnalyticsView(store: store)
                default:
                    AdminCommunityQueueView(store: store)
                }
            }
        }
        .overlay(alignment: .top) {
            if let message = store.errorMessage {
                AdminCommunityErrorBanner(
                    message: message,
                    dismiss: { store.clearMessages() },
                    retry: { Task { await store.refresh() } }
                )
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(20)
            }
        }
    }
}

// MARK: - Overview (Living Operational Cockpit)

private struct AdminCommunityOverviewView: View {
    @ObservedObject var store: AdminCommunityWorkspaceStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                pulseHeroHUD
                domainCommandClusters
                operationalSafetyMatrix
                attentionHorizon
                governanceAndPrivacyVault
            }
            .padding(horizontalSizeClass == .regular ? 24 : 16)
            .padding(.vertical, 20)
        }
        .refreshable { await store.refresh() }
    }

    private var pulseHeroHUD: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(AdminSurface.emerald)
                            .frame(width: 9, height: 9)
                            .overlay(
                                Circle()
                                    .stroke(AdminSurface.emerald.opacity(0.4), lineWidth: 3)
                                    .scaleEffect(1.4)
                            )
                        Text(Language.get("Community_Admin_Pulse_Live", alter: "نبض المجتمع المباشر"))
                            .font(AdminType.title3)
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                    Text(Language.get("Community_Admin_Pulse_Subtitle", alter: "مؤشرات تشغيلية حية من الخادم، بدون حسابات عميل محلية."))
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 13, weight: .bold))
                    Text(Language.get("Community_Admin_Status_Healthy", alter: "الأنظمة نشطة"))
                        .font(AdminType.caption2Bold)
                }
                .foregroundStyle(AdminSurface.emerald)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AdminSurface.emerald.opacity(0.12), in: Capsule())
            }

            HStack(spacing: 12) {
                quickTelemetryPill(
                    title: Language.get("Community_Admin_Metric_ActiveAdoptions", alter: "إعلانات تبني نشطة"),
                    value: store.overview["activeAdoptions", default: 0],
                    symbol: "heart.fill",
                    color: .pink
                ) {
                    store.select(.adoptionListings)
                }

                quickTelemetryPill(
                    title: Language.get("Community_Admin_Metric_ActiveMissing", alter: "حالات فقدان نشطة"),
                    value: store.overview["activeMissing", default: 0],
                    symbol: "magnifyingglass",
                    color: .orange
                ) {
                    store.select(.missingCases)
                }
            }
        }
        .padding(18)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 3)
    }

    private func quickTelemetryPill(title: String, value: Int, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(value)")
                        .font(AdminType.title3.monospacedDigit())
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(title)
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            .padding(12)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var domainCommandClusters: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 260 : 158), spacing: 12)], spacing: 12) {
            domainCard(
                title: Language.get("Community_Admin_Metric_ActiveAdoptions", alter: "إعلانات التبني"),
                count: store.overview["activeAdoptions", default: 0],
                subtitle: Language.get("Community_Admin_Adoption_Focus", alter: "عائلات تبحث عن أليف"),
                symbol: "heart.fill",
                accent: .pink
            ) {
                store.select(.adoptionListings)
            }

            domainCard(
                title: Language.get("Community_Admin_Metric_ActiveMissing", alter: "حالات الفقدان"),
                count: store.overview["activeMissing", default: 0],
                subtitle: Language.get("Community_Admin_Missing_Focus", alter: "بلاغات عاجلة قيد البحث"),
                symbol: "magnifyingglass",
                accent: .orange
            ) {
                store.select(.missingCases)
            }

            domainCard(
                title: Language.get("Community_Admin_Metric_Reunited", alter: "تم لمّ شملها"),
                count: store.overview["reunited", default: 0],
                subtitle: Language.get("Community_Admin_Reunited_Focus", alter: "هذا الشهر بنجاح"),
                symbol: "house.and.flag.fill",
                accent: .green
            ) {
                store.select(.overview)
            }

            domainCard(
                title: Language.get("Community_Admin_Metric_Found", alter: "بلاغات العثور"),
                count: store.overview["activeFoundReports", default: 0],
                subtitle: Language.get("Community_Admin_Found_Focus", alter: "ألياف تم العثور عليها"),
                symbol: "hand.raised.fill",
                accent: .teal
            ) {
                store.select(.foundReports)
            }

            domainCard(
                title: Language.get("Community_Admin_Metric_Matches", alter: "المطابقات الذكية"),
                count: store.overview["pendingMatches", default: 0],
                subtitle: Language.get("Community_Admin_Matches_Focus", alter: "تنتظر مراجعة المشرف"),
                symbol: "sparkles",
                accent: .indigo
            ) {
                store.select(.matches)
            }

            domainCard(
                title: Language.get("Community_Admin_Metric_Moderation", alter: "حالات الرقابة"),
                count: store.overview["pendingModeration", default: 0],
                subtitle: Language.get("Community_Admin_Moderation_Focus", alter: "محتوى معلق للتدقيق"),
                symbol: "shield.lefthalf.filled",
                accent: .purple
            ) {
                store.select(.moderation)
            }

            domainCard(
                title: Language.get("Community_Admin_Metric_Organizations", alter: "توثيق المنظمات"),
                count: store.overview["pendingOrganizations", default: 0],
                subtitle: Language.get("Community_Admin_Org_Focus", alter: "جمعيات وملاجئ تنتظر الاعتماد"),
                symbol: "building.2.fill",
                accent: .blue
            ) {
                store.select(.organizations)
            }

            domainCard(
                title: Language.get("Community_Admin_Metric_HighRisk", alter: "بلاغات عالية الخطورة"),
                count: store.overview["highRiskReports", default: 0],
                subtitle: Language.get("Community_Admin_HighRisk_Focus", alter: "تتطلب استجابة فورية"),
                symbol: "exclamationmark.shield.fill",
                accent: .red
            ) {
                store.select(.alerts)
            }
        }
    }

    private func domainCard(title: String, count: Int, subtitle: String, symbol: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 36, height: 36)
                        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    Spacer(minLength: 4)
                    Text("\(count)")
                        .font(AdminType.title2.monospacedDigit())
                        .foregroundStyle(AdminSurface.primaryText)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AdminType.captionBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    private var operationalSafetyMatrix: some View {
        VStack(alignment: .leading, spacing: 14) {
            AdminCommunitySectionHeader(
                title: Language.get("Community_Admin_Diagnostics", alter: "سلامة التشغيل"),
                subtitle: Language.get("Community_Admin_Diagnostics_Subtitle", alter: "إشارات الدعم قبل أن تتحول إلى حوادث مستخدمين."),
                symbol: "stethoscope"
            )
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 10)], spacing: 10) {
                diagnosticChip("openAlerts", "Community_Admin_Diagnostic_OpenAlerts", "تنبيهات مفتوحة", .red)
                diagnosticChip("failedNotifications", "Community_Admin_Diagnostic_Notifications", "إشعارات متعثرة", .orange)
                diagnosticChip("stalledMedia", "Community_Admin_Diagnostic_Media", "وسائط عالقة", .purple)
                diagnosticChip("processingMigrations", "Community_Admin_Diagnostic_Migrations", "عمليات ترحيل قيد التنفيذ", .indigo)
                diagnosticChip("configurationVersion", "Community_Admin_Diagnostic_Config", "إصدار الإعدادات", .blue)
            }
            if let rollout = store.diagnostics["rolloutStage"] as? String {
                HStack(spacing: 8) {
                    Circle().fill(AdminSurface.emerald).frame(width: 8, height: 8)
                    Text(Language.get("Community_Admin_Rollout", alter: "مرحلة الإطلاق"))
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(CommunityAdminLocalization.state(rollout))
                        .font(AdminType.captionBold)
                        .foregroundStyle(AdminSurface.primaryText)
                }
            }
        }
        .padding(18)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
    }

    private var attentionHorizon: some View {
        VStack(alignment: .leading, spacing: 13) {
            AdminCommunitySectionHeader(
                title: Language.get("Community_Admin_Attention", alter: "يحتاج انتباهك"),
                subtitle: Language.get("Community_Admin_Attention_Subtitle", alter: "أعلى الحالات أولوية من قوائم المراجعة التي تسمح بها صلاحياتك."),
                symbol: "bolt.shield.fill"
            )
            if store.attentionRecords.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AdminSurface.emerald)
                    Text(Language.get("Community_Admin_Attention_Clear", alter: "لا توجد عناصر عاجلة ضمن نطاق صلاحياتك الحالي."))
                        .font(AdminType.callout)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AdminSurface.emerald.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(store.attentionRecords) { record in
                            Button { store.openDossier(record) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label(record.title, systemImage: record.source.symbol)
                                        .font(AdminType.calloutBold)
                                        .foregroundStyle(AdminSurface.primaryText)
                                        .lineLimit(1)
                                    AdminCommunityStatusBadge(status: record.status, compact: true)
                                    Text(record.subtitle)
                                        .font(AdminType.caption)
                                        .foregroundStyle(AdminSurface.secondaryText)
                                        .lineLimit(2)
                                }
                                .padding(13)
                                .frame(width: 220, height: 118, alignment: .leading)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
    }

    private func diagnosticChip(_ key: String, _ titleKey: String, _ fallback: String, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color.opacity(0.15)).frame(width: 30, height: 30).overlay(
                Text(CommunityAdminValueFormatter.integer(store.diagnostics[key]))
                    .font(AdminType.captionBold.monospacedDigit())
                    .foregroundStyle(color)
            )
            Text(Language.get(titleKey, alter: fallback))
                .font(AdminType.caption)
                .foregroundStyle(AdminSurface.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var governanceAndPrivacyVault: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(AdminSurface.primary)
                .frame(width: 42, height: 42)
                .background(AdminSurface.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(Language.get("Community_Admin_Privacy_Title", alter: "الخصوصية جزء من التشغيل"))
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                Text(Language.get("Community_Admin_Privacy_Body", alter: "المواقع الدقيقة وبيانات المنظمات الخاصة لا تُحمّل افتراضيًا. كل كشف مصرح به يُسجّل خادميًا في سجل التدقيق."))
                    .font(AdminType.callout)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(17)
        .background(AdminSurface.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.primary.opacity(0.2), lineWidth: 0.8))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Dedicated Adoption Workspace

private struct AdminCommunityAdoptionWorkspace: View {
    @ObservedObject var store: AdminCommunityWorkspaceStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedSpecies: String = ""

    private struct StatusOption: Identifiable {
        let id: String
        let titleKey: String
        let fallback: String
        let symbol: String
        let tone: Color
    }

    private let statusOptions: [StatusOption] = [
        .init(id: "", titleKey: "Community_Admin_Status_All", fallback: "كل الحالات", symbol: "square.grid.2x2", tone: AdminSurface.primary),
        .init(id: "pending_review", titleKey: "Community_Admin_Status_Pending", fallback: "بانتظار الاعتماد", symbol: "clock.badge.exclamationmark.fill", tone: .orange),
        .init(id: "published", titleKey: "Community_Admin_Status_Published", fallback: "منشور نشط", symbol: "checkmark.seal.fill", tone: .green),
        .init(id: "needs_changes", titleKey: "Community_Admin_Status_NeedsChanges", fallback: "يتطلب تعديل", symbol: "pencil.and.list.clipboard", tone: .purple),
        .init(id: "applications_closed", titleKey: "Community_Admin_Status_Closed", fallback: "مكتمل / مغلق", symbol: "lock.fill", tone: .blue),
        .init(id: "paused", titleKey: "Community_Admin_Status_Paused", fallback: "موقوف مؤقتًا", symbol: "pause.circle.fill", tone: .secondary)
    ]

    private let speciesOptions: [(id: String, title: String, symbol: String)] = [
        ("", "الكل", "pawprint.fill"),
        ("dog", "كلاب", "dog.fill"),
        ("cat", "قطط", "cat.fill"),
        ("bird", "طيور", "bird.fill"),
        ("other", "أخرى", "ellipsis.circle.fill")
    ]

    private var adoptionRecords: [CommunityAdminRecord] {
        let base = store.filteredRecords
        guard !selectedSpecies.isEmpty else { return base }
        return base.filter { record in
            let species = record.string("pet.species", "species", "kind").lowercased()
            if selectedSpecies == "other" {
                return !["dog", "cat", "bird", "كلب", "قطة", "طير"].contains(where: { species.contains($0) })
            }
            return species.contains(selectedSpecies) ||
                (selectedSpecies == "dog" && (species.contains("dog") || species.contains("كلب"))) ||
                (selectedSpecies == "cat" && (species.contains("cat") || species.contains("قط"))) ||
                (selectedSpecies == "bird" && (species.contains("bird") || species.contains("طير")))
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                heroSanctuaryHeader
                statusRibbon
                searchAndSpeciesBar

                if adoptionRecords.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 340 : 300), spacing: 16)],
                        spacing: 16
                    ) {
                        ForEach(adoptionRecords) { record in
                            AdminAdoptionPetCard(record: record, store: store) {
                                store.openDossier(record)
                            }
                        }
                    }
                }

                if store.hasMore {
                    loadMoreButton
                }
            }
            .padding(horizontalSizeClass == .regular ? 24 : 16)
            .padding(.vertical, 20)
        }
        .refreshable { await store.refresh() }
    }

    private var heroSanctuaryHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#E11D48").opacity(0.20), AdminSurface.primary.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(hex: "#E11D48").opacity(0.28), lineWidth: 0.8)
                    .frame(width: 52, height: 52)
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color(hex: "#E11D48"))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(Language.get("Community_Admin_Adoption_Sanctuary", alter: "محراب التبني ورعاية الألياف"))
                        .font(PPBrandFont.bold(size: 19))
                        .foregroundStyle(AdminSurface.primaryText)
                    
                    Text("\(store.overview["activeAdoptions", default: store.records.count])")
                        .font(PPBrandFont.bold(size: 12).monospacedDigit())
                        .foregroundStyle(Color(hex: "#E11D48"))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Color(hex: "#E11D48").opacity(0.12), in: Capsule())
                }

                Text(Language.get("Community_Admin_Adoption_Subtitle", alter: "إدارة إعلانات التبني وتدقيق الهوية والتحقق من الشروط قبل إتاحتها للأسر الراغبة."))
                    .font(PPBrandFont.regular(size: 13))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.02), radius: 8, x: 0, y: 3)
    }

    private var statusRibbon: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(statusOptions) { option in
                    let isSelected = store.statusFilter == option.id
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        store.statusFilter = option.id
                        Task { await store.applyFilters() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: option.symbol)
                                .font(.system(size: 11, weight: .semibold))
                            Text(Language.get(option.titleKey, alter: option.fallback))
                                .font(isSelected ? PPBrandFont.bold(size: 13) : PPBrandFont.medium(size: 13))
                        }
                        .foregroundStyle(isSelected ? Color.white : AdminSurface.secondaryText)
                        .padding(.horizontal, 13)
                        .frame(height: 36)
                        .background(
                            isSelected
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [option.tone, option.tone.opacity(0.85)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                : AnyShapeStyle(AdminSurface.surface),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().stroke(isSelected ? Color.clear : AdminSurface.hairline, lineWidth: 0.8)
                        )
                        .shadow(color: isSelected ? option.tone.opacity(0.25) : Color.clear, radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var searchAndSpeciesBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AdminSurface.secondaryText)
                TextField(
                    Language.get("Community_Admin_Adoption_SearchPlaceholder", alter: "ابحث باسم الأليف، السلالة، أو الناشر…"),
                    text: $store.searchText
                )
                .font(PPBrandFont.regular(size: 14))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                if !store.searchText.isEmpty {
                    Button { store.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(AdminSurface.secondaryText)
                    }
                    .accessibilityLabel(Language.get("Clear", alter: "مسح"))
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(speciesOptions, id: \.id) { item in
                        let isSelected = selectedSpecies == item.id
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            selectedSpecies = item.id
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(item.title)
                                    .font(isSelected ? PPBrandFont.bold(size: 12.5) : PPBrandFont.medium(size: 12.5))
                            }
                            .foregroundStyle(isSelected ? Color.white : AdminSurface.secondaryText)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(
                                isSelected
                                    ? AnyShapeStyle(Color(hex: "#E11D48"))
                                    : AnyShapeStyle(AdminSurface.surface),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(isSelected ? Color.clear : AdminSurface.hairline, lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var emptyState: some View {
        AdminCommunityEmptyState(
            symbol: "heart.slash.fill",
            title: Language.get("Community_Admin_Adoption_Empty_Title", alter: "لا توجد إعلانات تبني مطابقة"),
            body: Language.get("Community_Admin_Adoption_Empty_Body", alter: "جرّب تغيير مرشح الحالة أو فئة الحيوان أو مسح نص البحث لعرض المزيد."),
            accentColor: Color(hex: "#E11D48"),
            resetAction: (!store.statusFilter.isEmpty || !selectedSpecies.isEmpty || !store.searchText.isEmpty) ? {
                store.statusFilter = ""
                selectedSpecies = ""
                store.searchText = ""
                Task { await store.applyFilters() }
            } : nil,
            action: { Task { await store.refresh() } }
        )
    }

    private var loadMoreButton: some View {
        Button {
            Task { await store.loadMore() }
        } label: {
            HStack(spacing: 9) {
                if store.isLoadingMore { ProgressView().tint(.white) }
                Text(Language.get("Community_Admin_LoadMore_Adoptions", alter: "تحميل المزيد من إعلانات التبني"))
                    .font(PPBrandFont.bold(size: 15))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                LinearGradient(
                    colors: [Color(hex: "#E11D48"), Color(hex: "#BE123C")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .shadow(color: Color(hex: "#E11D48").opacity(0.28), radius: 8, x: 0, y: 4)
        }
        .disabled(store.isLoadingMore)
    }
}

// MARK: - Dedicated Adoption Pet Card

private struct AdminAdoptionPetCard: View {
    let record: CommunityAdminRecord
    @ObservedObject var store: AdminCommunityWorkspaceStore
    let onOpen: () -> Void

    private var petBreed: String {
        let breed = record.string("pet.breed", "breed")
        if !breed.isEmpty { return breed }
        let species = record.string("pet.species", "species")
        return species.isEmpty ? Language.get("Community_Admin_Pet_General", alter: "أليف لطيف") : species
    }

    private var petGender: String {
        let raw = record.string("pet.gender", "gender").lowercased()
        if raw.contains("male") || raw.contains("ذكر") {
            return Language.get("Community_Admin_Gender_Male", alter: "ذكر ♂")
        }
        if raw.contains("female") || raw.contains("أنثى") {
            return Language.get("Community_Admin_Gender_Female", alter: "أنثى ♀")
        }
        return ""
    }

    private var petAge: String {
        record.string("pet.age", "age")
    }

    private var locationText: String {
        let city = record.string("area.city", "city")
        let district = record.string("area.district", "district")
        if !city.isEmpty && !district.isEmpty {
            return "\(city) · \(district)"
        }
        return city.isEmpty ? district : city
    }

    private var applicationsCount: Int {
        record.integer("applicationCount")
    }

    private var isFeatured: Bool {
        record.boolean("featured")
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                mediaCover
                contentBody
                Divider().overlay(AdminSurface.hairline)
                cardFooter
            }
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isFeatured ? Color.orange.opacity(0.4) : AdminSurface.hairline, lineWidth: isFeatured ? 1.4 : 0.8)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var mediaCover: some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .bottomLeading) {
                if let url = record.primaryMediaURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            mediaPlaceholder
                        default:
                            ProgressView().tint(AdminSurface.primary)
                        }
                    }
                    .frame(height: 164)
                    .frame(maxWidth: .infinity)
                    .clipped()
                } else {
                    mediaPlaceholder
                        .frame(height: 164)
                        .frame(maxWidth: .infinity)
                }

                LinearGradient(
                    colors: [Color.black.opacity(0.65), Color.clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(height: 64)

                if !locationText.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text(locationText)
                            .font(AdminType.captionBold)
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            }

            HStack {
                AdminCommunityStatusBadge(status: record.status)
                Spacer()
                if isFeatured {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(Language.get("Community_Admin_Featured", alter: "مميز"))
                            .font(AdminType.caption2Bold)
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.orange, in: Capsule())
                    .shadow(color: Color.orange.opacity(0.3), radius: 4, x: 0, y: 2)
                }
            }
            .padding(12)
        }
    }

    private var mediaPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [AdminSurface.primary.opacity(0.12), Color.pink.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 6) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary.opacity(0.6))
                Text(Language.get("Community_Admin_Adoption_Photo", alter: "صورة الأليف"))
                    .font(AdminType.caption2)
                    .foregroundStyle(AdminSurface.secondaryText)
            }
        }
    }

    private var contentBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.title)
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !record.lastUpdatedText.isEmpty {
                    Text(record.lastUpdatedText)
                        .font(AdminType.caption2)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }

            HStack(spacing: 6) {
                chip(petBreed, symbol: "tag.fill", color: AdminSurface.primary)
                if !petGender.isEmpty {
                    chip(petGender, symbol: nil, color: petGender.contains("ذكر") ? .blue : .pink)
                }
                if !petAge.isEmpty {
                    chip(petAge, symbol: "calendar", color: .purple)
                }
            }

            if !record.subtitle.isEmpty && record.subtitle != locationText {
                Text(record.subtitle)
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            if applicationsCount > 0 {
                HStack(spacing: 7) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.indigo)
                    Text("\(applicationsCount) " + Language.get("Community_Admin_Applications_Count", alter: "طلبات تبني مسجلة"))
                        .font(AdminType.captionBold)
                        .foregroundStyle(Color.indigo)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
        .padding(14)
    }

    private var cardFooter: some View {
        HStack(spacing: 12) {
            let publisher = record.string("organizationName", "ownerName", "publisherType")
            if !publisher.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: record.string("organizationName").isEmpty ? "person.fill" : "building.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(publisher)
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Text(Language.get("Community_Admin_ViewDossier", alter: "الملف الكامل"))
                    .font(AdminType.captionBold)
                    .foregroundStyle(AdminSurface.primary)
                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(AdminSurface.control.opacity(0.4))
    }

    private func chip(_ text: String, symbol: String?, color: Color) -> some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(AdminType.caption2Bold)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1), in: Capsule())
    }
}

// MARK: - Queue

private struct AdminCommunityQueueView: View {
    @ObservedObject var store: AdminCommunityWorkspaceStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                AdminCommunitySectionHeader(
                    title: Language.get(store.selectedLane.titleKey, alter: store.selectedLane.fallbackTitle),
                    subtitle: subtitle,
                    symbol: store.selectedLane.symbol,
                    accentColor: store.selectedLane.accentColor
                )
                filters

                if store.filteredRecords.isEmpty {
                    AdminCommunityEmptyState(
                        symbol: store.selectedLane.symbol,
                        title: Language.get("Community_Admin_Empty_Title", alter: "لا توجد عناصر في هذه القائمة"),
                        body: Language.get("Community_Admin_Empty_Body", alter: "غيّر المرشحات أو حدّث القائمة. لا توجد بيانات تجريبية أو عناصر وهمية."),
                        accentColor: store.selectedLane.accentColor,
                        resetAction: (!store.statusFilter.isEmpty || !store.searchText.isEmpty) ? {
                            store.statusFilter = ""
                            store.searchText = ""
                            Task { await store.applyFilters() }
                        } : nil,
                        action: { Task { await store.refresh() } }
                    )
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 300 : 280), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(store.filteredRecords) { record in
                            AdminCommunityRecordCard(record: record) {
                                store.openDossier(record)
                            }
                        }
                    }
                }

                if store.hasMore {
                    Button {
                        Task { await store.loadMore() }
                    } label: {
                        HStack(spacing: 9) {
                            if store.isLoadingMore { ProgressView().tint(.white) }
                            Text(Language.get("Community_Admin_LoadMore", alter: "تحميل المزيد"))
                                .font(PPBrandFont.bold(size: 15))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            LinearGradient(
                                colors: [store.selectedLane.accentColor, store.selectedLane.accentColor.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                        .shadow(color: store.selectedLane.accentColor.opacity(0.25), radius: 6, x: 0, y: 3)
                    }
                    .disabled(store.isLoadingMore)
                }
            }
            .padding(horizontalSizeClass == .regular ? 24 : 16)
            .padding(.vertical, 20)
        }
        .refreshable { await store.refresh() }
    }

    private var subtitle: String {
        switch store.selectedLane {
        case .adoptionApplications:
            return Language.get("Community_Admin_Applications_Subtitle", alter: "إشراف زمني وحالة الطلب؛ اختيار المتبني يبقى لصاحب الإعلان أو المنظمة.")
        case .audit:
            return Language.get("Community_Admin_Audit_Subtitle", alter: "أثر خادمي غير قابل للاستبدال لقرارات المجتمع الحساسة.")
        case .moderation:
            return Language.get("Community_Admin_Moderation_Subtitle", alter: "قرارات الثقة والسلامة تُطبق على المحتوى الحقيقي وتُسجل بالكامل.")
        default:
            return Language.get("Community_Admin_Queue_Subtitle", alter: "قائمة محدودة ومقسّمة إلى صفحات، مرتبة حسب آخر تحديث من الخادم.")
        }
    }

    @ViewBuilder
    private var filters: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AdminSurface.secondaryText)
                TextField(Language.get("Community_Admin_Search", alter: "بحث داخل الصفحة المحمّلة"), text: $store.searchText)
                    .font(PPBrandFont.regular(size: 14))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                if !store.searchText.isEmpty {
                    Button { store.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(AdminSurface.secondaryText)
                    }
                    .accessibilityLabel(Language.get("Clear", alter: "مسح"))
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))

            if store.selectedLane.supportsStatusFilter {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        let isAll = store.statusFilter.isEmpty
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            store.statusFilter = ""
                            Task { await store.applyFilters() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(Language.get("Community_Admin_Status_All", alter: "كل الحالات"))
                                    .font(isAll ? PPBrandFont.bold(size: 13) : PPBrandFont.medium(size: 13))
                            }
                            .foregroundStyle(isAll ? Color.white : AdminSurface.secondaryText)
                            .padding(.horizontal, 13)
                            .frame(height: 36)
                            .background(
                                isAll
                                    ? AnyShapeStyle(
                                        LinearGradient(
                                            colors: [store.selectedLane.accentColor, store.selectedLane.accentColor.opacity(0.85)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    : AnyShapeStyle(AdminSurface.surface),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(isAll ? Color.clear : AdminSurface.hairline, lineWidth: 0.8)
                            )
                            .shadow(color: isAll ? store.selectedLane.accentColor.opacity(0.25) : Color.clear, radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)

                        ForEach(CommunityAdminLocalization.statuses(for: store.selectedLane), id: \.self) { status in
                            let isSelected = store.statusFilter == status
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                store.statusFilter = status
                                Task { await store.applyFilters() }
                            } label: {
                                Text(CommunityAdminLocalization.state(status))
                                    .font(isSelected ? PPBrandFont.bold(size: 13) : PPBrandFont.medium(size: 13))
                                    .foregroundStyle(isSelected ? Color.white : AdminSurface.primaryText)
                                    .padding(.horizontal, 13)
                                    .frame(height: 36)
                                    .background(
                                        isSelected
                                            ? AnyShapeStyle(
                                                LinearGradient(
                                                    colors: [store.selectedLane.accentColor, store.selectedLane.accentColor.opacity(0.85)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            : AnyShapeStyle(AdminSurface.surface),
                                        in: Capsule()
                                    )
                                    .overlay(
                                        Capsule().stroke(isSelected ? Color.clear : AdminSurface.hairline, lineWidth: 0.8)
                                    )
                                    .shadow(color: isSelected ? store.selectedLane.accentColor.opacity(0.25) : Color.clear, radius: 4, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack(spacing: 8) {
                if [.missingCases, .foundReports, .sightings].contains(store.selectedLane), store.canViewPreciseLocation {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task { await store.setPreciseLocation(!store.includePreciseLocation) }
                    } label: {
                        filterToggleChip(
                            title: store.includePreciseLocation
                                ? Language.get("Community_Admin_Precise_On", alter: "الموقع الدقيق ظاهر")
                                : Language.get("Community_Admin_Precise_Off", alter: "إظهار الموقع الدقيق"),
                            symbol: store.includePreciseLocation ? "location.fill" : "location.slash",
                            isActive: store.includePreciseLocation,
                            activeColor: AdminSurface.emerald
                        )
                    }
                    .accessibilityHint(Language.get("Community_Admin_Precise_Audit_Hint", alter: "تُسجل هذه القراءة في سجل التدقيق"))
                }

                if store.selectedLane == .organizations,
                   store.session.hasPermission("community.organization.verify") {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task { await store.setPrivateOrganization(!store.includePrivateOrganization) }
                    } label: {
                        filterToggleChip(
                            title: store.includePrivateOrganization
                                ? Language.get("Community_Admin_Private_On", alter: "البيانات الخاصة ظاهرة")
                                : Language.get("Community_Admin_Private_Off", alter: "إظهار بيانات التحقق"),
                            symbol: store.includePrivateOrganization ? "lock.open.fill" : "lock.fill",
                            isActive: store.includePrivateOrganization,
                            activeColor: AdminSurface.emerald
                        )
                    }
                    .accessibilityHint(Language.get("Community_Admin_Precise_Audit_Hint", alter: "تُسجل هذه القراءة في سجل التدقيق"))
                }

                if store.selectedLane == .matches, store.canViewSensitiveMatchEvidence {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task { await store.setSensitiveMatchEvidence(!store.includeSensitiveMatchEvidence) }
                    } label: {
                        filterToggleChip(
                            title: store.includeSensitiveMatchEvidence
                                ? Language.get("Community_Admin_Sensitive_Evidence_On", alter: "الأدلة الحساسة ظاهرة")
                                : Language.get("Community_Admin_Sensitive_Evidence_Off", alter: "إظهار أدلة المطابقة الحساسة"),
                            symbol: store.includeSensitiveMatchEvidence ? "lock.open.fill" : "lock.fill",
                            isActive: store.includeSensitiveMatchEvidence,
                            activeColor: Color(hex: "#6366F1")
                        )
                    }
                    .accessibilityHint(Language.get("Community_Admin_Sensitive_Evidence_Audit_Hint", alter: "تتطلب هذه القراءة سببًا وتُسجل في سجل التدقيق"))
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if ([.missingCases, .foundReports, .sightings].contains(store.selectedLane) && store.canViewPreciseLocation) ||
                (store.selectedLane == .organizations && store.session.hasPermission("community.organization.verify")) ||
                (store.selectedLane == .matches && store.canViewSensitiveMatchEvidence) {
                VStack(alignment: .leading, spacing: 7) {
                    Label(
                        Language.get("Community_Admin_Private_Access_Reason", alter: "سبب الوصول الخاص"),
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(PPBrandFont.bold(size: 13))
                    .foregroundStyle(AdminSurface.secondaryText)
                    TextField(
                        Language.get("Community_Admin_Private_Access_Reason_Placeholder", alter: "اشرح سبب الحاجة إلى هذه البيانات"),
                        text: $store.privateAccessReason,
                        axis: .vertical
                    )
                    .font(PPBrandFont.regular(size: 14))
                    .lineLimit(1...3)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
                    .accessibilityHint(Language.get("Community_Admin_Sensitive_Evidence_Audit_Hint", alter: "تتطلب هذه القراءة سببًا وتُسجل في سجل التدقيق"))
                }
            }
        }
    }

    private func filterToggleChip(title: String, symbol: String, isActive: Bool, activeColor: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
            Text(title).lineLimit(1)
        }
        .font(PPBrandFont.bold(size: 12.5))
        .foregroundStyle(isActive ? activeColor : AdminSurface.secondaryText)
        .padding(.horizontal, 13)
        .frame(minHeight: 36)
        .background(
            isActive ? activeColor.opacity(0.12) : AdminSurface.surface,
            in: Capsule()
        )
        .overlay(
            Capsule().stroke(isActive ? activeColor.opacity(0.35) : AdminSurface.hairline, lineWidth: 0.8)
        )
    }
}

private struct AdminCommunityRecordCard: View {
    let record: CommunityAdminRecord
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top, spacing: 12) {
                    media
                    VStack(alignment: .leading, spacing: 5) {
                        Text(record.title)
                            .font(PPBrandFont.bold(size: 15))
                            .foregroundStyle(AdminSurface.primaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(record.subtitle)
                            .font(PPBrandFont.regular(size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                HStack(spacing: 8) {
                    AdminCommunityStatusBadge(status: record.status)
                    if !record.moderationStatus.isEmpty, record.moderationStatus != record.status {
                        AdminCommunityStatusBadge(status: record.moderationStatus, compact: true)
                    }
                    Spacer(minLength: 0)
                    if !record.lastUpdatedText.isEmpty {
                        Text(record.lastUpdatedText)
                            .font(PPBrandFont.regular(size: 11))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }

                HStack(spacing: 12) {
                    if record.integer("applicationCount") > 0 {
                        compactFact("doc.text", record.integer("applicationCount"))
                    }
                    if record.integer("sightingCount") > 0 {
                        compactFact("eye.fill", record.integer("sightingCount"))
                    }
                    if record.integer("matchCount") > 0 {
                        compactFact("sparkles", record.integer("matchCount"))
                    }
                    if let score = record.decimal("score") {
                        Label(score.formatted(.percent.precision(.fractionLength(0))), systemImage: "gauge.with.dots.needle.67percent")
                            .font(PPBrandFont.bold(size: 11.5).monospacedDigit())
                            .foregroundStyle(AdminSurface.primary)
                    }
                    Spacer(minLength: 0)
                    Text("v\(record.version)")
                        .font(PPBrandFont.bold(size: 11).monospacedDigit())
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 156, alignment: .leading)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
            .shadow(color: Color.black.opacity(0.02), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Language.get("Community_Admin_Record_OpenHint", alter: "يفتح التفاصيل والإجراءات المتاحة"))
    }

    @ViewBuilder
    private var media: some View {
        if let url = record.primaryMediaURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                case .failure: placeholder
                default: ProgressView().tint(AdminSurface.primary)
                }
            }
            .frame(width: 60, height: 60)
            .background(AdminSurface.control)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        } else {
            placeholder
                .frame(width: 60, height: 60)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(AdminSurface.primary.opacity(0.1))
            .overlay(
                Image(systemName: record.source.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AdminSurface.primary)
            )
    }

    private func compactFact(_ symbol: String, _ value: Int) -> some View {
        Label(value.formatted(), systemImage: symbol)
            .font(PPBrandFont.bold(size: 11.5).monospacedDigit())
            .foregroundStyle(AdminSurface.secondaryText)
    }
}

// MARK: - Privacy-preserving operations map

private struct CommunityAdminMapCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let records: [CommunityAdminRecord]

    var color: Color {
        if records.contains(where: { $0.source == .missingCases }) { return .orange }
        if records.contains(where: { $0.source == .sightings }) { return .purple }
        return .teal
    }
}

private struct AdminCommunityOperationsMapView: View {
    @ObservedObject var store: AdminCommunityWorkspaceStore
    @State private var selectedLayers: Set<CommunityAdminLane> = [.missingCases, .foundReports, .sightings]
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedCluster: CommunityAdminMapCluster?

    private var visibleRecords: [CommunityAdminRecord] {
        store.records.filter { selectedLayers.contains($0.source) }
    }

    private var clusters: [CommunityAdminMapCluster] {
        let recordsWithLocation = visibleRecords.compactMap { record -> (CommunityAdminRecord, CLLocationCoordinate2D)? in
            guard let coordinate = record.coordinate(prefersPrecise: store.includePreciseLocation) else { return nil }
            return (record, coordinate)
        }
        let grouped = Dictionary(grouping: recordsWithLocation) { item in
            // Approximate/public points cluster at about 2 km. Precise access
            // remains visually clustered so the screen does not encourage
            // casual exact-location inspection.
            let latitudeBucket = Int((item.1.latitude * 50).rounded())
            let longitudeBucket = Int((item.1.longitude * 50).rounded())
            return "\(latitudeBucket):\(longitudeBucket)"
        }
        return grouped.map { key, items in
            let latitude = items.map { $0.1.latitude }.reduce(0, +) / Double(items.count)
            let longitude = items.map { $0.1.longitude }.reduce(0, +) / Double(items.count)
            return CommunityAdminMapCluster(
                id: key,
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                records: items.map(\.0)
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            mapToolbar
            if clusters.isEmpty {
                AdminCommunityEmptyState(
                    symbol: "map",
                    title: Language.get("Community_Admin_Map_Empty", alter: "لا توجد نقاط مكانية ضمن هذه الصفحة"),
                    body: Language.get("Community_Admin_Map_Empty_Body", alter: "قد تكون السجلات بلا إحداثيات عامة، أو أن الطبقات الحالية لا تحتوي نتائج."),
                    action: { Task { await store.refresh() } }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(18)
            } else {
                Map(position: $cameraPosition) {
                    ForEach(clusters) { cluster in
                        Annotation("", coordinate: cluster.coordinate, anchor: .center) {
                            Button {
                                if cluster.records.count == 1 { store.openDossier(cluster.records[0]) }
                                else { selectedCluster = cluster }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(cluster.color)
                                        .frame(width: cluster.records.count > 1 ? 42 : 34, height: cluster.records.count > 1 ? 42 : 34)
                                        .shadow(color: .black.opacity(0.16), radius: 7, y: 3)
                                    if cluster.records.count > 1 {
                                        Text(cluster.records.count.formatted())
                                            .font(AdminType.captionBold.monospacedDigit())
                                            .foregroundStyle(.white)
                                    } else {
                                        Image(systemName: cluster.records[0].source.symbol)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                String(
                                    format: Language.get("Community_Admin_Map_Cluster_Format", alter: "%d سجلات في هذه المنطقة"),
                                    cluster.records.count
                                )
                            )
                            .accessibilityHint(
                                cluster.records.count == 1
                                    ? Language.get("Community_Admin_Record_OpenHint", alter: "يفتح التفاصيل والإجراءات المتاحة")
                                    : Language.get("Community_Admin_Map_Cluster_Hint", alter: "يفتح قائمة سجلات هذه المنطقة")
                            )
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll, showsTraffic: false))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .overlay(alignment: .bottomLeading) {
                    privacyBadge.padding(14)
                }
                .accessibilityLabel(Language.get("Community_Admin_OperationsMap", alter: "خريطة عمليات المجتمع"))
            }
        }
        .background(AdminSurface.background)
        .sheet(item: $selectedCluster) { cluster in
            AdminCommunityMapClusterSheet(cluster: cluster, store: store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var mapToolbar: some View {
        VStack(alignment: .leading, spacing: 11) {
            AdminCommunitySectionHeader(
                title: Language.get("Community_Admin_OperationsMap", alter: "خريطة العمليات"),
                subtitle: Language.get("Community_Admin_Map_Subtitle", alter: "طبقات الحالات والمشاهدات وبلاغات العثور؛ المواقع التقريبية هي الوضع الافتراضي."),
                symbol: "map.fill"
            )
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([CommunityAdminLane.missingCases, .foundReports, .sightings], id: \.self) { lane in
                        if store.canAccess(lane) {
                            Button {
                                if selectedLayers.contains(lane) { selectedLayers.remove(lane) }
                                else { selectedLayers.insert(lane) }
                            } label: {
                                Label(Language.get(lane.titleKey, alter: lane.fallbackTitle), systemImage: lane.symbol)
                                    .font(AdminType.captionBold)
                                    .foregroundStyle(selectedLayers.contains(lane) ? Color.white : AdminSurface.primaryText)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 38)
                                    .background(selectedLayers.contains(lane) ? AdminSurface.primary : AdminSurface.control, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selectedLayers.contains(lane) ? .isSelected : [])
                        }
                    }
                    if store.canViewPreciseLocation {
                        Button {
                            Task { await store.setPreciseLocation(!store.includePreciseLocation) }
                        } label: {
                            Label(
                                store.includePreciseLocation
                                    ? Language.get("Community_Admin_Precise_On", alter: "الموقع الدقيق ظاهر")
                                    : Language.get("Community_Admin_Precise_Off", alter: "إظهار الموقع الدقيق"),
                                systemImage: store.includePreciseLocation ? "location.fill" : "location.slash"
                            )
                            .font(AdminType.captionBold)
                            .foregroundStyle(store.includePreciseLocation ? Color.white : AdminSurface.crimson)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 38)
                            .background(store.includePreciseLocation ? AdminSurface.crimson : AdminSurface.crimson.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Language.get("Community_Admin_Precise_Audit_Hint", alter: "تُسجل هذه القراءة في سجل التدقيق"))
                    }
                }
            }
            if store.canViewPreciseLocation {
                VStack(alignment: .leading, spacing: 7) {
                    Label(
                        Language.get("Community_Admin_Private_Access_Reason", alter: "سبب الوصول الخاص"),
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(AdminType.captionBold)
                    .foregroundStyle(AdminSurface.secondaryText)
                    TextField(
                        Language.get("Community_Admin_Private_Access_Reason_Placeholder", alter: "اشرح سبب الحاجة إلى هذه البيانات"),
                        text: $store.privateAccessReason,
                        axis: .vertical
                    )
                    .font(AdminType.callout)
                    .lineLimit(1...3)
                    .padding(.horizontal, 13)
                    .frame(minHeight: 46)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
                    .accessibilityHint(Language.get("Community_Admin_Sensitive_Evidence_Audit_Hint", alter: "تتطلب هذه القراءة سببًا وتُسجل في سجل التدقيق"))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AdminSurface.surface)
    }

    private var privacyBadge: some View {
        Label(
            store.includePreciseLocation
                ? Language.get("Community_Admin_Map_Precise_Badge", alter: "وضع دقيق · قراءة مدققة")
                : Language.get("Community_Admin_Map_Approximate_Badge", alter: "مواقع عامة تقريبية"),
            systemImage: store.includePreciseLocation ? "lock.open.fill" : "lock.fill"
        )
        .font(AdminType.captionBold)
        .foregroundStyle(store.includePreciseLocation ? AdminSurface.crimson : AdminSurface.primaryText)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(AdminSurface.hairline, lineWidth: 0.8))
    }
}

private struct AdminCommunityMapClusterSheet: View {
    let cluster: CommunityAdminMapCluster
    @ObservedObject var store: AdminCommunityWorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRecord: CommunityAdminRecord?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(cluster.records) { record in
                        AdminCommunityRecordCard(record: record) {
                            selectedRecord = record
                            store.loadDossier(record)
                        }
                    }
                }
                .padding(16)
            }
            .background(AdminSurface.background)
            .navigationTitle(Language.get("Community_Admin_Map_Cluster_Title", alter: "سجلات هذه المنطقة"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Language.get("Done", alter: "تم")) { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(item: $selectedRecord, onDismiss: {
            store.dismissDossier()
        }) { record in
            AdminCommunityRecordDetailView(record: record, store: store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Analytics

private struct AdminCommunityAnalyticsView: View {
    @ObservedObject var store: AdminCommunityWorkspaceStore

    private struct Metric: Identifiable {
        let id: String
        let key: String
        let titleKey: String
        let fallback: String
        let format: Format
        enum Format { case integer, percent }
    }

    private let metrics: [Metric] = [
        .init(id: "listings", key: "listings", titleKey: "Community_Admin_Analytics_Listings", fallback: "إعلانات التبني", format: .integer),
        .init(id: "applications", key: "applications", titleKey: "Community_Admin_Analytics_Applications", fallback: "طلبات التبني", format: .integer),
        .init(id: "missing", key: "missingCases", titleKey: "Community_Admin_Analytics_Missing", fallback: "حالات الفقدان", format: .integer),
        .init(id: "sightings", key: "sightings", titleKey: "Community_Admin_Analytics_Sightings", fallback: "المشاهدات", format: .integer),
        .init(id: "matches", key: "matches", titleKey: "Community_Admin_Analytics_Matches", fallback: "المطابقات", format: .integer),
        .init(id: "reunited", key: "reunited", titleKey: "Community_Admin_Analytics_Reunited", fallback: "لمّ الشمل", format: .integer),
        .init(id: "applicationRate", key: "adoptionApplicationRate", titleKey: "Community_Admin_Analytics_ApplicationRate", fallback: "معدل التحويل إلى طلب", format: .percent),
        .init(id: "reunionRate", key: "reunionRate", titleKey: "Community_Admin_Analytics_ReunionRate", fallback: "معدل لمّ الشمل", format: .percent)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                AdminCommunitySectionHeader(
                    title: Language.get("Community_Admin_Analytics_Title", alter: "أثر المجتمع"),
                    subtitle: Language.get("Community_Admin_Analytics_Subtitle", alter: "مقاييس مجمعة من الخادم تساعد التشغيل دون كشف بيانات شخصية."),
                    symbol: "chart.xyaxis.line"
                )
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                    ForEach(metrics) { metric in
                        VStack(alignment: .leading, spacing: 9) {
                            Text(formatted(metric))
                                .font(AdminType.title2.monospacedDigit())
                                .foregroundStyle(AdminSurface.primaryText)
                            Text(Language.get(metric.titleKey, alter: metric.fallback))
                                .font(AdminType.caption)
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
                        .accessibilityElement(children: .combine)
                    }
                }

                if let daily = store.analytics["daily"] as? [[String: Any]], !daily.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(Language.get("Community_Admin_Analytics_Daily", alter: "المؤشرات اليومية"))
                            .font(AdminType.headline)
                            .foregroundStyle(AdminSurface.primaryText)
                        ForEach(Array(daily.suffix(14).reversed().enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 10) {
                                Text(item["id"] as? String ?? "—")
                                    .font(AdminType.captionBold.monospaced())
                                    .foregroundStyle(AdminSurface.primaryText)
                                Spacer()
                                Text(CommunityAdminValueFormatter.summary(item))
                                    .font(AdminType.caption)
                                    .foregroundStyle(AdminSurface.secondaryText)
                                    .lineLimit(1)
                            }
                            if item["id"] as? String != daily.last?["id"] as? String {
                                Divider().overlay(AdminSurface.hairline)
                            }
                        }
                    }
                    .padding(17)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
                }
            }
            .padding(16)
            .padding(.vertical, 4)
        }
        .refreshable { await store.refresh() }
    }

    private func formatted(_ metric: Metric) -> String {
        let value = (store.analytics[metric.key] as? NSNumber)?.doubleValue ?? 0
        switch metric.format {
        case .integer: return Int(value).formatted()
        case .percent: return value.formatted(.percent.precision(.fractionLength(1)))
        }
    }
}

// MARK: - Configuration

private struct AdminCommunityConfigurationView: View {
    @ObservedObject var store: AdminCommunityWorkspaceStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingSaveConfirmation = false
    @State private var configurationReason = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                AdminCommunitySectionHeader(
                    title: Language.get("Community_Admin_Config_Title", alter: "سياسة المجتمع وإطلاقه"),
                    subtitle: Language.get("Community_Admin_Config_Subtitle", alter: "إعدادات خادمية بإصدار متفائل؛ ثوابت الخصوصية والمراجعة لا يمكن تعطيلها من العميل."),
                    symbol: "slider.horizontal.3"
                )

                versionAndInvariants
                configurationSection(Language.get("Community_Admin_Config_Features", alter: "ميزات ومسارات"), symbol: "switch.2") {
                    featureToggles
                }
                configurationSection(Language.get("Community_Admin_Config_Rollout", alter: "الإطلاق والمناطق"), symbol: "globe.europe.africa.fill") {
                    rolloutFields
                }
                configurationSection(Language.get("Community_Admin_Config_Policies", alter: "سياسات التبني والمفقودات"), symbol: "checklist") {
                    policyFields
                }
                configurationSection(Language.get("Community_Admin_Config_Taxonomy", alter: "التصنيفات المرجعية"), symbol: "square.grid.2x2.fill") {
                    taxonomyEditors
                }
                configurationSection(Language.get("Community_Admin_Config_Questions", alter: "أسئلة طلب التبني"), symbol: "questionmark.bubble.fill") {
                    questionsEditor
                }
                configurationSection(Language.get("Community_Admin_Config_Notifications", alter: "قوالب الإشعارات"), symbol: "bell.badge.fill") {
                    notificationTemplatesEditor
                }

                configurationSection(Language.get("Community_Admin_Config_Reason", alter: "سبب التغيير"), symbol: "text.bubble") {
                    TextField(
                        Language.get("Community_Admin_Config_Reason_Placeholder", alter: "اشرح سبب هذا التغيير التشغيلي"),
                        text: $configurationReason,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                    .textInputAutocapitalization(.sentences)
                    .padding(13)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityLabel(Language.get("Community_Admin_Config_Reason", alter: "سبب التغيير"))
                }

                Button {
                    showingSaveConfirmation = true
                } label: {
                    HStack(spacing: 9) {
                        if store.isMutating { ProgressView().tint(.white) }
                        Image(systemName: "checkmark.shield.fill")
                        Text(Language.get("Community_Admin_Config_Save", alter: "حفظ إعدادات المجتمع"))
                            .font(AdminType.calloutBold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(store.isMutating)
            }
            .padding(horizontalSizeClass == .regular ? 24 : 16)
            .padding(.vertical, 20)
        }
        .alert(Language.get("Community_Admin_Config_Confirm_Title", alter: "تطبيق إعدادات جديدة؟"), isPresented: $showingSaveConfirmation) {
            Button(Language.get("Cancel", alter: "إلغاء"), role: .cancel) {}
            Button(Language.get("Community_Admin_Config_Apply", alter: "تطبيق")) {
                Task {
                    if await store.saveConfiguration(reason: configurationReason) {
                        configurationReason = ""
                    }
                }
            }
        } message: {
            Text(Language.get("Community_Admin_Config_Confirm_Body", alter: "سيتم التحقق من الإصدار والقيم على الخادم ثم تسجيل التغيير في سجل التدقيق."))
        }
    }

    private var versionAndInvariants: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AdminSurface.emerald)
                .frame(width: 40, height: 40)
                .background(AdminSurface.emerald.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(String(format: Language.get("Community_Admin_Config_Version_Format", alter: "الإصدار الحالي: %d"), store.configuration.version))
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                Text(Language.get("Community_Admin_Config_Invariants", alter: "مراجعة القوائم والحالات، دقة الموقع العام المحدودة، ومراجعة الصور ثوابت إلزامية على الخادم."))
                    .font(AdminType.callout)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(AdminSurface.emerald.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.emerald.opacity(0.2), lineWidth: 0.8))
    }

    private var featureToggles: some View {
        VStack(spacing: 0) {
            configToggle("Community_Admin_Config_Community", "المجتمع بالكامل", $store.configuration.communityEnabled)
            configToggle("Community_Admin_Config_Adoption", "التبني", $store.configuration.adoptionEnabled)
            configToggle("Community_Admin_Config_Applications", "طلبات التبني", $store.configuration.adoptionApplicationsEnabled)
            configToggle("Community_Admin_Config_Missing", "الحيوانات المفقودة", $store.configuration.missingPetsEnabled)
            configToggle("Community_Admin_Config_Found", "بلاغات العثور", $store.configuration.foundPetReportsEnabled)
            configToggle("Community_Admin_Config_Sightings", "المشاهدات", $store.configuration.sightingsEnabled)
            configToggle("Community_Admin_Config_Matching", "المطابقة", $store.configuration.matchingEnabled)
            configToggle("Community_Admin_Config_Messaging", "مراسلات المجتمع", $store.configuration.communityMessagingEnabled)
            configToggle("Community_Admin_Config_AI", "مطابقة الصور الذكية", $store.configuration.aiImageMatchingEnabled)
            configToggle("Community_Admin_Config_Organizations", "المنظمات", $store.configuration.organizationsEnabled)
            configToggle("Community_Admin_Config_OrgVerification", "توثيق المنظمات", $store.configuration.organizationVerificationEnabled)
            configToggle("Community_Admin_Config_Map", "خريطة عمليات الإدارة", $store.configuration.adminOperationsMapEnabled, showsDivider: false)
        }
    }

    private var rolloutFields: some View {
        VStack(spacing: 14) {
            Picker(Language.get("Community_Admin_Config_Stage", alter: "مرحلة الإطلاق"), selection: $store.configuration.rolloutStage) {
                ForEach(["internal", "trusted_organizations", "regional_beta", "public_beta", "full"], id: \.self) { stage in
                    Text(CommunityAdminLocalization.state(stage)).tag(stage)
                }
            }
            .pickerStyle(.menu)
            .tint(AdminSurface.primary)

            configTextField(
                Language.get("Community_Admin_Config_Countries", alter: "رموز الدول المدعومة"),
                placeholder: Language.get("Community_Admin_Config_Countries_Placeholder", alter: "KW, SA, AE"),
                text: $store.configuration.supportedCountries
            )
            configTextField(
                Language.get("Community_Admin_Config_Regions", alter: "رموز المناطق المفعلة"),
                placeholder: Language.get("Community_Admin_Config_Regions_Placeholder", alter: "KW-HAWALLI, KW-CAPITAL"),
                text: $store.configuration.enabledRegions
            )
        }
    }

    private var policyFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            numericStepper(
                Language.get("Community_Admin_Config_ListingExpiry", alter: "انتهاء إعلان التبني"),
                suffix: Language.get("Days", alter: "يوم"),
                value: $store.configuration.listingExpirationDays,
                range: 7...365,
                step: 1
            )
            numericStepper(
                Language.get("Community_Admin_Config_CaseExpiry", alter: "انتهاء حالة الفقدان"),
                suffix: Language.get("Days", alter: "يوم"),
                value: $store.configuration.caseExpirationDays,
                range: 7...365,
                step: 1
            )
            numericStepper(
                Language.get("Community_Admin_Config_Radius", alter: "نطاق الظهور الافتراضي"),
                suffix: Language.get("Community_Admin_Kilometers", alter: "كم"),
                value: $store.configuration.defaultMissingRadiusKM,
                range: 1...100,
                step: 1
            )
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(Language.get("Community_Admin_Config_MatchThreshold", alter: "حد المطابقة الآلية"))
                        .font(AdminType.callout)
                    Spacer()
                    Text(store.configuration.autoMatchThreshold.formatted(.percent.precision(.fractionLength(0))))
                        .font(AdminType.calloutBold.monospacedDigit())
                }
                Slider(value: $store.configuration.autoMatchThreshold, in: 0.5...0.95, step: 0.01)
                    .tint(AdminSurface.primary)
            }
            confidenceThreshold(
                Language.get("Community_Admin_Config_MatchMediumConfidence", alter: "حد الثقة المتوسط"),
                value: $store.configuration.mediumMatchConfidenceThreshold,
                range: 0.5...0.94
            )
            .onChange(of: store.configuration.mediumMatchConfidenceThreshold) { medium in
                store.configuration.highMatchConfidenceThreshold = max(
                    store.configuration.highMatchConfidenceThreshold,
                    min(0.99, medium + 0.01)
                )
            }
            confidenceThreshold(
                Language.get("Community_Admin_Config_MatchHighConfidence", alter: "حد الثقة المرتفع"),
                value: $store.configuration.highMatchConfidenceThreshold,
                range: 0.51...0.99
            )
            Picker(Language.get("Community_Admin_Config_ApplicationPolicy", alter: "سلطة اختيار المتبني"), selection: $store.configuration.applicationPolicy) {
                Text(Language.get("Community_Admin_Config_OwnerManaged", alter: "صاحب الإعلان")).tag("owner_managed")
                Text(Language.get("Community_Admin_Config_OrgManaged", alter: "المنظمة")).tag("organization_managed")
            }
            .pickerStyle(.menu)
            Toggle(Language.get("Community_Admin_Config_SightingPhoto", alter: "الصورة إلزامية في المشاهدة"), isOn: $store.configuration.sightingPhotoRequired)
                .font(AdminType.callout)
                .tint(AdminSurface.primary)
            numericStepper(
                Language.get("Community_Admin_Config_HighRisk", alter: "حد البلاغ عالي الخطورة"),
                suffix: Language.get("Community_Admin_Reports", alter: "بلاغ"),
                value: $store.configuration.highRiskReportThreshold,
                range: 1...20,
                step: 1
            )
            numericStepper(
                Language.get("Community_Admin_Config_AutoHide", alter: "حد الإخفاء الوقائي"),
                suffix: Language.get("Community_Admin_Reports", alter: "بلاغ"),
                value: $store.configuration.autoHideReportThreshold,
                range: 2...50,
                step: 1
            )
            configTextField(
                Language.get("Community_Admin_Config_OrgDocuments", alter: "أنواع مستندات المنظمة المطلوبة"),
                placeholder: Language.get("Community_Admin_Config_OrgDocuments_Placeholder", alter: "license, address_proof"),
                text: $store.configuration.requiredOrganizationDocuments
            )
        }
    }

    private var taxonomyEditors: some View {
        VStack(spacing: 12) {
            taxonomyEditor(Language.get("Community_Admin_Config_Species", alter: "الأنواع"), entries: $store.configuration.species)
            taxonomyEditor(Language.get("Community_Admin_Config_Breeds", alter: "السلالات"), entries: $store.configuration.breeds, includesSpecies: true)
            taxonomyEditor(Language.get("Community_Admin_Config_Colors", alter: "الألوان"), entries: $store.configuration.colors)
            taxonomyEditor(Language.get("Community_Admin_Config_Sizes", alter: "الأحجام"), entries: $store.configuration.sizes)
            taxonomyEditor(Language.get("Community_Admin_Config_Temperaments", alter: "سمات الطبع"), entries: $store.configuration.temperamentTags)
        }
    }

    private func taxonomyEditor(
        _ title: String,
        entries: Binding<[CommunityConfigurationCatalogEntry]>,
        includesSpecies: Bool = false
    ) -> some View {
        DisclosureGroup {
            VStack(spacing: 10) {
                ForEach(entries) { $entry in
                    VStack(spacing: 8) {
                        HStack {
                            TextField(Language.get("Community_Admin_Config_Key", alter: "المعرّف"), text: $entry.key)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                            Button(role: .destructive) {
                                entries.wrappedValue.removeAll { $0.id == entry.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel(Language.get("Delete", alter: "حذف"))
                        }
                        HStack {
                            TextField(Language.get("Community_Admin_Config_LabelAr", alter: "الاسم العربي"), text: $entry.labelAr)
                            TextField(Language.get("Community_Admin_Config_LabelEn", alter: "الاسم الإنجليزي"), text: $entry.labelEn)
                                .environment(\.layoutDirection, .leftToRight)
                        }
                        if includesSpecies {
                            TextField(Language.get("Community_Admin_Config_SpeciesKey", alter: "معرّف النوع الأب"), text: $entry.speciesID)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                        }
                    }
                    .font(AdminType.callout)
                    .padding(12)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                Button {
                    entries.wrappedValue.append(CommunityConfigurationCatalogEntry())
                } label: {
                    Label(Language.get("Community_Admin_Config_AddEntry", alter: "إضافة عنصر"), systemImage: "plus.circle.fill")
                        .font(AdminType.captionBold)
                }
            }
            .padding(.top, 10)
        } label: {
            HStack {
                Text(title).font(AdminType.calloutBold)
                Spacer()
                Text(entries.wrappedValue.count.formatted())
                    .font(AdminType.captionBold.monospacedDigit())
                    .foregroundStyle(AdminSurface.secondaryText)
            }
        }
        .tint(AdminSurface.primary)
    }

    private var questionsEditor: some View {
        VStack(spacing: 10) {
            ForEach($store.configuration.adoptionQuestions) { $question in
                VStack(spacing: 9) {
                    HStack {
                        TextField(Language.get("Community_Admin_Config_Key", alter: "المعرّف"), text: $question.key)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                        Button(role: .destructive) {
                            store.configuration.adoptionQuestions.removeAll { $0.id == question.id }
                        } label: { Image(systemName: "trash") }
                    }
                    TextField(Language.get("Community_Admin_Config_QuestionAr", alter: "السؤال بالعربية"), text: $question.titleAr)
                    TextField(Language.get("Community_Admin_Config_QuestionEn", alter: "السؤال بالإنجليزية"), text: $question.titleEn)
                        .environment(\.layoutDirection, .leftToRight)
                    HStack {
                        Picker(Language.get("Community_Admin_Config_AnswerType", alter: "نوع الإجابة"), selection: $question.type) {
                            ForEach(["text", "long_text", "yes_no", "single_choice", "multiple_choice"], id: \.self) { type in
                                Text(CommunityAdminLocalization.state(type)).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                        Toggle(Language.get("Required", alter: "مطلوب"), isOn: $question.required)
                    }
                    if ["single_choice", "multiple_choice"].contains(question.type) {
                        VStack(spacing: 8) {
                            ForEach($question.options) { $option in
                                VStack(spacing: 7) {
                                    HStack {
                                        TextField(Language.get("Community_Admin_Config_OptionKey", alter: "معرّف الخيار"), text: $option.key)
                                            .textInputAutocapitalization(.never)
                                            .disableAutocorrection(true)
                                        Button(role: .destructive) {
                                            question.options.removeAll { $0.id == option.id }
                                        } label: { Image(systemName: "minus.circle.fill") }
                                            .accessibilityLabel(Language.get("Delete", alter: "حذف"))
                                    }
                                    TextField(Language.get("Community_Admin_Config_OptionAr", alter: "الخيار بالعربية"), text: $option.labelAr)
                                    TextField(Language.get("Community_Admin_Config_OptionEn", alter: "الخيار بالإنجليزية"), text: $option.labelEn)
                                        .environment(\.layoutDirection, .leftToRight)
                                }
                                .padding(10)
                                .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            }
                            Button {
                                question.options.append(CommunityConfigurationQuestionOption())
                            } label: {
                                Label(Language.get("Community_Admin_Config_AddOption", alter: "إضافة خيار"), systemImage: "plus.circle")
                                    .font(AdminType.captionBold)
                            }
                        }
                    }
                }
                .font(AdminType.callout)
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            Button {
                store.configuration.adoptionQuestions.append(CommunityConfigurationQuestion())
            } label: {
                Label(Language.get("Community_Admin_Config_AddQuestion", alter: "إضافة سؤال"), systemImage: "plus.circle.fill")
                    .font(AdminType.captionBold)
            }
        }
    }

    private var notificationTemplatesEditor: some View {
        VStack(spacing: 10) {
            ForEach($store.configuration.templates) { $template in
                DisclosureGroup {
                    VStack(spacing: 8) {
                        TextField(Language.get("Community_Admin_Config_TemplateKey", alter: "مفتاح القالب"), text: $template.key)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                        TextField(Language.get("Community_Admin_Config_ArabicTitle", alter: "العنوان العربي"), text: $template.arabicTitle)
                        TextField(Language.get("Community_Admin_Config_ArabicBody", alter: "النص العربي"), text: $template.arabicBody, axis: .vertical)
                            .lineLimit(2...5)
                        TextField(Language.get("Community_Admin_Config_EnglishTitle", alter: "العنوان الإنجليزي"), text: $template.englishTitle)
                            .environment(\.layoutDirection, .leftToRight)
                        TextField(Language.get("Community_Admin_Config_EnglishBody", alter: "النص الإنجليزي"), text: $template.englishBody, axis: .vertical)
                            .lineLimit(2...5)
                            .environment(\.layoutDirection, .leftToRight)
                        Button(role: .destructive) {
                            store.configuration.templates.removeAll { $0.id == template.id }
                        } label: {
                            Label(Language.get("Delete", alter: "حذف"), systemImage: "trash")
                                .font(AdminType.captionBold)
                        }
                    }
                    .font(AdminType.callout)
                    .padding(.top, 10)
                } label: {
                    Text(template.key.isEmpty
                         ? Language.get("Community_Admin_Config_NewTemplate", alter: "قالب جديد")
                         : template.key)
                        .font(AdminType.calloutBold.monospaced())
                }
                .tint(AdminSurface.primary)
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            Button {
                store.configuration.templates.append(CommunityNotificationTemplateDraft())
            } label: {
                Label(Language.get("Community_Admin_Config_AddTemplate", alter: "إضافة قالب"), systemImage: "plus.circle.fill")
                    .font(AdminType.captionBold)
            }
        }
    }

    private func configurationSection<Content: View>(
        _ title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)
            content()
        }
        .padding(17)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
    }

    private func configToggle(_ key: String, _ fallback: String, _ binding: Binding<Bool>, showsDivider: Bool = true) -> some View {
        VStack(spacing: 0) {
            Toggle(Language.get(key, alter: fallback), isOn: binding)
                .font(AdminType.callout)
                .tint(AdminSurface.primary)
                .frame(minHeight: 44)
            if showsDivider { Divider().overlay(AdminSurface.hairline) }
        }
    }

    private func configTextField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(AdminType.captionBold).foregroundStyle(AdminSurface.secondaryText)
            TextField(placeholder, text: text)
                .font(AdminType.callout)
                .textInputAutocapitalization(.characters)
                .disableAutocorrection(true)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func numericStepper(_ title: String, suffix: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title).font(AdminType.callout)
                Spacer()
                Text("\(Int(value.wrappedValue).formatted()) \(suffix)")
                    .font(AdminType.calloutBold.monospacedDigit())
                    .foregroundStyle(AdminSurface.primary)
            }
        }
    }

    private func confidenceThreshold(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(AdminType.callout)
                Spacer()
                Text(value.wrappedValue.formatted(.percent.precision(.fractionLength(0))))
                    .font(AdminType.calloutBold.monospacedDigit())
            }
            Slider(value: value, in: range, step: 0.01)
                .tint(AdminSurface.primary)
        }
    }
}

// MARK: - Record dossier and mutation confirmation

private struct AdminCommunityRecordDetailView: View {
    let record: CommunityAdminRecord
    @ObservedObject var store: AdminCommunityWorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var intent: CommunityAdminActionDescriptor?

    private var currentRecord: CommunityAdminRecord {
        guard let dossierRecord = store.dossierRecord,
              dossierRecord.id == record.id,
              dossierRecord.source == record.source else {
            return record
        }
        return dossierRecord
    }

    private var actions: [CommunityAdminActionDescriptor] {
        guard store.session.hasGlobalScope else { return [] }
        return CommunityAdminActionPolicy.actions(for: currentRecord, session: store.session)
    }

    var body: some View {
        let record = currentRecord
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    identityCard
                    lifecycleCard
                    if record.source == .matches {
                        matchComparisonCard
                    }
                    domainFacts
                    if store.isLoadingDossier {
                        dossierLoadingCard
                    } else if let dossierErrorMessage = store.dossierErrorMessage {
                        dossierErrorCard(dossierErrorMessage)
                    } else if !store.dossierSections.isEmpty {
                        dossierEvidence
                    }
                    if record.source == .adoptionApplications, !applicationAnswerRows.isEmpty {
                        applicationAnswersCard
                    }
                    if let coordinate = record.coordinate(prefersPrecise: store.includePreciseLocation) {
                        locationCard(coordinate)
                    }
                    if let privateData = record.value("private") as? [String: Any], !privateData.isEmpty {
                        privateDataCard(privateData)
                    }
                    if !actions.isEmpty {
                        actionsCard
                    } else if record.source == .adoptionApplications {
                        oversightNotice
                    }
                }
                .padding(16)
            }
            .background(AdminSurface.background)
            .navigationTitle(Language.get("Community_Admin_Dossier", alter: "ملف العملية"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Language.get("Done", alter: "تم")) { dismiss() }
                }
            }
            .overlay(alignment: .top) {
                if let message = store.errorMessage {
                    AdminCommunityErrorBanner(
                        message: message,
                        dismiss: { store.clearMessages() },
                        retry: nil
                    )
                    .padding(12)
                }
            }
            .sheet(item: $intent) { action in
                AdminCommunityActionConfirmationView(record: record, action: action, store: store)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    @ViewBuilder
    private var identityCard: some View {
        let record = currentRecord
        HStack(alignment: .top, spacing: 14) {
            Group {
                if let url = record.primaryMediaURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase { image.resizable().scaledToFill() }
                        else { dossierPlaceholder }
                    }
                } else {
                    dossierPlaceholder
                }
            }
            .frame(width: 82, height: 82)
            .background(AdminSurface.control)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(record.title)
                    .font(AdminType.title3)
                    .foregroundStyle(AdminSurface.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(record.subtitle)
                    .font(AdminType.callout)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(record.id)
                    .font(AdminType.caption2.monospaced())
                    .foregroundStyle(AdminSurface.secondaryText)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
    }

    @ViewBuilder
    private var dossierPlaceholder: some View {
        let record = currentRecord
        ZStack {
            AdminSurface.primary.opacity(0.1)
            Image(systemName: record.source.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(AdminSurface.primary)
        }
    }

    @ViewBuilder
    private var lifecycleCard: some View {
        let record = currentRecord
        VStack(alignment: .leading, spacing: 12) {
            Label(Language.get("Community_Admin_Lifecycle", alter: "الحالة ودقة التزامن"), systemImage: "arrow.triangle.2.circlepath")
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)
            HStack(spacing: 8) {
                AdminCommunityStatusBadge(status: record.status)
                if !record.moderationStatus.isEmpty, record.moderationStatus != record.status {
                    AdminCommunityStatusBadge(status: record.moderationStatus, compact: true)
                }
                Spacer()
                Text(String(format: Language.get("Community_Admin_Version_Format", alter: "الإصدار %d"), record.version))
                    .font(AdminType.captionBold.monospacedDigit())
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            if !record.lastUpdatedText.isEmpty {
                Label(record.lastUpdatedText, systemImage: "clock")
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            Text(Language.get("Community_Admin_Concurrency_Hint", alter: "أي تغيير متزامن يوقف القرار ويطلب إعادة تحميل النسخة الأحدث."))
                .font(AdminType.caption)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
    }

    private var domainFacts: some View {
        let facts = detailFacts
        return VStack(alignment: .leading, spacing: 12) {
            Label(Language.get("Community_Admin_Details", alter: "تفاصيل موثوقة"), systemImage: "list.bullet.rectangle.portrait")
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)
            ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                HStack(alignment: .top, spacing: 10) {
                    Text(fact.0)
                        .font(AdminType.caption)
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(minWidth: 92, alignment: .leading)
                    Spacer(minLength: 10)
                    Text(fact.1)
                        .font(AdminType.calloutBold)
                        .foregroundStyle(AdminSurface.primaryText)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                if index < facts.count - 1 { Divider().overlay(AdminSurface.hairline) }
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
    }

    private var matchComparisonCard: some View {
        let record = currentRecord
        return VStack(alignment: .leading, spacing: 14) {
            Label(Language.get("Community_Admin_Match_Comparison", alter: "مقارنة التطابق"), systemImage: "rectangle.split.2x1.fill")
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)
            Text(Language.get("Community_Admin_Match_Comparison_Hint", alter: "قارن الصور والعلامات المميزة قبل اتخاذ القرار. تبقى المواقع والمعرّفات الخاصة محمية."))
                .font(AdminType.caption)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 12) {
                        comparisonSide(
                            title: Language.get("Community_Admin_Match_MissingPet", alter: "الحيوان المفقود"),
                            name: record.string("comparison.missing.pet.name", "comparison.missing.pet.displayName"),
                            detail: record.string("comparison.missing.appearance.distinctiveMarks", "comparison.missing.description"),
                            mediaURL: record.missingComparisonMediaURL,
                            tint: .orange
                        )
                        comparisonSide(
                            title: Language.get("Community_Admin_Match_FoundReport", alter: "بلاغ العثور"),
                            name: record.string("comparison.found.appearance.breed", "comparison.found.appearance.speciesId"),
                            detail: record.string("comparison.found.appearance.distinctiveMarks", "comparison.found.description"),
                            mediaURL: record.foundComparisonMediaURL,
                            tint: .teal
                        )
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        comparisonSide(
                            title: Language.get("Community_Admin_Match_MissingPet", alter: "الحيوان المفقود"),
                            name: record.string("comparison.missing.pet.name", "comparison.missing.pet.displayName"),
                            detail: record.string("comparison.missing.appearance.distinctiveMarks", "comparison.missing.description"),
                            mediaURL: record.missingComparisonMediaURL,
                            tint: .orange
                        )
                        comparisonSide(
                            title: Language.get("Community_Admin_Match_FoundReport", alter: "بلاغ العثور"),
                            name: record.string("comparison.found.appearance.breed", "comparison.found.appearance.speciesId"),
                            detail: record.string("comparison.found.appearance.distinctiveMarks", "comparison.found.description"),
                            mediaURL: record.foundComparisonMediaURL,
                            tint: .teal
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
    }

    private func comparisonSide(
        title: String,
        name: String,
        detail: String,
        mediaURL: URL?,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Group {
                if let mediaURL {
                    AsyncImage(url: mediaURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else if case .failure = phase {
                            comparisonPlaceholder(tint: tint)
                        } else {
                            ProgressView().tint(tint)
                        }
                    }
                } else {
                    comparisonPlaceholder(tint: tint)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 180)
            .background(AdminSurface.control)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            Text(title)
                .font(AdminType.captionBold)
                .foregroundStyle(tint)
            Text(name.isEmpty ? Language.get("Community_Admin_Value_Unknown", alter: "غير متاح") : name)
                .font(AdminType.calloutBold)
                .foregroundStyle(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if !detail.isEmpty {
                Text(detail)
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func comparisonPlaceholder(tint: Color) -> some View {
        ZStack {
            tint.opacity(0.09)
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
        }
    }

    private var detailFacts: [(String, String)] {
        let record = currentRecord
        var facts: [(String, String)] = []
        func add(_ key: String, _ fallback: String, _ value: String) {
            guard !value.isEmpty else { return }
            facts.append((Language.get(key, alter: fallback), value))
        }
        add("Community_Admin_Field_Pet", "الحيوان", record.string("pet.name", "pet.displayName"))
        add("Community_Admin_Field_Species", "النوع", record.string("appearance.speciesId", "pet.speciesId", "speciesId"))
        add("Community_Admin_Field_Breed", "السلالة", record.string("appearance.breed", "pet.breed", "breed"))
        add("Community_Admin_Field_Owner", "المالك", record.string("ownerUid", "caseOwnerUid"))
        add("Community_Admin_Field_Reporter", "المبلّغ", record.string("reporterUid"))
        add("Community_Admin_Field_Applicant", "مقدم الطلب", record.string("applicantUid"))
        add("Community_Admin_Field_Organization", "المنظمة", record.string("organizationId", "organizationName"))
        add("Community_Admin_Field_Target", "المحتوى المستهدف", record.string("targetType") + (record.string("targetId").isEmpty ? "" : " · \(record.string("targetId"))"))
        add("Community_Admin_Field_Reason", "السبب", record.string("latestReason", "reason", "moderationReason"))
        add("Community_Admin_Field_Description", "الوصف", record.string("description", "notes", "message"))
        add("Community_Admin_Field_Region", "المنطقة", [record.string("area.district"), record.string("area.city"), record.string("area.countryCode")].filter { !$0.isEmpty }.joined(separator: " · "))
        add("Community_Admin_Field_Custody", "حالة الرعاية", CommunityAdminLocalization.optionalState(record.string("custodyStatus")))
        add("Community_Admin_Field_Risk", "الخطورة", CommunityAdminLocalization.optionalState(record.string("priority", "riskLevel", "confidenceBand")))
        if let score = record.decimal("score") {
            add("Community_Admin_Field_MatchScore", "درجة المطابقة", score.formatted(.percent.precision(.fractionLength(1))))
        }
        if let distance = record.decimal("distanceKm") {
            add("Community_Admin_Field_Distance", "المسافة", "\(distance.formatted(.number.precision(.fractionLength(1)))) \(Language.get("Community_Admin_Kilometers", alter: "كم"))")
        }
        if let hours = record.decimal("timeDeltaHours") {
            add("Community_Admin_Field_TimeDelta", "الفارق الزمني", "\(hours.formatted(.number.precision(.fractionLength(1)))) \(Language.get("Community_Admin_Hours", alter: "ساعة"))")
        }
        for (key, localization, fallback) in [
            ("applicationCount", "Community_Admin_Field_Applications", "الطلبات"),
            ("sightingCount", "Community_Admin_Field_Sightings", "المشاهدات"),
            ("matchCount", "Community_Admin_Field_Matches", "المطابقات"),
            ("reportCount", "Community_Admin_Field_Reports", "البلاغات")
        ] where record.integer(key) > 0 {
            add(localization, fallback, record.integer(key).formatted())
        }
        if let signals = record.value("signals") as? [String: Any], !signals.isEmpty {
            add("Community_Admin_Field_Signals", "إشارات المطابقة", CommunityAdminValueFormatter.percentSummary(signals))
        }
        return facts.isEmpty
            ? [(Language.get("Community_Admin_Field_ID", alter: "المعرّف"), record.id)]
            : facts
    }

    private var applicationAnswersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(Language.get("Community_Admin_Application_Answers", alter: "إجابات طلب التبني"), systemImage: "checklist.checked")
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)
            Text(Language.get("Community_Admin_Application_Answers_Hint", alter: "بيانات خاصة بالمراجعة؛ استخدمها فقط لتقييم ملاءمة التبني."))
                .font(AdminType.caption)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(applicationAnswerRows.enumerated()), id: \.offset) { index, row in
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.0).font(AdminType.captionBold).foregroundStyle(AdminSurface.secondaryText)
                    Text(row.1).font(AdminType.callout).foregroundStyle(AdminSurface.primaryText).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if index < applicationAnswerRows.count - 1 { Divider().overlay(AdminSurface.hairline) }
            }
        }
        .padding(16)
        .background(AdminSurface.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.primary.opacity(0.18), lineWidth: 0.8))
    }

    private var applicationAnswerRows: [(String, String)] {
        let record = currentRecord
        func dictionary(_ value: Any?) -> [String: Any] {
            value as? [String: Any] ?? (value as? NSDictionary) as? [String: Any] ?? [:]
        }
        func dictionaries(_ value: Any?) -> [[String: Any]] {
            value as? [[String: Any]] ?? (value as? [NSDictionary])?.compactMap { $0 as? [String: Any] } ?? []
        }
        var rows: [(String, String)] = []
        let standard = dictionary(record.value("answers"))
        let standardLabels: [(String, String, String)] = [
            ("householdType", "Community_Admin_Application_HouseholdType", "نوع السكن"),
            ("householdMembers", "Community_Admin_Application_HouseholdMembers", "أفراد المنزل"),
            ("children", "Community_Admin_Application_Children", "الأطفال"),
            ("existingPets", "Community_Admin_Application_ExistingPets", "الحيوانات الحالية"),
            ("petExperience", "Community_Admin_Application_Experience", "خبرة رعاية الحيوانات"),
            ("housingPermission", "Community_Admin_Application_HousingPermission", "موافقة السكن"),
            ("dailyRoutine", "Community_Admin_Application_Routine", "الروتين اليومي"),
            ("carePlan", "Community_Admin_Application_CarePlan", "خطة الرعاية")
        ]
        for (field, key, fallback) in standardLabels {
            if let value = standard[field] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rows.append((Language.get(key, alter: fallback), value))
            }
        }
        for configured in dictionaries(record.value("questionAnswers")) {
            let preferredLabel = Language.isRTL() ? configured["labelAr"] as? String : configured["labelEn"] as? String
            let fallbackLabel = Language.isRTL() ? configured["labelEn"] as? String : configured["labelAr"] as? String
            let label = [preferredLabel, fallbackLabel, configured["questionId"] as? String].compactMap { $0 }.first { !$0.isEmpty } ?? ""
            let selectedOptions = dictionaries(configured["selectedOptions"])
            let optionLabels = selectedOptions.compactMap { option -> String? in
                let preferred = Language.isRTL() ? option["labelAr"] as? String : option["labelEn"] as? String
                let fallback = Language.isRTL() ? option["labelEn"] as? String : option["labelAr"] as? String
                return [preferred, fallback, option["id"] as? String].compactMap { $0 }.first { !$0.isEmpty }
            }
            let value: String
            if !optionLabels.isEmpty {
                value = optionLabels.joined(separator: " · ")
            } else if let text = configured["answer"] as? String {
                value = text == "yes" ? Language.get("Yes", alter: "نعم") : text == "no" ? Language.get("No", alter: "لا") : text
            } else if let values = configured["answer"] as? [String] {
                value = values.joined(separator: " · ")
            } else {
                value = ""
            }
            if !label.isEmpty, !value.isEmpty { rows.append((label, value)) }
        }
        return rows
    }

    private var dossierLoadingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(AdminSurface.primary)
            VStack(alignment: .leading, spacing: 3) {
                Text(Language.get("Community_Admin_Dossier_Loading", alter: "جارٍ تحميل الأدلة المرتبطة…"))
                    .font(AdminType.calloutBold)
                    .foregroundStyle(AdminSurface.primaryText)
                Text(Language.get("Community_Admin_Dossier_Loading_Hint", alter: "يطلب التطبيق ملفًا خادميًا محدودًا ومحميًا بالصلاحيات."))
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(AdminSurface.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.primary.opacity(0.18), lineWidth: 0.8))
        .accessibilityElement(children: .combine)
    }

    private func dossierErrorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(Language.get("Community_Admin_Dossier_Unavailable", alter: "تعذر تحميل الأدلة المرتبطة"), systemImage: "exclamationmark.triangle.fill")
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.crimson)
            Text(message)
                .font(AdminType.callout)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                store.loadDossier(currentRecord)
            } label: {
                Label(Language.get("Community_Admin_Dossier_Retry", alter: "إعادة المحاولة"), systemImage: "arrow.clockwise")
                    .font(AdminType.captionBold)
                    .foregroundStyle(AdminSurface.primary)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(AdminSurface.crimson.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.crimson.opacity(0.2), lineWidth: 0.8))
    }

    private var dossierEvidence: some View {
        ForEach(store.dossierSections) { section in
            VStack(alignment: .leading, spacing: 12) {
                Label(Language.get(section.titleKey, alter: section.fallbackTitle), systemImage: section.symbol)
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                ForEach(Array(section.evidence.enumerated()), id: \.element.id) { index, evidence in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(evidence.title)
                            .font(AdminType.calloutBold)
                            .foregroundStyle(AdminSurface.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if !evidence.subtitle.isEmpty, evidence.subtitle != evidence.title {
                            Text(evidence.subtitle)
                                .font(AdminType.caption)
                                .foregroundStyle(AdminSurface.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        HStack(spacing: 8) {
                            if !evidence.status.isEmpty {
                                AdminCommunityStatusBadge(status: evidence.status, compact: true)
                            }
                            if !evidence.timestampText.isEmpty {
                                Label(evidence.timestampText, systemImage: "clock")
                                    .font(AdminType.caption)
                                    .foregroundStyle(AdminSurface.secondaryText)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    if index < section.evidence.count - 1 { Divider().overlay(AdminSurface.hairline) }
                }
            }
            .padding(16)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
        }
    }

    private func locationCard(_ coordinate: CLLocationCoordinate2D) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label(
                    store.includePreciseLocation
                        ? Language.get("Community_Admin_Precise_On", alter: "الموقع الدقيق ظاهر")
                        : Language.get("Community_Admin_Map_Approximate_Badge", alter: "مواقع عامة تقريبية"),
                    systemImage: store.includePreciseLocation ? "location.fill" : "lock.fill"
                )
                .font(AdminType.headline)
                .foregroundStyle(store.includePreciseLocation ? AdminSurface.crimson : AdminSurface.primaryText)
                Spacer()
                if store.includePreciseLocation {
                    Text(Language.get("Community_Admin_Audited", alter: "قراءة مدققة"))
                        .font(AdminType.captionBold)
                        .foregroundStyle(AdminSurface.crimson)
                }
            }
            Text("\(coordinate.latitude.formatted(.number.precision(.fractionLength(store.includePreciseLocation ? 5 : 2)))), \(coordinate.longitude.formatted(.number.precision(.fractionLength(store.includePreciseLocation ? 5 : 2))))")
                .font(AdminType.callout.monospaced())
                .foregroundStyle(AdminSurface.secondaryText)
                .textSelection(.enabled)
        }
        .padding(16)
        .background((store.includePreciseLocation ? AdminSurface.crimson : AdminSurface.primary).opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke((store.includePreciseLocation ? AdminSurface.crimson : AdminSurface.primary).opacity(0.2), lineWidth: 0.8))
    }

    private func privateDataCard(_ privateData: [String: Any]) -> some View {
        let fields = CommunityAdminValueFormatter.privateFields(privateData)
        return VStack(alignment: .leading, spacing: 11) {
            Label(Language.get("Community_Admin_Private_Verification", alter: "بيانات تحقق خاصة"), systemImage: "lock.open.fill")
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.crimson)
            Text(Language.get("Community_Admin_Private_Verification_Hint", alter: "ظهرت بصلاحية صريحة، وسجّل الخادم عملية الوصول."))
                .font(AdminType.caption)
                .foregroundStyle(AdminSurface.secondaryText)
            ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                HStack(alignment: .top) {
                    Text(field.0).font(AdminType.caption).foregroundStyle(AdminSurface.secondaryText)
                    Spacer()
                    Text(field.1).font(AdminType.calloutBold).foregroundStyle(AdminSurface.primaryText).textSelection(.enabled)
                }
            }
        }
        .padding(16)
        .background(AdminSurface.crimson.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.crimson.opacity(0.2), lineWidth: 0.8))
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(Language.get("Community_Admin_Actions", alter: "قرارات متاحة"), systemImage: "checkmark.shield.fill")
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)
            Text(Language.get("Community_Admin_Actions_Hint", alter: "كل قرار يحتاج سببًا، إصدارًا حديثًا، وصلاحية خادمية؛ ثم يُكتب في سجل التدقيق."))
                .font(AdminType.caption)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 9)], spacing: 9) {
                ForEach(actions) { action in
                    Button {
                        intent = action
                    } label: {
                        Label(Language.get(action.titleKey, alter: action.fallbackTitle), systemImage: action.symbol)
                            .font(AdminType.captionBold)
                            .foregroundStyle(actionForeground(action.tone))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(actionBackground(action.tone), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isMutating)
                }
            }
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
    }

    private var oversightNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.2.badge.gearshape.fill")
                .foregroundStyle(AdminSurface.primary)
            Text(Language.get("Community_Admin_Application_Oversight", alter: "هذه شاشة إشراف فقط. اختيار المتبني وتحديث مسار الطلب يتمان بواسطة صاحب الإعلان أو المنظمة المخولة، وليس نيابةً عنهما من الإدارة."))
                .font(AdminType.callout)
                .foregroundStyle(AdminSurface.secondaryText)
        }
        .padding(16)
        .background(AdminSurface.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func actionForeground(_ tone: CommunityAdminActionDescriptor.Tone) -> Color {
        switch tone {
        case .normal: return AdminSurface.primary
        case .warning: return AdminSurface.amber
        case .destructive: return AdminSurface.crimson
        }
    }

    private func actionBackground(_ tone: CommunityAdminActionDescriptor.Tone) -> Color {
        actionForeground(tone).opacity(0.1)
    }
}

private struct AdminCommunityActionConfirmationView: View {
    let record: CommunityAdminRecord
    let action: CommunityAdminActionDescriptor
    @ObservedObject var store: AdminCommunityWorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var canonicalCaseID = ""

    private var canSubmit: Bool {
        reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 &&
            (!action.requiresCanonicalCase || (
                !canonicalCaseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                canonicalCaseID.trimmingCharacters(in: .whitespacesAndNewlines) != record.id
            )) && !store.isMutating
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: action.symbol)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(tint)
                            .frame(width: 46, height: 46)
                            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Language.get(action.titleKey, alter: action.fallbackTitle))
                                .font(AdminType.title3)
                                .foregroundStyle(AdminSurface.primaryText)
                            Text(record.title)
                                .font(AdminType.callout)
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text(Language.get("Community_Admin_Action_Reason", alter: "سبب القرار"))
                            .font(AdminType.captionBold)
                            .foregroundStyle(AdminSurface.secondaryText)
                        TextEditor(text: $reason)
                            .font(AdminType.body)
                            .frame(minHeight: 120)
                            .padding(10)
                            .scrollContentBackground(.hidden)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
                            .accessibilityLabel(Language.get("Community_Admin_Action_Reason", alter: "سبب القرار"))
                        Text(Language.get("Community_Admin_Action_Reason_Hint", alter: "اكتب مبررًا مهنيًا واضحًا؛ سيظهر في سجل التدقيق وقد يُستخدم في إشعار صاحب السجل."))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }

                    if action.requiresCanonicalCase {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(Language.get("Community_Admin_Action_CanonicalCase", alter: "معرّف الحالة الأساسية"))
                                .font(AdminType.captionBold)
                                .foregroundStyle(AdminSurface.secondaryText)
                            TextField(Language.get("Community_Admin_Action_CanonicalCase_Placeholder", alter: "ألصق معرّف حالة مختلفة ومعتمدة"), text: $canonicalCaseID)
                                .font(AdminType.callout.monospaced())
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 48)
                                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(AdminSurface.emerald)
                        Text(Language.get("Community_Admin_Action_Server_Hint", alter: "سيتحقق الخادم من الجلسة والحالة والصلاحية والإصدار، ثم ينفذ القرار مرة واحدة فقط ويكتب سجل التدقيق."))
                            .font(AdminType.caption)
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    .padding(13)
                    .background(AdminSurface.emerald.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        Task {
                            let succeeded = await store.perform(
                                record: record,
                                action: action.action,
                                reason: reason,
                                duplicateOfID: canonicalCaseID
                            )
                            if succeeded { dismiss() }
                        }
                    } label: {
                        HStack(spacing: 9) {
                            if store.isMutating { ProgressView().tint(.white) }
                            Text(Language.get("Community_Admin_Action_Confirm", alter: "تأكيد وتنفيذ"))
                                .font(AdminType.calloutBold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(canSubmit ? tint : AdminSurface.secondaryText.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(!canSubmit)
                }
                .padding(16)
            }
            .background(AdminSurface.background)
            .navigationTitle(Language.get("Community_Admin_Action_Review", alter: "مراجعة القرار"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Language.get("Cancel", alter: "إلغاء")) { dismiss() }
                        .disabled(store.isMutating)
                }
            }
        }
        .interactiveDismissDisabled(store.isMutating)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }

    private var tint: Color {
        switch action.tone {
        case .normal: return AdminSurface.primary
        case .warning: return AdminSurface.amber
        case .destructive: return AdminSurface.crimson
        }
    }
}

// MARK: - Shared presentation primitives

private struct AdminCommunitySectionHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    var accentColor: Color = AdminSurface.primary

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(0.18), accentColor.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accentColor.opacity(0.25), lineWidth: 0.8)
                    .frame(width: 44, height: 44)
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(accentColor)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(PPBrandFont.bold(size: 19))
                    .foregroundStyle(AdminSurface.primaryText)
                Text(subtitle)
                    .font(PPBrandFont.regular(size: 13.5))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
        .accessibilityElement(children: .combine)
    }
}

private struct AdminCommunityStatusBadge: View {
    let status: String
    var compact = false

    private var color: Color {
        switch status.lowercased() {
        case "active", "published", "approved", "verified", "resolved", "reunited", "full": return AdminSurface.emerald
        case "pending", "pending_review", "needs_information", "needs_changes", "acknowledged", "manual_review": return AdminSurface.amber
        case "rejected", "removed", "invalid", "suspended", "revoked", "dead_letter", "failed": return AdminSurface.crimson
        case "escalated", "high", "likely_match", "possible_match": return .purple
        default: return AdminSurface.primary
        }
    }

    var body: some View {
        Text(CommunityAdminLocalization.state(status))
            .font(compact ? PPBrandFont.bold(size: 10.5) : PPBrandFont.bold(size: 12))
            .foregroundStyle(color)
            .padding(.horizontal, compact ? 8 : 10)
            .frame(minHeight: compact ? 24 : 28)
            .background(color.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 0.7))
            .accessibilityLabel(
                String(
                    format: Language.get("Community_Admin_Status_Format", alter: "الحالة: %@"),
                    CommunityAdminLocalization.state(status)
                )
            )
    }
}

private struct AdminCommunityErrorBanner: View {
    let message: String
    let dismiss: () -> Void
    let retry: (() -> Void)?

    private var displayMessage: String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("INTERNAL") == .orderedSame ||
           trimmed.localizedCaseInsensitiveContains("internal") ||
           trimmed.contains("FIRFunctionsErrorDomain") {
            return Language.get("Community_Admin_Error_ServerSync", alter: "تعذرت المزامنة مع الخادم مؤقتاً. يجري تجهيز البيانات.")
        }
        if trimmed.caseInsensitiveCompare("UNAVAILABLE") == .orderedSame ||
           trimmed.localizedCaseInsensitiveContains("unavailable") {
            return Language.get("Community_Admin_Error_Unavailable", alter: "الخدمة غير متوفرة حالياً. يرجى المحاولة بعد قليل.")
        }
        return trimmed.isEmpty ? Language.get("Community_Admin_Error_Generic", alter: "حدث خطأ غير متوقع. أعد المحاولة.") : trimmed
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AdminSurface.crimson)
            Text(displayMessage)
                .font(AdminType.captionBold)
                .foregroundStyle(AdminSurface.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let retry {
                Button(Language.get("Retry", alter: "إعادة المحاولة"), action: retry)
                    .font(AdminType.captionBold)
            }
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
            }
            .accessibilityLabel(Language.get("Dismiss", alter: "إغلاق"))
        }
        .padding(13)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(AdminSurface.crimson.opacity(0.3), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

private struct AdminCommunityEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var accentColor: Color = AdminSurface.primary
    var resetAction: (() -> Void)? = nil
    let action: () -> Void

    init(
        symbol: String,
        title: String,
        body message: String,
        accentColor: Color = AdminSurface.primary,
        resetAction: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.accentColor = accentColor
        self.resetAction = resetAction
        self.action = action
    }

    init(
        symbol: String,
        title: String,
        message: String,
        accentColor: Color = AdminSurface.primary,
        resetAction: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) {
        self.init(symbol: symbol, title: title, body: message, accentColor: accentColor, resetAction: resetAction, action: action)
    }

    var body: some View {
        VStack(spacing: 20) {
            // Concentric Pulsing Aura & 3D-styled Emblem
            ZStack {
                Circle()
                    .stroke(accentColor.opacity(0.10), lineWidth: 1.5)
                    .frame(width: 104, height: 104)
                Circle()
                    .stroke(accentColor.opacity(0.18), lineWidth: 1.5)
                    .frame(width: 84, height: 84)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accentColor.opacity(0.20), accentColor.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 66, height: 66)
                    .shadow(color: accentColor.opacity(0.22), radius: 10, x: 0, y: 5)
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(accentColor)
            }
            .padding(.top, 8)

            VStack(spacing: 8) {
                Text(title)
                    .font(PPBrandFont.bold(size: 19))
                    .foregroundStyle(AdminSurface.primaryText)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(PPBrandFont.regular(size: 13.5))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                    .padding(.horizontal, 14)
            }

            VStack(spacing: 10) {
                if let resetAction {
                    Button(action: resetAction) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12, weight: .bold))
                            Text(Language.get("Community_Admin_Reset_Filters", alter: "إعادة ضبط المرشحات والبحث"))
                                .font(PPBrandFont.bold(size: 13))
                        }
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(accentColor.opacity(0.10), in: Capsule())
                        .overlay(Capsule().stroke(accentColor.opacity(0.25), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: action) {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold))
                        Text(Language.get("Community_Admin_LiveSync", alter: "تحديث البيانات من الخادم"))
                            .font(PPBrandFont.bold(size: 14))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 22)
                    .frame(height: 44)
                    .background(
                        LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .shadow(color: accentColor.opacity(0.25), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                Circle().fill(AdminSurface.emerald).frame(width: 6, height: 6)
                Text(Language.get("Community_Admin_ServerTruthFootnote", alter: "مزامنة لحظية مباشرة · مصدر الحقيقة الخادمي"))
                    .font(PPBrandFont.medium(size: 11))
                    .foregroundStyle(AdminSurface.secondaryText.opacity(0.8))
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .contain)
    }
}

private enum CommunityAdminLocalization {
    static func state(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return Language.get("Community_Admin_State_Unknown", alter: "غير معروف") }
        return Language.get("Community_Admin_State_\(normalized)", alter: fallbackState(normalized))
    }

    static func optionalState(_ value: String) -> String {
        value.isEmpty ? "" : state(value)
    }

    static func statuses(for lane: CommunityAdminLane) -> [String] {
        switch lane {
        case .adoptionListings: return ["pending_review", "needs_changes", "published", "paused", "applications_closed", "match_in_progress", "rejected", "archived"]
        case .adoptionApplications: return ["draft", "submitted", "under_review", "approved", "rejected", "withdrawn", "completed"]
        case .missingCases: return ["pending_review", "active", "searching", "sighting_received", "possibly_found", "reunited", "closed", "duplicate", "invalid"]
        case .foundReports: return ["pending_review", "active", "possible_match", "matched", "closed", "rejected", "withdrawn"]
        case .sightings: return ["pending", "verified", "rejected"]
        case .matches: return ["pending_review", "likely_match", "needs_information", "escalated", "rejected", "confirmed"]
        case .moderation: return ["open", "reopened", "escalated", "resolved"]
        case .media: return ["manual_review", "approved", "rejected", "processing", "failed"]
        case .organizations: return ["pending", "active", "restricted", "suspended", "revoked"]
        case .alerts: return ["open", "acknowledged", "resolved"]
        default: return []
        }
    }

    private static func fallbackState(_ value: String) -> String {
        let arabic: [String: String] = [
            "active": "نشط", "published": "منشور", "approved": "معتمد", "verified": "موثق",
            "resolved": "محلول", "reunited": "تم لمّ الشمل", "pending": "معلّق",
            "pending_review": "بانتظار المراجعة", "needs_information": "بحاجة لمعلومات",
            "needs_changes": "بحاجة لتعديلات", "acknowledged": "تم الاستلام", "manual_review": "مراجعة يدوية",
            "rejected": "مرفوض", "removed": "مزال", "invalid": "غير صالح", "suspended": "معلّق",
            "revoked": "مسحوب", "escalated": "مصعّد", "likely_match": "مطابقة مرجحة",
            "possible_match": "مطابقة محتملة", "paused": "متوقف مؤقتًا", "applications_closed": "الطلبات مغلقة",
            "match_in_progress": "مطابقة قيد التنفيذ", "archived": "مؤرشف", "draft": "مسودة",
            "submitted": "مقدم", "under_review": "قيد المراجعة", "withdrawn": "مسحوب", "completed": "مكتمل",
            "searching": "جارٍ البحث", "sighting_received": "وردت مشاهدة", "possibly_found": "ربما عُثر عليه",
            "closed": "مغلق", "duplicate": "مكرر", "matched": "تمت المطابقة", "confirmed": "مؤكد",
            "open": "مفتوح", "reopened": "أعيد فتحه", "processing": "قيد المعالجة", "failed": "متعثر",
            "restricted": "مقيد", "internal": "داخلي", "trusted_organizations": "منظمات موثوقة",
            "regional_beta": "تجربة إقليمية", "public_beta": "تجربة عامة", "full": "إطلاق كامل",
            "owner_managed": "بإدارة صاحب الإعلان", "organization_managed": "بإدارة المنظمة",
            "text": "نص قصير", "long_text": "نص مطول", "yes_no": "نعم أو لا",
            "single_choice": "اختيار واحد", "multiple_choice": "اختيارات متعددة"
        ]
        if Language.isRTL(), let result = arabic[value] { return result }
        return value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private enum CommunityAdminValueFormatter {
    static func integer(_ value: Any?) -> String {
        if let number = value as? NSNumber { return number.intValue.formatted() }
        if let number = value as? Int { return number.formatted() }
        return "0"
    }

    static func summary(_ dictionary: [String: Any]) -> String {
        dictionary
            .filter { $0.key != "id" }
            .prefix(3)
            .map { "\($0.key): \(integer($0.value))" }
            .joined(separator: " · ")
    }

    static func percentSummary(_ dictionary: [String: Any]) -> String {
        dictionary.sorted { $0.key < $1.key }.compactMap { key, value in
            guard let number = value as? NSNumber else { return nil }
            return "\(CommunityAdminLocalization.state(key)): \(number.doubleValue.formatted(.percent.precision(.fractionLength(0))))"
        }.joined(separator: " · ")
    }

    static func privateFields(_ dictionary: [String: Any]) -> [(String, String)] {
        var output: [(String, String)] = []
        func append(_ labelKey: String, _ fallback: String, _ value: Any?) {
            guard let string = value as? String, !string.isEmpty else { return }
            output.append((Language.get(labelKey, alter: fallback), string))
        }
        let contact = dictionary["contactInfo"] as? [String: Any] ?? [:]
        let address = dictionary["privateAddress"] as? [String: Any] ?? [:]
        append("Community_Admin_Field_ContactName", "جهة الاتصال", contact["contactName"])
        append("Community_Admin_Field_Email", "البريد", contact["email"])
        append("Community_Admin_Field_Phone", "الهاتف", contact["phone"])
        append("Community_Admin_Field_Address", "العنوان", address["line1"])
        append("Community_Admin_Field_Address2", "تكملة العنوان", address["line2"])
        append("Community_Admin_Field_City", "المدينة", address["city"])
        append("Community_Admin_Field_District", "المنطقة", address["district"])
        append("Community_Admin_Field_MissingMicrochip", "شريحة الحيوان المفقود", dictionary["missingMicrochipId"])
        append("Community_Admin_Field_MissingRingTag", "حلقة الحيوان المفقود", dictionary["missingRingTag"])
        append("Community_Admin_Field_FoundMicrochip", "شريحة الحيوان الموجود", dictionary["foundMicrochipId"])
        append("Community_Admin_Field_FoundRingTag", "حلقة الحيوان الموجود", dictionary["foundRingTag"])
        return output
    }
}

// MARK: - UIKit route bridge

@objc public final class AdminCommunityHostingController: UIViewController {
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private var restoreGeneration = UUID()
    private var host: UIViewController?

    public override func viewDidLoad() {
        super.viewDidLoad()
        extendedLayoutIncludesOpaqueBars = true
        edgesForExtendedLayout = .all
        view.backgroundColor = .ppBackground
        installLoadingState()
        restoreSession()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    private func installLoadingState() {
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.color = .ppPrimary
        activityIndicator.startAnimating()
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func restoreSession() {
        let generation = UUID()
        restoreGeneration = generation
        PPAdminSessionBridge.restoreCurrentSession { [weak self] snapshot, error in
            DispatchQueue.main.async {
                guard let self, self.restoreGeneration == generation else { return }
                guard let snapshot,
                      !snapshot.uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.showRestoreFailure(error)
                    return
                }
                let session = AdminSession(source: snapshot)
                guard AdminRoute.community.isAuthorized(for: session) || AdminRoute.adoptionManager.isAuthorized(for: session) else {
                    self.showRestoreFailure(AdminCommunityServiceError.permissionDenied)
                    return
                }
                self.installHost(session: session)
            }
        }
    }

    private func installHost(session: AdminSession) {
        activityIndicator.removeFromSuperview()
        let controller = UIHostingController(rootView: AdminCommunityControlCenterView(session: session) { [weak self] in
            guard let self else {
                PPAdminNavigationFallback.popOrDismiss()
                return
            }
            PPAdminNavigationFallback.popOrDismiss(from: self)
        })
        controller.view.backgroundColor = .clear
        addChild(controller)
        view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        controller.didMove(toParent: self)
        host = controller
    }

    private func showRestoreFailure(_ error: Error?) {
        activityIndicator.stopAnimating()
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .ppTextSecondary
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.text = error?.localizedDescription
            ?? Language.get("Community_Admin_Error_Unauthenticated", alter: "انتهت الجلسة. سجّل الدخول مجددًا.")
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
