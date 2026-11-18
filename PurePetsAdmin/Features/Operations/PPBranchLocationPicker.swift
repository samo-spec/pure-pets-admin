//
//  PPBranchLocationPicker.swift
//  PurePetsAdmin
//
//  NextGen V10 Category-Defining Spatial Location & Delivery Pickup Surface.
//  Engineered from first principles for pinpoint spatial precision:
//  - Interactive 60/120fps MapKit camera with physics-based living beacon & radar pulse.
//  - Real-time debounced reverse geocoding (CLGeocoder) with bilingual street & zone resolution.
//  - Live coordinate telemetry HUD with 6-decimal-place monospace precision and 1-tap copy.
//  - Instant Qatar Commercial Logistics Hub quick-teleport chips (Doha Flagship, Pearl, Lusail, etc.).
//  - Smart MKLocalSearch bar with instant place and street autocompletion.
//  - Verified Courier Pickup & Routing Reassurance contract for fulfillment dispatches.
//  - Full bidirectional Arabic RTL / English LTR support with Beiruti typography & haptic feedback.
//

import SwiftUI
@preconcurrency import MapKit
import CoreLocation

// MARK: - Qatar Logistics Hub Presets

public struct QatarHubPreset: Identifiable, Hashable, @unchecked Sendable {
    public let id: String
    public let nameAr: String
    public let nameEn: String
    public let coordinate: CLLocationCoordinate2D
    public let icon: String

    public init(id: String, nameAr: String, nameEn: String, coordinate: CLLocationCoordinate2D, icon: String = "building.2.fill") {
        self.id = id
        self.nameAr = nameAr
        self.nameEn = nameEn
        self.coordinate = coordinate
        self.icon = icon
    }

    public var localizedName: String {
        Language.isRTL() ? nameAr : nameEn
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: QatarHubPreset, rhs: QatarHubPreset) -> Bool {
        lhs.id == rhs.id
    }

    @MainActor public static let standardHubs: [QatarHubPreset] = [
        QatarHubPreset(
            id: "doha_salwa",
            nameAr: "طريق سلوى - الفرع الرئيسي",
            nameEn: "Salwa Road - Flagship",
            coordinate: CLLocationCoordinate2D(latitude: 25.2605, longitude: 51.4880),
            icon: "star.fill"
        ),
        QatarHubPreset(
            id: "pearl_porto",
            nameAr: "اللؤلؤة - بورتو أرابيا",
            nameEn: "The Pearl - Porto Arabia",
            coordinate: CLLocationCoordinate2D(latitude: 25.3713, longitude: 51.5499),
            icon: "water.waves"
        ),
        QatarHubPreset(
            id: "lusail_marina",
            nameAr: "لوسيل - المارينا والبروميناد",
            nameEn: "Lusail - Marina Promenade",
            coordinate: CLLocationCoordinate2D(latitude: 25.4208, longitude: 51.5284),
            icon: "building.columns.fill"
        ),
        QatarHubPreset(
            id: "al_rayyan",
            nameAr: "الريان - شارع الوعب",
            nameEn: "Al Rayyan - Al Waab",
            coordinate: CLLocationCoordinate2D(latitude: 25.2750, longitude: 51.4420),
            icon: "tram.fill"
        ),
        QatarHubPreset(
            id: "al_sadd",
            nameAr: "السد - سحيم بن حمد",
            nameEn: "Al Sadd - Suhaim Bin Hamad",
            coordinate: CLLocationCoordinate2D(latitude: 25.2854, longitude: 51.4988),
            icon: "building.2.crop.circle"
        ),
        QatarHubPreset(
            id: "al_wakrah",
            nameAr: "الوكرة - السوق القديم",
            nameEn: "Al Wakrah - Souq & Coast",
            coordinate: CLLocationCoordinate2D(latitude: 25.1768, longitude: 51.6035),
            icon: "sailboat.fill"
        ),
        QatarHubPreset(
            id: "west_bay",
            nameAr: "الخليج الغربي - الدفنة",
            nameEn: "West Bay - Al Dafna",
            coordinate: CLLocationCoordinate2D(latitude: 25.3210, longitude: 51.5310),
            icon: "skyscraper.fill"
        )
    ]
}

// MARK: - Location Picker ViewModel

@MainActor
public final class PPBranchLocationPickerViewModel: NSObject, ObservableObject {
    @Published public var currentCoordinate: CLLocationCoordinate2D
    @Published public var formattedAddress: String = ""
    @Published public var isGeocoding: Bool = false
    @Published public var isDragging: Bool = false
    @Published public var mapType: MKMapType = .standard
    @Published public var searchQuery: String = ""
    @Published public var searchResults: [MKLocalSearchCompletion] = []
    @Published public var isSearching: Bool = false
    @Published public var toastMessage: String? = nil

    private let geocoder = CLGeocoder()
    private var geocodeWorkItem: DispatchWorkItem?
    private var searchCompleter = MKLocalSearchCompleter()
    private var searchCompleterAdapter: PPAdminSearchCompleterAdapter?
    public weak var mapView: MKMapView?

    public init(initialCoordinate: CLLocationCoordinate2D?, initialAddress: String?) {
        // Default to provided coordinate or Doha central commercial district
        let fallback = CLLocationCoordinate2D(latitude: 25.2854, longitude: 51.5310)
        let resolved = initialCoordinate.flatMap {
            (abs($0.latitude) > 0.001 && abs($0.longitude) > 0.001) ? $0 : nil
        } ?? fallback

        self.currentCoordinate = resolved
        self.formattedAddress = initialAddress?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        super.init()

        let adapter = PPAdminSearchCompleterAdapter(viewModel: self)
        self.searchCompleterAdapter = adapter
        searchCompleter.delegate = adapter
        searchCompleter.resultTypes = [.address, .pointOfInterest]
        // Constrain search region roughly around Qatar
        let qatarCenter = CLLocationCoordinate2D(latitude: 25.2854, longitude: 51.5310)
        searchCompleter.region = MKCoordinateRegion(
            center: qatarCenter,
            span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)
        )

        if self.formattedAddress.isEmpty {
            performReverseGeocode(for: resolved)
        }
    }

    public func updateCenterCoordinate(_ coordinate: CLLocationCoordinate2D) {
        self.currentCoordinate = coordinate
        scheduleReverseGeocode(for: coordinate)
    }

    public func setDragging(_ dragging: Bool) {
        if self.isDragging != dragging {
            self.isDragging = dragging
            if !dragging {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
            }
        }
    }

    public func scheduleReverseGeocode(for coordinate: CLLocationCoordinate2D) {
        geocodeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.performReverseGeocode(for: coordinate)
        }
        geocodeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: item)
    }

    private func performReverseGeocode(for coordinate: CLLocationCoordinate2D) {
        isGeocoding = true
        let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let preferredLocale = Locale(identifier: Language.isRTL() ? "ar_QA" : "en_QA")

        geocoder.reverseGeocodeLocation(loc, preferredLocale: preferredLocale) { [weak self] placemarks, error in
            Task { @MainActor in
                guard let self else { return }
                self.isGeocoding = false
                if let pm = placemarks?.first {
                    var parts: [String] = []
                    if let name = pm.name, !name.isEmpty { parts.append(name) }
                    if let thoroughfare = pm.thoroughfare, !thoroughfare.isEmpty, !parts.contains(thoroughfare) {
                        parts.append(thoroughfare)
                    }
                    if let subLocality = pm.subLocality, !subLocality.isEmpty, !parts.contains(subLocality) {
                        parts.append(subLocality)
                    }
                    if let locality = pm.locality, !locality.isEmpty, !parts.contains(locality) {
                        parts.append(locality)
                    }
                    if let country = pm.country, !country.isEmpty, !parts.contains(country) {
                        parts.append(country)
                    }

                    if !parts.isEmpty {
                        self.formattedAddress = parts.joined(separator: " · ")
                    } else {
                        self.formattedAddress = String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
                    }
                }
            }
        }
    }

    public func moveToHub(_ hub: QatarHubPreset) {
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        self.currentCoordinate = hub.coordinate
        let region = MKCoordinateRegion(
            center: hub.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        )
        mapView?.setRegion(region, animated: true)
        scheduleReverseGeocode(for: hub.coordinate)
    }

    public func updateSearchQuery(_ query: String) {
        self.searchQuery = query
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.searchResults = []
            self.isSearching = false
            searchCompleter.queryFragment = ""
        } else {
            self.isSearching = true
            searchCompleter.queryFragment = query
        }
    }

    public func selectSearchResult(_ completion: MKLocalSearchCompletion) {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            Task { @MainActor in
                guard let self, let item = response?.mapItems.first else { return }
                let haptic = UIImpactFeedbackGenerator(style: .medium)
                haptic.impactOccurred()

                let coord = item.placemark.coordinate
                self.currentCoordinate = coord
                self.searchQuery = ""
                self.searchResults = []
                self.isSearching = false

                let region = MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                )
                self.mapView?.setRegion(region, animated: true)
                self.scheduleReverseGeocode(for: coord)
            }
        }
    }

    public func toggleMapType() {
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        withAnimation(AdminAnimation.fast) {
            self.mapType = (self.mapType == .standard) ? .hybrid : .standard
        }
    }

    public func copyCoordinates() {
        let str = String(format: "%.6f, %.6f", currentCoordinate.latitude, currentCoordinate.longitude)
        UIPasteboard.general.string = str
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        showToast(Language.get("Branches_CoordsCopied", alter: "تم نسخ الإحداثيات بدقة"))
    }

    public func showToast(_ msg: String) {
        self.toastMessage = msg
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if self.toastMessage == msg {
                self.toastMessage = nil
            }
        }
    }
}

// MARK: - Search Completer Adapter (Swift 6 Safe)

private final class PPAdminSearchCompleterAdapter: NSObject, MKLocalSearchCompleterDelegate, @unchecked Sendable {
    private weak var viewModel: PPBranchLocationPickerViewModel?

    init(viewModel: PPBranchLocationPickerViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor [weak viewModel] in
            viewModel?.searchResults = results
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor [weak viewModel] in
            viewModel?.searchResults = []
        }
    }
}

// MARK: - Interactive MapView Representable

public struct PPBranchInteractiveMapView: UIViewRepresentable {
    @ObservedObject var viewModel: PPBranchLocationPickerViewModel

    public func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    public func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = true
        mapView.mapType = viewModel.mapType

        let region = MKCoordinateRegion(
            center: viewModel.currentCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        )
        mapView.setRegion(region, animated: false)

        viewModel.mapView = mapView
        return mapView
    }

    public func updateUIView(_ uiView: MKMapView, context: Context) {
        if uiView.mapType != viewModel.mapType {
            uiView.mapType = viewModel.mapType
        }
    }

    public final class Coordinator: NSObject, MKMapViewDelegate {
        let viewModel: PPBranchLocationPickerViewModel

        init(viewModel: PPBranchLocationPickerViewModel) {
            self.viewModel = viewModel
        }

        public func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            Task { @MainActor in
                self.viewModel.setDragging(true)
            }
        }

        public func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let center = mapView.centerCoordinate
            Task { @MainActor in
                self.viewModel.setDragging(false)
                self.viewModel.updateCenterCoordinate(center)
            }
        }
    }
}

// MARK: - Sovereign NextGen V10 Location Picker Surface

public struct PPBranchLocationPicker: View {
    let branchName: String?
    let initialCoordinate: CLLocationCoordinate2D?
    let initialAddress: String?
    let onConfirm: @MainActor (CLLocationCoordinate2D, String) -> Void
    let onDismiss: @MainActor () -> Void

    @StateObject private var viewModel: PPBranchLocationPickerViewModel
    @State private var radarPulse: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        branchName: String?,
        initialCoordinate: CLLocationCoordinate2D?,
        initialAddress: String?,
        onConfirm: @escaping @MainActor (CLLocationCoordinate2D, String) -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.branchName = branchName
        self.initialCoordinate = initialCoordinate
        self.initialAddress = initialAddress
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: PPBranchLocationPickerViewModel(
            initialCoordinate: initialCoordinate,
            initialAddress: initialAddress
        ))
    }

    public var body: some View {
        ZStack {
            // Level 0: The Underlying 60/120fps Map Canvas
            PPBranchInteractiveMapView(viewModel: viewModel)
                .ignoresSafeArea()

            // Level 1: Precise Living Center Beacon Pin & Animated Radar Pulse
            centerBeaconOverlay

            // Level 2: Top Floating Spatial Search Island & Layer Toggles
            VStack(spacing: 0) {
                topSpatialIsland
                if viewModel.isSearching && !viewModel.searchResults.isEmpty {
                    searchResultsDropdown
                }
                Spacer()
            }
            .padding(.top, 8)
            .padding(.horizontal, AdminSpacing.screenMargin)

            // Level 3: Bottom Tactical Pickup Intelligence & Reassurance Dock
            VStack(spacing: 0) {
                Spacer()
                bottomTacticalDock
            }
            .ignoresSafeArea(edges: .bottom)

            // Level 4: Telemetry Toast Banner
            if let toast = viewModel.toastMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AdminSurface.emerald)
                        Text(toast)
                            .font(AdminType.footnoteBold)
                            .foregroundColor(AdminSurface.primaryText)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(AdminSurface.emerald.opacity(0.3), lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    .padding(.bottom, 220)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(AdminAnimation.standard, value: viewModel.toastMessage)
                .zIndex(90)
            }
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false)) {
                    radarPulse = true
                }
            }
        }
    }

    // MARK: - Center Living Beacon Pin

    private var centerBeaconOverlay: some View {
        ZStack {
            // Radar expansion wave on the ground
            Circle()
                .stroke(AdminSurface.primary.opacity(radarPulse ? 0.0 : 0.45), lineWidth: 2)
                .frame(width: radarPulse ? 100 : 20, height: radarPulse ? 100 : 20)
                .scaleEffect(radarPulse ? 1.0 : 0.3)
                .opacity(viewModel.isDragging ? 0.2 : 1.0)

            // Pin ground shadow
            Ellipse()
                .fill(Color.black.opacity(viewModel.isDragging ? 0.18 : 0.32))
                .frame(
                    width: viewModel.isDragging ? 18 : 26,
                    height: viewModel.isDragging ? 7 : 10
                )
                .offset(y: 22)
                .blur(radius: viewModel.isDragging ? 3 : 1.5)

            // Living Spatial Beacon Pin
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AdminSurface.primary, AdminSurface.primaryPressed],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .shadow(color: AdminSurface.primary.opacity(0.4), radius: 8, y: 4)

                    Image(systemName: "box.truck.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }

                // Needle tip pointing to ground
                Triangle()
                    .fill(AdminSurface.primary)
                    .frame(width: 14, height: 10)
                    .offset(y: -2)
            }
            .offset(y: viewModel.isDragging ? -32 : -18)
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: viewModel.isDragging)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Top Spatial Island

    private var topSpatialIsland: some View {
        HStack(spacing: 10) {
            // Close Button
            Button {
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(AdminType.bodyBold)
                    .foregroundColor(AdminSurface.primaryText)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(AdminSurface.borderSubtle, lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
            }
            .buttonStyle(BranchPressStyle())

            // Search Bar Field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(AdminType.body)
                    .foregroundColor(AdminSurface.primary)

                TextField(Language.get("Branches_SearchLocation", alter: "ابحث عن موقع أو شارع أو معلم في قطر…"), text: Binding(
                    get: { viewModel.searchQuery },
                    set: { viewModel.updateSearchQuery($0) }
                ))
                .font(AdminType.body)
                .foregroundColor(AdminSurface.primaryText)
                .disableAutocorrection(true)

                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.updateSearchQuery("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AdminType.caption1)
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(AdminSurface.borderSubtle, lineWidth: 0.8))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)

            // Map Style Toggle
            Button {
                viewModel.toggleMapType()
            } label: {
                Image(systemName: viewModel.mapType == .standard ? "globe.europe.africa.fill" : "map.fill")
                    .font(AdminType.bodyBold)
                    .foregroundColor(AdminSurface.primary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(AdminSurface.borderSubtle, lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
            }
            .buttonStyle(BranchPressStyle())
        }
    }

    // MARK: - Search Results Dropdown

    private var searchResultsDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(viewModel.searchResults, id: \.self) { result in
                        Button {
                            viewModel.selectSearchResult(result)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(AdminSurface.primary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .font(AdminType.bodyBold)
                                        .foregroundColor(AdminSurface.primaryText)
                                        .lineLimit(1)

                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(AdminType.caption1)
                                            .foregroundColor(AdminSurface.secondaryText)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(BranchPressStyle())

                        Divider().padding(.horizontal, 16)
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AdminSurface.borderSubtle, lineWidth: 0.8))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        .padding(.top, 8)
    }

    // MARK: - Bottom Tactical Dock

    private var bottomTacticalDock: some View {
        VStack(spacing: 0) {
            // Quick Hubs Horizontal Teleport Matrix
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.horizontal.fill")
                        .font(AdminType.caption2Bold)
                        .foregroundColor(AdminSurface.primary)

                    Text(Language.get("Branches_QuickHubs", alter: "المراكز اللوجستية الكبرى في قطر"))
                        .font(AdminType.caption1Bold)
                        .foregroundColor(AdminSurface.secondaryText)

                    Spacer()
                }
                .padding(.horizontal, AdminSpacing.screenMargin)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(QatarHubPreset.standardHubs) { hub in
                            Button {
                                viewModel.moveToHub(hub)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: hub.icon)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(AdminSurface.primary)

                                    Text(hub.localizedName)
                                        .font(AdminType.caption1Bold)
                                        .foregroundColor(AdminSurface.primaryText)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AdminSurface.control.opacity(0.9), in: Capsule())
                                .overlay(Capsule().stroke(AdminSurface.borderSubtle, lineWidth: 0.8))
                            }
                            .buttonStyle(BranchPressStyle())
                        }
                    }
                    .padding(.horizontal, AdminSpacing.screenMargin)
                }
            }
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Address & Courier Delivery Reassurance Card
            VStack(spacing: 12) {
                // Courier Guidance Banner
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(AdminSurface.emerald.opacity(0.16))
                            .frame(width: 32, height: 32)
                        Image(systemName: "shippingbox.and.arrow.backward.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AdminSurface.emerald)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Branches_PickupTitle", alter: "نقطة انطلاق واستلام المناديب الرسمية"))
                            .font(AdminType.caption1Bold)
                            .foregroundColor(AdminSurface.primaryText)

                        Text(Language.get("Branches_PickupDesc", alter: "هذه الإحداثيات هي التي سيتوجه إليها مندوبو التوصيل لاستلام الشحنات من الفرع."))
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)
                    }

                    Spacer()
                }
                .padding(10)
                .background(AdminSurface.emerald.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AdminSurface.emerald.opacity(0.25), lineWidth: 0.8)
                )

                // Live Geocoded Address String
                HStack(spacing: 10) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primary)

                    if viewModel.isGeocoding {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.8)
                            Text(Language.get("Branches_ResolvingAddress", alter: "جارٍ تحديد العنوان الميداني بدقة…"))
                                .font(AdminType.subheadline)
                                .foregroundColor(AdminSurface.secondaryText)
                        }
                    } else {
                        Text(viewModel.formattedAddress.isEmpty ? Language.get("Branches_SelectLocationPrompt", alter: "اسحب الخريطة لتحديد موقع الفرع بدقة") : viewModel.formattedAddress)
                            .font(AdminType.bodyBold)
                            .foregroundColor(AdminSurface.primaryText)
                            .lineLimit(2)
                    }

                    Spacer()
                }

                // Coordinate Monospace Telemetry Strip
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "location.north.line.fill")
                            .font(AdminType.caption2)
                            .foregroundColor(AdminSurface.secondaryText)

                        Text(String(format: "%.6f° N, %.6f° E", viewModel.currentCoordinate.latitude, viewModel.currentCoordinate.longitude))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(AdminSurface.secondaryText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AdminSurface.control, in: Capsule())

                    Spacer()

                    Button {
                        viewModel.copyCoordinates()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text(Language.get("Copy", alter: "نسخ"))
                        }
                        .font(AdminType.caption2Bold)
                        .foregroundColor(AdminSurface.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AdminSurface.primary.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(BranchPressStyle())
                }

                // Primary Confirmation Action Button
                Button {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                    onConfirm(viewModel.currentCoordinate, viewModel.formattedAddress)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(AdminType.headline)

                        Text(Language.get("Branches_ConfirmPickupPoint", alter: "اعتماد نقطة استلام الشحنات للفرع"))
                            .font(AdminType.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(
                            colors: [AdminSurface.primary, AdminSurface.primaryPressed],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: AdminRadius.button, style: .continuous)
                    )
                    .shadow(color: AdminSurface.primary.opacity(0.28), radius: 10, y: 4)
                }
                .buttonStyle(BranchPressStyle())
            }
            .padding(.horizontal, AdminSpacing.screenMargin)
            .padding(.top, 14)
            .padding(.bottom, 32)
            .background(
                AdminSurface.background
                    .shadow(color: .black.opacity(0.14), radius: 16, y: -4)
            )
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - Needle Triangle Shape

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
