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
            "pet.name", "pet.displayName", "name", "title", "organizationName",
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
        let candidates = [
            "media.0.thumbnailUrl", "media.0.previewUrl", "media.0.url",
            "pet.media.0.thumbnailUrl", "pet.media.0.url", "logo.thumbnailUrl", "logo.url"
        ]
        for path in candidates {
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

    private func codeList(_ text: String, max: Int, uppercased: Bool = true) -> [String] {
        var seen = Set<String>()
        return text
            .components(separatedBy: CharacterSet(charactersIn: ",\n;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { uppercased ? $0.uppercased() : $0 }
            .filter { seen.insert($0).inserted }
            .prefix(max)
            .map(String.init)
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
            return message
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
        includePrivateOrganization: Bool = false
    ) async throws -> [String: Any] {
        var payload: [String: Any] = ["action": action, "limit": max(1, min(200, limit))]
        if !status.isEmpty { payload["status"] = status }
        if let cursor, !cursor.isEmpty { payload["cursor"] = cursor }
        if !ownerUID.isEmpty { payload["ownerUid"] = ownerUID }
        if includePreciseLocation { payload["includePreciseLocation"] = true }
        if includePrivateOrganization { payload["includePrivateOrganization"] = true }
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

    func updateConfiguration(_ draft: CommunityConfigurationDraft) async throws -> [String: Any] {
        try await mutation(
            name: "communityConfigurationCommand",
            action: "save",
            payload: ["expectedVersion": draft.version, "configuration": draft.payload()]
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
            if response["ok"] as? Bool == false {
                throw AdminCommunityServiceError.server(
                    response["message"] as? String
                        ?? Language.get("Community_Admin_Error_Command", alter: "تعذر تنفيذ أمر المجتمع.")
                )
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
    @Published private(set) var overview: [String: Int] = [:]
    @Published private(set) var attentionRecords: [CommunityAdminRecord] = []
    @Published private(set) var diagnostics: [String: Any] = [:]
    @Published private(set) var analytics: [String: Any] = [:]
    @Published private(set) var operationsMapEnabled = false
    @Published var configuration = CommunityConfigurationDraft()
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isMutating = false
    @Published private(set) var hasMore = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var successMessage: String?
    @Published var statusFilter = ""
    @Published var searchText = ""
    @Published var includePreciseLocation = false
    @Published var includePrivateOrganization = false

    let session: AdminSession
    private let service: AdminCommunityService
    private var nextCursor: String?
    private var loadGeneration = UUID()

    init(session: AdminSession, service: AdminCommunityService = .shared) {
        self.session = session
        self.service = service
    }

    var availableLanes: [CommunityAdminLane] {
        CommunityAdminLane.allCases.filter { lane in
            canAccess(lane) && (lane != .operationsMap || operationsMapEnabled)
        }
    }

    func canAccess(_ lane: CommunityAdminLane) -> Bool {
        session.hasPermission(lane.permission) && session.hasGlobalScope
    }

    var canViewPreciseLocation: Bool {
        session.hasPermission("community.location.precise") && session.hasGlobalScope
    }

    var canResolveModeration: Bool {
        session.hasPermission("community.moderation.resolve") && session.hasGlobalScope
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
        includePreciseLocation = enabled
        await load(reset: true)
    }

    func setPrivateOrganization(_ enabled: Bool) async {
        guard session.hasPermission("community.organization.verify"), session.hasGlobalScope else {
            includePrivateOrganization = false
            errorMessage = AdminCommunityServiceError.permissionDenied.localizedDescription
            return
        }
        includePrivateOrganization = enabled
        await load(reset: true)
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
            await load(reset: true)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
    }

    func saveConfiguration() async -> Bool {
        if let validationError = configuration.validationError() {
            errorMessage = validationError
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
        isMutating = true
        errorMessage = nil
        successMessage = nil
        defer { isMutating = false }
        do {
            _ = try await service.updateConfiguration(configuration)
            successMessage = Language.get("Community_Admin_Config_Saved", alter: "حُفظت إعدادات المجتمع بأمان.")
            await load(reset: true)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return false
        }
    }

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
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
                    includePrivateOrganization: includePrivateOrganization
                )
                guard generation == loadGeneration else { return }
                let page = Self.recordArray(response["items"], source: selectedLane)
                records = reset ? page : Self.deduplicated(records + page)
                nextCursor = response["nextCursor"] as? String
                hasMore = (response["hasMore"] as? Bool) == true && nextCursor != nil
            }
        } catch {
            guard generation == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func loadOperationsMap(generation: UUID) async throws {
        let precise = includePreciseLocation && canViewPreciseLocation
        let sightingsAllowed = canAccess(.sightings)
        let missing = try await service.read(action: "missing_cases", limit: 200, includePreciseLocation: precise)
        let found = try await service.read(action: "found_reports", limit: 200, includePreciseLocation: precise)
        var all = Self.recordArray(missing["items"], source: .missingCases)
            + Self.recordArray(found["items"], source: .foundReports)
        if sightingsAllowed {
            let sightings = try await service.read(action: "sightings", limit: 200, includePreciseLocation: precise)
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
        case .adoptionListings where session.hasPermission("community.adoption.moderate"):
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
                    .init("remove", "Community_Admin_Action_Remove", "إزالة المحتوى", symbol: "trash.fill", tone: .destructive),
                    .init("suspend_owner", "Community_Admin_Action_SuspendOwner", "تعليق صاحب المحتوى", symbol: "person.crop.circle.badge.xmark", tone: .destructive)
                ]
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

    init(session: AdminSession, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        _store = StateObject(wrappedValue: AdminCommunityWorkspaceStore(session: session))
    }

    private var isWide: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass != .compact
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(AdminSurface.hairline)
            if isWide {
                HStack(spacing: 0) {
                    laneSidebar
                        .frame(width: 246)
                    Divider().overlay(AdminSurface.hairline)
                    workspace
                }
            } else {
                laneRail
                Divider().overlay(AdminSurface.hairline)
                workspace
            }
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .task { await store.start() }
        .sheet(item: $store.selectedRecord) { record in
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

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: onDismiss) {
                Image(systemName: Language.isRTL() ? "chevron.right" : "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AdminSurface.primaryText)
                    .frame(width: 42, height: 42)
                    .background(AdminSurface.control, in: Circle())
                    .overlay(Circle().stroke(AdminSurface.hairline, lineWidth: 0.8))
            }
            .accessibilityLabel(Language.get("Back", alter: "رجوع"))

            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(AdminSurface.primary.opacity(0.13))
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AdminSurface.primary)
            }
            .frame(width: 42, height: 42)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(Language.get("Community_Admin_Title", alter: "مركز عمليات المجتمع"))
                    .font(AdminType.title3)
                    .foregroundStyle(AdminSurface.primaryText)
                Text(Language.get("Community_Admin_Subtitle", alter: "التبني · المفقودات · الثقة والسلامة"))
                    .font(AdminType.caption)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if store.isMutating {
                ProgressView()
                    .tint(AdminSurface.primary)
                    .accessibilityLabel(Language.get("Community_Admin_Working", alter: "جارٍ تنفيذ العملية"))
            }

            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AdminSurface.primaryText)
                    .frame(width: 42, height: 42)
                    .background(AdminSurface.control, in: Circle())
                    .overlay(Circle().stroke(AdminSurface.hairline, lineWidth: 0.8))
            }
            .disabled(store.isLoading || store.isMutating)
            .accessibilityLabel(Language.get("Refresh", alter: "تحديث"))
        }
        .padding(.horizontal, isWide ? 24 : 16)
        .padding(.vertical, 12)
        .background(AdminSurface.surface)
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
        .background(AdminSurface.surface)
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

    private func laneButton(_ lane: CommunityAdminLane, compact: Bool) -> some View {
        let selected = store.selectedLane == lane
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) {
                store.select(lane)
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: lane.symbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(Language.get(lane.titleKey, alter: lane.fallbackTitle))
                    .font(selected ? AdminType.captionBold : AdminType.caption)
                    .lineLimit(1)
                if !compact { Spacer(minLength: 0) }
            }
            .foregroundStyle(selected ? Color.white : AdminSurface.secondaryText)
            .padding(.horizontal, compact ? 13 : 12)
            .frame(minHeight: 38)
            .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
            .background(selected ? AdminSurface.primary : AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? Color.clear : AdminSurface.hairline, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var workspace: some View {
        ZStack {
            AdminSurface.background
            if store.isLoading {
                VStack(spacing: 12) {
                    ProgressView().tint(AdminSurface.primary)
                    Text(Language.get("Community_Admin_Loading", alter: "جارٍ تحميل بيانات المجتمع الآمنة…"))
                        .font(AdminType.callout)
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .accessibilityElement(children: .combine)
            } else {
                switch store.selectedLane {
                case .overview:
                    AdminCommunityOverviewView(store: store)
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

// MARK: - Overview

private struct AdminCommunityOverviewView: View {
    @ObservedObject var store: AdminCommunityWorkspaceStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private struct Metric: Identifiable {
        let id: String
        let titleKey: String
        let fallback: String
        let symbol: String
        let color: Color
    }

    private let metrics: [Metric] = [
        .init(id: "activeAdoptions", titleKey: "Community_Admin_Metric_ActiveAdoptions", fallback: "إعلانات تبني نشطة", symbol: "heart.fill", color: .pink),
        .init(id: "activeMissing", titleKey: "Community_Admin_Metric_ActiveMissing", fallback: "حالات فقدان نشطة", symbol: "magnifyingglass", color: .orange),
        .init(id: "reunited", titleKey: "Community_Admin_Metric_Reunited", fallback: "تم لمّ شملها هذا الشهر", symbol: "house.and.flag.fill", color: .green),
        .init(id: "activeFoundReports", titleKey: "Community_Admin_Metric_Found", fallback: "بلاغات عثور نشطة", symbol: "hand.raised.fill", color: .teal),
        .init(id: "pendingMatches", titleKey: "Community_Admin_Metric_Matches", fallback: "مطابقات تنتظر المراجعة", symbol: "sparkles", color: .indigo),
        .init(id: "pendingModeration", titleKey: "Community_Admin_Metric_Moderation", fallback: "حالات رقابة معلّقة", symbol: "shield.lefthalf.filled", color: .purple),
        .init(id: "pendingOrganizations", titleKey: "Community_Admin_Metric_Organizations", fallback: "منظمات تنتظر التوثيق", symbol: "building.2.fill", color: .blue),
        .init(id: "highRiskReports", titleKey: "Community_Admin_Metric_HighRisk", fallback: "بلاغات عالية الخطورة", symbol: "exclamationmark.shield.fill", color: .red)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                AdminCommunitySectionHeader(
                    title: Language.get("Community_Admin_Overview_Title", alter: "نبض المجتمع الآن"),
                    subtitle: Language.get("Community_Admin_Overview_Subtitle", alter: "مؤشرات تشغيلية مباشرة من الخادم، دون قراءات عميل غير موثوقة."),
                    symbol: "waveform.path.ecg"
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 190 : 148), spacing: 12)], spacing: 12) {
                    ForEach(metrics) { metric in
                        metricCard(metric)
                    }
                }

                if !store.diagnostics.isEmpty {
                    diagnosticsPanel
                }

                attentionPanel

                privacyPanel
            }
            .padding(horizontalSizeClass == .regular ? 24 : 16)
            .padding(.vertical, 20)
        }
        .refreshable { await store.refresh() }
    }

    private func metricCard(_ metric: Metric) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: metric.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(metric.color)
                    .frame(width: 34, height: 34)
                    .background(metric.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
                Text(store.overview[metric.id, default: 0].formatted())
                    .font(AdminType.title2.monospacedDigit())
                    .foregroundStyle(AdminSurface.primaryText)
            }
            Text(Language.get(metric.titleKey, alter: metric.fallback))
                .font(AdminType.captionBold)
                .foregroundStyle(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
        .accessibilityElement(children: .combine)
    }

    private var diagnosticsPanel: some View {
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

    private var attentionPanel: some View {
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
                            Button { store.selectedRecord = record } label: {
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

    private var privacyPanel: some View {
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

// MARK: - Queue

private struct AdminCommunityQueueView: View {
    @ObservedObject var store: AdminCommunityWorkspaceStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                AdminCommunitySectionHeader(
                    title: Language.get(store.selectedLane.titleKey, alter: store.selectedLane.fallbackTitle),
                    subtitle: subtitle,
                    symbol: store.selectedLane.symbol
                )
                filters

                if store.filteredRecords.isEmpty {
                    AdminCommunityEmptyState(
                        symbol: store.selectedLane.symbol,
                        title: Language.get("Community_Admin_Empty_Title", alter: "لا توجد عناصر في هذه القائمة"),
                        body: Language.get("Community_Admin_Empty_Body", alter: "غيّر المرشحات أو حدّث القائمة. لا توجد بيانات تجريبية أو عناصر وهمية."),
                        action: { Task { await store.refresh() } }
                    )
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 300 : 280), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(store.filteredRecords) { record in
                            AdminCommunityRecordCard(record: record) {
                                store.selectedRecord = record
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
                                .font(AdminType.calloutBold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
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
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AdminSurface.secondaryText)
                TextField(Language.get("Community_Admin_Search", alter: "بحث داخل الصفحة المحمّلة"), text: $store.searchText)
                    .font(AdminType.callout)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                if !store.searchText.isEmpty {
                    Button { store.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(AdminSurface.secondaryText)
                    }
                    .accessibilityLabel(Language.get("Clear", alter: "مسح"))
                }
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 46)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))

            HStack(spacing: 10) {
                if store.selectedLane.supportsStatusFilter {
                    Menu {
                        Button(Language.get("Community_Admin_Status_All", alter: "كل الحالات")) {
                            store.statusFilter = ""
                            Task { await store.applyFilters() }
                        }
                        ForEach(CommunityAdminLocalization.statuses(for: store.selectedLane), id: \.self) { status in
                            Button(CommunityAdminLocalization.state(status)) {
                                store.statusFilter = status
                                Task { await store.applyFilters() }
                            }
                        }
                    } label: {
                        filterChip(
                            title: store.statusFilter.isEmpty
                                ? Language.get("Community_Admin_Status_All", alter: "كل الحالات")
                                : CommunityAdminLocalization.state(store.statusFilter),
                            symbol: "line.3.horizontal.decrease.circle"
                        )
                    }
                }

                if [.missingCases, .foundReports, .sightings].contains(store.selectedLane), store.canViewPreciseLocation {
                    Button {
                        Task { await store.setPreciseLocation(!store.includePreciseLocation) }
                    } label: {
                        filterChip(
                            title: store.includePreciseLocation
                                ? Language.get("Community_Admin_Precise_On", alter: "الموقع الدقيق ظاهر")
                                : Language.get("Community_Admin_Precise_Off", alter: "إظهار الموقع الدقيق"),
                            symbol: store.includePreciseLocation ? "location.fill" : "location.slash"
                        )
                    }
                    .accessibilityHint(Language.get("Community_Admin_Precise_Audit_Hint", alter: "تُسجل هذه القراءة في سجل التدقيق"))
                }

                if store.selectedLane == .organizations,
                   store.session.hasPermission("community.organization.verify") {
                    Button {
                        Task { await store.setPrivateOrganization(!store.includePrivateOrganization) }
                    } label: {
                        filterChip(
                            title: store.includePrivateOrganization
                                ? Language.get("Community_Admin_Private_On", alter: "البيانات الخاصة ظاهرة")
                                : Language.get("Community_Admin_Private_Off", alter: "إظهار بيانات التحقق"),
                            symbol: store.includePrivateOrganization ? "lock.open.fill" : "lock.fill"
                        )
                    }
                    .accessibilityHint(Language.get("Community_Admin_Precise_Audit_Hint", alter: "تُسجل هذه القراءة في سجل التدقيق"))
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func filterChip(title: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
            Text(title).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
        }
        .font(AdminType.captionBold)
        .foregroundStyle(AdminSurface.primaryText)
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
        .background(AdminSurface.control, in: Capsule())
        .overlay(Capsule().stroke(AdminSurface.hairline, lineWidth: 0.8))
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
                            .font(AdminType.headline)
                            .foregroundStyle(AdminSurface.primaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(record.subtitle)
                            .font(AdminType.caption)
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
                            .font(AdminType.caption2)
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
                            .font(AdminType.captionBold)
                            .foregroundStyle(AdminSurface.primary)
                    }
                    Spacer(minLength: 0)
                    Text("v\(record.version)")
                        .font(AdminType.caption2.monospaced())
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 156, alignment: .leading)
            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
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
            .font(AdminType.captionBold)
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
                                if cluster.records.count == 1 { store.selectedRecord = cluster.records[0] }
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
        .sheet(item: $selectedRecord) { record in
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
                Task { _ = await store.saveConfiguration() }
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
}

// MARK: - Record dossier and mutation confirmation

private struct AdminCommunityRecordDetailView: View {
    let record: CommunityAdminRecord
    @ObservedObject var store: AdminCommunityWorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var intent: CommunityAdminActionDescriptor?

    private var actions: [CommunityAdminActionDescriptor] {
        guard store.session.hasGlobalScope else { return [] }
        return CommunityAdminActionPolicy.actions(for: record, session: store.session)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    identityCard
                    lifecycleCard
                    domainFacts
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

    private var identityCard: some View {
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

    private var dossierPlaceholder: some View {
        ZStack {
            AdminSurface.primary.opacity(0.1)
            Image(systemName: record.source.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(AdminSurface.primary)
        }
    }

    private var lifecycleCard: some View {
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

    private var detailFacts: [(String, String)] {
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AdminSurface.primary)
                .frame(width: 40, height: 40)
                .background(AdminSurface.primary.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AdminType.title3)
                    .foregroundStyle(AdminSurface.primaryText)
                Text(subtitle)
                    .font(AdminType.callout)
                    .foregroundStyle(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
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
            .font(compact ? AdminType.caption2Bold : AdminType.captionBold)
            .foregroundStyle(color)
            .padding(.horizontal, compact ? 8 : 10)
            .frame(minHeight: compact ? 24 : 28)
            .background(color.opacity(0.11), in: Capsule())
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AdminSurface.crimson)
            Text(message)
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
    let body: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(AdminSurface.primary)
                .frame(width: 64, height: 64)
                .background(AdminSurface.primary.opacity(0.1), in: Circle())
            Text(title)
                .font(AdminType.headline)
                .foregroundStyle(AdminSurface.primaryText)
                .multilineTextAlignment(.center)
            Text(body)
                .font(AdminType.callout)
                .foregroundStyle(AdminSurface.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(Language.get("Refresh", alter: "تحديث"), action: action)
                .font(AdminType.calloutBold)
                .buttonStyle(.borderedProminent)
                .tint(AdminSurface.primary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AdminSurface.hairline, lineWidth: 0.8))
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
                guard AdminRoute.community.isAuthorized(for: session) else {
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
