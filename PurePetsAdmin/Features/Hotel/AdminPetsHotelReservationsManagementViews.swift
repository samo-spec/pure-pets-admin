//
//  AdminPetsHotelReservationsManagementViews.swift
//  PurePetsAdmin
//
//  Category-defining, beyond-FAANG mobile operations suite for
//  hotel reservations management (إدارة الحجوزات الفندقية).
//  Mirrors Pure Pets Console and Infra Cloud Functions.
//

import SwiftUI

// MARK: - Main Reservations Management View
public struct AdminPetsHotelReservationsManagementView: View {
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.colorScheme) private var colorScheme

    public init(viewModel: AdminPetsHotelViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Pipeline Telemetry Sentinel Deck
            pipelineTelemetryDeck

            // Lifecycle Horizon Filter Tabs
            lifecycleTabs

            // Tactical Action Bar (Search + Wing Pills + New Booking CTA)
            tacticalActionBar

            // Reservations List Content
            if viewModel.filteredReservations.isEmpty {
                emptyReservationsCard
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.filteredReservations) { res in
                        AdminPetsHotelReservationCard(reservation: res, viewModel: viewModel)
                    }
                }
            }
        }
    }

    // MARK: - Pipeline Telemetry Sentinel Deck
    private var pipelineTelemetryDeck: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Language.get("Hotel_Res_PipelineTitle", alter: "مؤشرات تدفق الحجوزات والنزلاء"))
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                Text(String.localizedStringWithFormat(
                    Language.get("Hotel_Res_TotalCountFormat", alter: "%ld حجز مسجل"),
                    viewModel.reservations.count
                ))
                .font(Font.custom("Beiruti-Medium", size: 12))
                .foregroundStyle(AdminSurface.secondaryText)
            }

            HStack(spacing: 8) {
                telemetryTile(
                    title: Language.get("Hotel_Res_PendingTab", alter: "بانتظار التأكيد"),
                    count: viewModel.reservations.filter { $0.status == .pendingConfirmation || $0.status == .draft }.count,
                    color: Color(red: 0.95, green: 0.55, blue: 0.15),
                    icon: "clock.badge.exclamationmark"
                )

                telemetryTile(
                    title: Language.get("Hotel_Res_ConfirmedTab", alter: "مؤكد وجاهز"),
                    count: viewModel.reservations.filter { $0.status == .confirmed || $0.status == .readyForCheckin }.count,
                    color: Color(red: 0.10, green: 0.55, blue: 0.85),
                    icon: "calendar.badge.checkmark"
                )

                telemetryTile(
                    title: Language.get("Hotel_Res_ArrivalsToday", alter: "وصول اليوم"),
                    count: viewModel.arrivalsTodayCount,
                    color: Color(red: 0.16, green: 0.72, blue: 0.44),
                    icon: "arrow.down.left.circle.fill"
                )

                telemetryTile(
                    title: Language.get("Hotel_Res_InStayTab", alter: "في الإقامة"),
                    count: viewModel.inHouseGuestsCount,
                    color: AdminSurface.primary,
                    icon: "pawprint.fill"
                )
            }
        }
        .padding(14)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.75)
        )
    }

    private func telemetryTile(title: String, count: Int, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(AdminSurface.primaryText)
            }

            Text(title)
                .font(Font.custom("Beiruti-Medium", size: 11))
                .foregroundStyle(AdminSurface.secondaryText)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Lifecycle Horizon Filter Tabs
    private var lifecycleTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterPill(id: "all", title: Language.get("All", alter: "الكل"))
                filterPill(id: "pending", title: Language.get("Hotel_Res_PendingTab", alter: "بانتظار التأكيد"))
                filterPill(id: "confirmed", title: Language.get("Hotel_Res_ConfirmedTab", alter: "المؤكدة"))
                filterPill(id: "in_stay", title: Language.get("Hotel_Res_InStayTab", alter: "قيد الإقامة"))
                filterPill(id: "completed", title: Language.get("Hotel_Res_CompletedTab", alter: "المكتملة"))
                filterPill(id: "cancelled", title: Language.get("Hotel_Res_CancelledTab", alter: "الملغاة والمرفوضة"))
            }
        }
    }

    private func filterPill(id: String, title: String) -> some View {
        let isSelected = viewModel.reservationStatusFilter == id
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                viewModel.reservationStatusFilter = id
            }
        } label: {
            Text(title)
                .font(Font.custom(isSelected ? "Beiruti-Bold" : "Beiruti-Medium", size: 13))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isSelected ? AdminSurface.primary : AdminSurface.control, in: Capsule())
                .foregroundStyle(isSelected ? .white : AdminSurface.primaryText)
                .overlay(Capsule().strokeBorder(isSelected ? AdminSurface.primary : Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75))
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Tactical Action Bar (Search + New Booking CTA)
    private var tacticalActionBar: some View {
        HStack(spacing: 10) {
            // Summary count
            Text(String.localizedStringWithFormat(
                Language.get("Hotel_Res_ShowingFormat", alter: "عرض %ld حجز"),
                viewModel.filteredReservations.count
            ))
            .font(Font.custom("Beiruti-Bold", size: 13))
            .foregroundStyle(AdminSurface.secondaryText)

            Spacer()

            // New Reservation CTA
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                viewModel.newReservationModalOpen = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 13, weight: .bold))
                    Text(Language.get("Hotel_Res_NewReservationCTA", alter: "حجز فندقي جديد"))
                        .font(Font.custom("Beiruti-Bold", size: 13))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    LinearGradient(
                        colors: [AdminSurface.primary, Color(red: 0.85, green: 0.20, blue: 0.40)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
                .shadow(color: AdminSurface.primary.opacity(0.3), radius: 6, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var emptyReservationsCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 40))
                .foregroundStyle(AdminSurface.secondaryText)

            Text(Language.get("Hotel_Res_NoReservationsMatch", alter: "لا توجد حجوزات مسجلة تطابق التصفية الحالية"))
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.secondaryText)

            Button {
                viewModel.newReservationModalOpen = true
            } label: {
                Text(Language.get("Hotel_Res_CreateFirst", alter: "تسجيل حجز فندقي جديد"))
                    .font(Font.custom("Beiruti-Bold", size: 14))
                    .foregroundStyle(AdminSurface.primary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Category-Defining Flagship Reservation Card
public struct AdminPetsHotelReservationCard: View {
    let reservation: AdminHotelReservation
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row: Wing Icon + Pet & Customer + Status Pill
            HStack(spacing: 12) {
                // Pet Avatar & Wing Badge
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(reservation.wing.tint.opacity(0.18))
                        .frame(width: 50, height: 50)
                    Image(systemName: reservation.wing.icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(reservation.wing.tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(reservation.petName.isEmpty ? Language.get("Pet", alter: "حيوان أليف") : reservation.petName)
                            .font(Font.custom("Beiruti-Bold", size: 17))
                            .foregroundStyle(AdminSurface.primaryText)

                        if reservation.medicationRequired {
                            Image(systemName: "pill.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))
                        }
                    }

                    HStack(spacing: 4) {
                        Text(reservation.customerName)
                            .font(Font.custom("Beiruti-Medium", size: 13))
                            .foregroundStyle(AdminSurface.primaryText)

                        Text("•")
                            .font(.system(size: 8))
                            .foregroundStyle(AdminSurface.secondaryText)

                        Text(reservation.customerPhone)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }

                Spacer()

                // Status Capsule
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(reservation.status.color)
                            .frame(width: 6, height: 6)
                        Text(reservation.status.title)
                            .font(Font.custom("Beiruti-Bold", size: 11))
                            .foregroundStyle(reservation.status.color)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(reservation.status.color.opacity(0.12), in: Capsule())

                    if !reservation.reservationNumber.isEmpty {
                        Text(reservation.reservationNumber)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }

            Divider()
                .opacity(0.6)

            // Horizon Stay Window & Room Assignment
            HStack(spacing: 12) {
                // Dates Horizon
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)

                    Text("\(formatDate(reservation.checkInDate)) → \(formatDate(reservation.checkOutDate))")
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text("(\(reservation.numberOfNights) \(Language.get("Hotel_Nights_Short", alter: "ليالي")))")
                        .font(Font.custom("Beiruti-Bold", size: 11))
                        .foregroundStyle(AdminSurface.primary)
                }

                Spacer()

                // Room Assignment Badge
                if let roomNumber = reservation.assignedRoomNumber, !roomNumber.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "bed.double.fill")
                            .font(.system(size: 10))
                        Text(roomNumber)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(reservation.wing.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(reservation.wing.tint)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 10))
                        Text(Language.get("Hotel_Room_Unassigned", alter: "غير مخصص"))
                            .font(Font.custom("Beiruti-Bold", size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(Color.orange)
                }
            }

            // Financial Balance & Action Strip
            HStack {
                // Financial Quoted / Balance
                VStack(alignment: .leading, spacing: 1) {
                    Text(Language.get("Hotel_Res_TotalQuoted", alter: "إجمالي الحساب:"))
                        .font(Font.custom("Beiruti-Medium", size: 10))
                        .foregroundStyle(AdminSurface.secondaryText)

                    Text(reservation.formattedTotal)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(AdminSurface.primaryText)
                }

                Spacer()

                // Action Buttons based on status
                HStack(spacing: 8) {
                    // Confirm action if pending
                    if reservation.status == .pendingConfirmation || reservation.status == .draft {
                        Button {
                            Task {
                                await viewModel.confirmReservation(reservation: reservation)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                Text(Language.get("Hotel_Res_ConfirmAction", alter: "تأكيد الحجز"))
                                    .font(Font.custom("Beiruti-Bold", size: 12))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.10, green: 0.55, blue: 0.85), in: Capsule())
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Check-in trigger if ready or confirmed
                    if reservation.status == .confirmed || reservation.status == .readyForCheckin || reservation.status == .preArrival {
                        Button {
                            viewModel.checkInModalReservation = reservation
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.left.circle.fill")
                                    .font(.system(size: 11))
                                Text(Language.get("Hotel_CheckInNow", alter: "تسجيل دخول"))
                                    .font(Font.custom("Beiruti-Bold", size: 12))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.16, green: 0.72, blue: 0.44), in: Capsule())
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(!viewModel.canCheckIn)
                        .opacity(viewModel.canCheckIn ? 1 : 0.5)
                    }

                    // Dossier Inspector trigger
                    Button {
                        viewModel.selectedReservationDetail = reservation
                    } label: {
                        HStack(spacing: 4) {
                            Text(Language.get("Details", alter: "التفاصيل"))
                                .font(Font.custom("Beiruti-Bold", size: 12))
                            Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AdminSurface.surface, in: Capsule())
                        .foregroundStyle(AdminSurface.primary)
                        .overlay(Capsule().strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AdminSurface.control)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.04), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.55), lineWidth: 0.85)
        )
    }

    private func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: Language.currentLanguageCode())
        df.dateFormat = "d MMM"
        return df.string(from: date)
    }
}

// MARK: - Sovereign Reservation Detail Sheet (ملف الحجز والنزيل المتكامل)
public struct AdminPetsHotelReservationDetailSheet: View {
    let reservation: AdminHotelReservation
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isExtending: Bool = false
    @State private var newDepartureDate: Date = Date()
    @State private var isShowingReasonSheet: Bool = false
    @State private var pendingAction: String = ""

    public var body: some View {
        VStack(spacing: 0) {
            sheetNavBar

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    // Hero Identity Deck
                    heroDeck

                    // Customer Fact Card
                    customerCard

                    // Pet Profile & Clinical Care Card
                    petProfileCard

                    // Stay Horizon & Room Assignment Card
                    stayHorizonCard

                    // Financial Ledger & Billing
                    billingCard

                    // Emergency Contact Card
                    if let eName = reservation.emergencyContactName, !eName.isEmpty {
                        emergencyCard(name: eName, phone: reservation.emergencyContactPhone ?? "")
                    }

                    // Special Notes
                    if let notes = reservation.specialInstructions ?? reservation.notes, !notes.isEmpty {
                        notesCard(notes: notes)
                    }

                    // Action Flight Deck
                    actionDeck
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .sheet(isPresented: $isExtending) {
            AdminPetsHotelExtendStayDialog(reservation: reservation, viewModel: viewModel)
        }
        .sheet(isPresented: $isShowingReasonSheet) {
            AdminPetsHotelReasonSheet(reservation: reservation, action: pendingAction, viewModel: viewModel)
        }
    }

    private var sheetNavBar: some View {
        AdminSovereignNavigationBar(
            title: reservation.reservationNumber.isEmpty ? Language.get("Hotel_Res_DetailTitle", alter: "تفاصيل الحجز") : reservation.reservationNumber,
            subtitle: "\(reservation.petName) • \(reservation.wing.title)",
            statusDotColor: reservation.status.tint,
            isModal: true,
            onBack: { dismiss() }
        ) {
            HStack(spacing: 4) {
                Image(systemName: reservation.status.icon)
                    .font(.system(size: 10, weight: .bold))
                Text(reservation.status.title)
                    .font(Font.custom("Beiruti-Bold", size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(reservation.status.tint.opacity(0.12), in: Capsule())
            .foregroundStyle(reservation.status.tint)
        }
    }

    private var heroDeck: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(reservation.wing.tint.opacity(0.18))
                    .frame(width: 64, height: 64)
                Image(systemName: reservation.wing.icon)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(reservation.wing.tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(reservation.petName)
                        .font(Font.custom("Beiruti-Bold", size: 20))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(reservation.status.title)
                        .font(Font.custom("Beiruti-Bold", size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(reservation.status.color.opacity(0.15), in: Capsule())
                        .foregroundStyle(reservation.status.color)
                }

                Text("\(reservation.petBreed) • \(reservation.wing.title)")
                    .font(Font.custom("Beiruti-Medium", size: 13))
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            Spacer()
        }
        .padding(14)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var customerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Customer", alter: "العميل والاتصال"), systemImage: "person.crop.circle.fill")
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reservation.customerName)
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(reservation.customerPhone)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AdminSurface.secondaryText)
                    if let email = reservation.customerEmail, !email.isEmpty {
                        Text(email)
                            .font(.system(size: 11))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }

                Spacer()

                // Direct Dial Action
                if let url = URL(string: "tel://\(reservation.customerPhone.replacingOccurrences(of: " ", with: ""))") {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "phone.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var petProfileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Pet_Details", alter: "بيانات النزيل والرعاية"), systemImage: "pawprint.fill")
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    detailRow(label: Language.get("Pet_Name", alter: "الاسم"), value: reservation.petName)
                    Spacer()
                    detailRow(label: Language.get("Breed", alter: "السلالة"), value: reservation.petBreed.isEmpty ? "—" : reservation.petBreed)
                }

                if reservation.medicationRequired {
                    HStack(spacing: 6) {
                        Image(systemName: "cross.vial.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))
                        Text(Language.get("Hotel_MedicationRequiredBadge", alter: "يتطلب خطة أدوية مسجلة"))
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))
                    }
                    .padding(8)
                    .background(Color(red: 0.90, green: 0.25, blue: 0.25).opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var stayHorizonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_Res_StayHorizon", alter: "فترة الإقامة وتخصيص الجناح"), systemImage: "calendar.badge.clock")
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Language.get("Hotel_Arrival", alter: "تاريخ الوصول"))
                            .font(Font.custom("Beiruti-Medium", size: 11))
                            .foregroundStyle(AdminSurface.secondaryText)
                        Text(formatDateTime(reservation.checkInDate))
                            .font(Font.custom("Beiruti-Bold", size: 14))
                            .foregroundStyle(AdminSurface.primaryText)
                    }

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AdminSurface.secondaryText)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Language.get("Hotel_Departure", alter: "تاريخ المغادرة"))
                            .font(Font.custom("Beiruti-Medium", size: 11))
                            .foregroundStyle(AdminSurface.secondaryText)
                        Text(formatDateTime(reservation.checkOutDate))
                            .font(Font.custom("Beiruti-Bold", size: 14))
                            .foregroundStyle(AdminSurface.primaryText)
                    }
                }

                Divider()

                HStack {
                    Text(String.localizedStringWithFormat(
                        Language.get("Hotel_Nights_Format", alter: "%ld ليلة إقامة"),
                        reservation.numberOfNights
                    ))
                    .font(Font.custom("Beiruti-Bold", size: 13))
                    .foregroundStyle(AdminSurface.primary)

                    Spacer()

                    if let room = reservation.assignedRoomNumber {
                        Text(String.localizedStringWithFormat(Language.get("Hotel_AssignedRoom_Format", alter: "جناح رقم: %@"), room))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(reservation.wing.tint)
                    } else {
                        Text(Language.get("Hotel_Room_Unassigned", alter: "غير مخصص بعد"))
                            .font(Font.custom("Beiruti-Bold", size: 12))
                            .foregroundStyle(Color.orange)
                    }
                }
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var billingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_Billing", alter: "الحساب المالي والفواتير"), systemImage: "creditcard.fill")
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 8) {
                HStack {
                    Text(Language.get("Hotel_QuotedTotal", alter: "إجمالي الإقامة التقديري:"))
                        .font(Font.custom("Beiruti-Medium", size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Spacer()
                    Text(reservation.formattedTotal)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(AdminSurface.primaryText)
                }

                if let deposit = reservation.depositMinor, deposit > 0 {
                    HStack {
                        Text(Language.get("Hotel_DepositPaid", alter: "العربون المحصل:"))
                            .font(Font.custom("Beiruti-Medium", size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)
                        Spacer()
                        Text("\(deposit / 100) \(Language.get("Currency_QAR", alter: "ر.ق"))")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                    }
                }

                if let balance = reservation.balanceDueMinor, balance > 0 {
                    HStack {
                        Text(Language.get("Hotel_BalanceDue", alter: "المتبقي للدفع:"))
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))
                        Spacer()
                        Text("\(balance / 100) \(Language.get("Currency_QAR", alter: "ر.ق"))")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(red: 0.90, green: 0.25, blue: 0.25))
                    }
                }
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func emergencyCard(name: String, phone: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("EmergencyContact", alter: "جهة الاتصال في حالات الطوارئ"), systemImage: "cross.fill")
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(Font.custom("Beiruti-Bold", size: 15))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(phone)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                Spacer()
                if let url = URL(string: "tel://\(phone.replacingOccurrences(of: " ", with: ""))") {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        Image(systemName: "phone.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                    }
                }
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func notesCard(notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(Language.get("SpecialInstructions", alter: "تعليمات وتوجيهات خاصة"), systemImage: "info.circle.fill")
                .font(Font.custom("Beiruti-Bold", size: 14))
                .foregroundStyle(AdminSurface.primaryText)

            Text(notes)
                .font(Font.custom("Beiruti-Medium", size: 13))
                .foregroundStyle(AdminSurface.secondaryText)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var actionDeck: some View {
        VStack(spacing: 10) {
            // Confirm button
            if reservation.status == .pendingConfirmation || reservation.status == .draft {
                Button {
                    Task {
                        await viewModel.confirmReservation(reservation: reservation)
                    }
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text(Language.get("Hotel_Res_ConfirmAction", alter: "تأكيد الحجز الفندقي"))
                            .font(Font.custom("Beiruti-Bold", size: 16))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.10, green: 0.55, blue: 0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
                }
            }

            // Check-in button
            if reservation.status == .confirmed || reservation.status == .readyForCheckin || reservation.status == .preArrival {
                Button {
                    dismiss()
                    viewModel.checkInModalReservation = reservation
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.left.circle.fill")
                        Text(Language.get("Hotel_CheckInNow", alter: "إتمام تسجيل الدخول الآن"))
                            .font(Font.custom("Beiruti-Bold", size: 16))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.16, green: 0.72, blue: 0.44), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
                }
                .disabled(!viewModel.canCheckIn)
            }

            // Extend Stay button
            if reservation.status != .completed && reservation.status != .cancelled {
                Button {
                    isExtending = true
                } label: {
                    HStack {
                        Image(systemName: "calendar.badge.plus")
                        Text(Language.get("Hotel_Res_ExtendStay", alter: "تمديد فترة الإقامة"))
                            .font(Font.custom("Beiruti-Bold", size: 15))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(AdminSurface.primary)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AdminSurface.primary.opacity(0.3), lineWidth: 1))
                }
            }

            // Cancel / Reject buttons
            if reservation.status != .completed && reservation.status != .cancelled && reservation.status != .checkedIn && reservation.status != .inStay {
                Button {
                    pendingAction = "cancel_reservation"
                    isShowingReasonSheet = true
                } label: {
                    Text(Language.get("Hotel_Res_CancelReservation", alter: "إلغاء الحجز الفندقي"))
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .foregroundStyle(Color(red: 0.85, green: 0.25, blue: 0.25))
                        .padding(.vertical, 10)
                }
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Font.custom("Beiruti-Medium", size: 11))
                .foregroundStyle(AdminSurface.secondaryText)
            Text(value)
                .font(Font.custom("Beiruti-Bold", size: 14))
                .foregroundStyle(AdminSurface.primaryText)
        }
    }

    private func formatDateTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: Language.currentLanguageCode())
        df.dateFormat = "d MMM yyyy, hh:mm a"
        return df.string(from: date)
    }
}

// MARK: - Sovereign Create Reservation Sheet (حجز فندقي جديد)
public struct AdminPetsHotelCreateReservationSheet: View {
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.dismiss) private var dismiss

    // Customer state
    @State private var customerName: String = ""
    @State private var customerPhone: String = ""
    @State private var customerEmail: String = ""

    // Pet state
    @State private var petName: String = ""
    @State private var petSpecies: String = "dog"
    @State private var petBreed: String = ""
    @State private var petWeight: Double = 5.0
    @State private var specialDiet: String = ""
    @State private var allergies: String = ""
    @State private var requiresMedication: Bool = false

    // Stay & Tier state
    @State private var selectedWing: HotelWing = .dogs
    @State private var selectedTypeId: String = ""
    @State private var arrivalDate: Date = Date()
    @State private var departureDate: Date = Date().addingTimeInterval(86400 * 3)

    // Financial & Extras
    @State private var depositPaidQAR: String = "0"
    @State private var emergencyName: String = ""
    @State private var emergencyPhone: String = ""
    @State private var notes: String = ""
    @State private var confirmImmediately: Bool = true

    @State private var isSubmitting: Bool = false
    @State private var validationError: String? = nil

    private var numberOfNights: Int {
        let cal = Calendar.current
        let d1 = cal.startOfDay(for: arrivalDate)
        let d2 = cal.startOfDay(for: departureDate)
        let diff = cal.dateComponents([.day], from: d1, to: d2).day ?? 1
        return max(1, diff)
    }

    private var calculatedEstimatedTotal: Int {
        let type = viewModel.accommodationTypes.first(where: { $0.id == selectedTypeId })
        let rate = type?.nightlyRateMinor ?? 15000
        return (rate * numberOfNights) / 100
    }

    public var body: some View {
        VStack(spacing: 0) {
            sheetNavBar

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    if let error = validationError {
                        Text(error)
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundStyle(Color.red)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    // Step 1: Customer Contact
                    customerSection

                    // Step 2: Pet Profile
                    petSection

                    // Step 3: Wing & Accommodation Tier
                    tierSection

                    // Step 4: Stay Horizon Dates
                    datesSection

                    // Step 5: Financial Estimate & Deposit
                    financialSection

                    // Step 6: Emergency Contact & Notes
                    emergencySection

                    // Step 7: Confirmation Options & Submit CTA
                    submitSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .onAppear {
            if selectedTypeId.isEmpty {
                selectedTypeId = viewModel.accommodationTypes.first?.id ?? ""
            }
        }
    }

    private var sheetNavBar: some View {
        AdminSovereignNavigationBar(
            title: Language.get("Hotel_Res_NewReservationTitle", alter: "تسجيل حجز فندقي جديد"),
            subtitle: Language.get("Hotel_Res_NewReservationSub", alter: "فندق بيور بيتس • حجز إقامة"),
            statusDotColor: Color(uiColor: .ppSuccess),
            isModal: true,
            onBack: { dismiss() }
        )
    }

    private var customerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Customer", alter: "بيانات العميل"), systemImage: "person.fill")
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 10) {
                TextField(Language.get("Customer_Name_Placeholder", alter: "اسم العميل بالكامل *"), text: $customerName)
                    .font(Font.custom("Beiruti-Medium", size: 14))
                    .padding(10)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                TextField(Language.get("Customer_Phone_Placeholder", alter: "رقم هاتف العميل للتواصل *"), text: $customerPhone)
                    .keyboardType(.phonePad)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .padding(10)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                TextField(Language.get("Email_Optional", alter: "البريد الإلكتروني (اختياري)"), text: $customerEmail)
                    .keyboardType(.emailAddress)
                    .font(.system(size: 14))
                    .padding(10)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var petSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Pet_Details", alter: "بيانات الحيوان الأليف والنزيل"), systemImage: "pawprint.fill")
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 12) {
                // Pet Species Picker
                HStack(spacing: 8) {
                    speciesButton(id: "dog", title: Language.get("Dog", alter: "كلب"), icon: "dog.fill")
                    speciesButton(id: "cat", title: Language.get("Cat", alter: "قط"), icon: "cat.fill")
                    speciesButton(id: "bird", title: Language.get("Bird", alter: "طائر"), icon: "bird.fill")
                    speciesButton(id: "small_pets", title: Language.get("SmallPet", alter: "أليف صغير"), icon: "hare.fill")
                }

                TextField(Language.get("Pet_Name_Placeholder", alter: "اسم الحيوان الأليف *"), text: $petName)
                    .font(Font.custom("Beiruti-Medium", size: 14))
                    .padding(10)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                TextField(Language.get("Breed_Optional", alter: "السلالة / النوع"), text: $petBreed)
                    .font(Font.custom("Beiruti-Medium", size: 14))
                    .padding(10)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Toggle(isOn: $requiresMedication) {
                    Text(Language.get("Hotel_MedicationPlanToggle", alter: "يتطلب جدول أو خطة أدوية أثناء الإقامة"))
                        .font(Font.custom("Beiruti-Medium", size: 13))
                        .foregroundStyle(AdminSurface.primaryText)
                }
                .tint(AdminSurface.primary)
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func speciesButton(id: String, title: String, icon: String) -> some View {
        let isSelected = petSpecies == id
        return Button {
            petSpecies = id
            if id == "cat" { selectedWing = .cats }
            else if id == "bird" { selectedWing = .birds }
            else if id == "small_pets" { selectedWing = .smallPets }
            else { selectedWing = .dogs }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(Font.custom("Beiruti-Bold", size: 12))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(isSelected ? AdminSurface.primary : AdminSurface.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(isSelected ? .white : AdminSurface.primaryText)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var tierSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_WingAndTier", alter: "الجناح والفئة الفندقية"), systemImage: "bed.double.fill")
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 10) {
                if !viewModel.accommodationTypes.isEmpty {
                    Menu {
                        ForEach(viewModel.accommodationTypes) { type in
                            Button {
                                selectedTypeId = type.id
                            } label: {
                                Text("\(type.displayName) (\(type.formattedRate))")
                            }
                        }
                    } label: {
                        HStack {
                            if let selected = viewModel.accommodationTypes.first(where: { $0.id == selectedTypeId }) {
                                Text("\(selected.displayName) — \(selected.formattedRate)")
                                    .font(Font.custom("Beiruti-Bold", size: 14))
                                    .foregroundStyle(AdminSurface.primaryText)
                            } else {
                                Text(Language.get("Hotel_ChooseType", alter: "اختر فئة الجناح..."))
                                    .font(Font.custom("Beiruti-Medium", size: 13))
                                    .foregroundStyle(AdminSurface.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                        .padding(12)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                } else {
                    Text(Language.get("Hotel_NoAccommodationTypesWarning", alter: "لم يتم إنشاء فئات بعد. سيتم استخدام السعر القياسي."))
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(Color.orange)
                }
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var datesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_StayPeriod", alter: "تواريخ الإقامة الفندقية"), systemImage: "calendar")
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 12) {
                DatePicker(Language.get("Hotel_ArrivalDate", alter: "تاريخ الوصول:"), selection: $arrivalDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .font(Font.custom("Beiruti-Medium", size: 14))

                DatePicker(Language.get("Hotel_DepartureDate", alter: "تاريخ المغادرة:"), selection: $departureDate, in: arrivalDate..., displayedComponents: [.date, .hourAndMinute])
                    .font(Font.custom("Beiruti-Medium", size: 14))

                HStack {
                    Text(Language.get("Hotel_TotalNights", alter: "إجمالي الليالي:"))
                        .font(Font.custom("Beiruti-Medium", size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Spacer()
                    Text("\(numberOfNights) \(Language.get("Hotel_Nights_Short", alter: "ليالي"))")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(AdminSurface.primary)
                }
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var financialSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_FinancialEstimation", alter: "الحساب التقديري والعربون"), systemImage: "banknote.fill")
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 12) {
                HStack {
                    Text(Language.get("Hotel_QuotedTotal", alter: "إجمالي الإقامة التقديري:"))
                        .font(Font.custom("Beiruti-Medium", size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Spacer()
                    Text("\(calculatedEstimatedTotal) \(Language.get("Currency_QAR", alter: "ر.ق"))")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(AdminSurface.primaryText)
                }

                HStack {
                    Text(Language.get("Hotel_DepositPaidNow", alter: "العربون المدفوع مقدماً:"))
                        .font(Font.custom("Beiruti-Medium", size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Spacer()
                    HStack {
                        TextField("0", text: $depositPaidQAR)
                            .keyboardType(.numberPad)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text(Language.get("Currency_QAR", alter: "ر.ق"))
                            .font(Font.custom("Beiruti-Bold", size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var emergencySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("EmergencyContact", alter: "جهة اتصال الطوارئ والملاحظات"), systemImage: "cross.fill")
                .font(Font.custom("Beiruti-Bold", size: 15))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 10) {
                TextField(Language.get("Emergency_Name", alter: "اسم شخص للطوارئ (اختياري)"), text: $emergencyName)
                    .font(Font.custom("Beiruti-Medium", size: 13))
                    .padding(10)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                TextField(Language.get("Emergency_Phone", alter: "هاتف الطوارئ (اختياري)"), text: $emergencyPhone)
                    .keyboardType(.phonePad)
                    .font(.system(size: 13))
                    .padding(10)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                TextField(Language.get("SpecialInstructions", alter: "أي تعليمات أو متطلبات خاصة بالنزيل..."), text: $notes)
                    .font(Font.custom("Beiruti-Medium", size: 13))
                    .padding(10)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var submitSection: some View {
        VStack(spacing: 12) {
            Toggle(isOn: $confirmImmediately) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Language.get("Hotel_ConfirmImmediately", alter: "تأكيد فوري للحجز"))
                        .font(Font.custom("Beiruti-Bold", size: 14))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(Language.get("Hotel_ConfirmImmediatelyHint", alter: "ينشئ ملف إقامة جاهز لتسجيل الدخول مباشرة"))
                        .font(Font.custom("Beiruti-Medium", size: 11))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }
            .tint(Color(red: 0.16, green: 0.72, blue: 0.44))
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button {
                validateAndCreate()
            } label: {
                HStack(spacing: 6) {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(Language.get("Hotel_CreateReservationSubmit", alter: "تأكيد وتسجيل الحجز الآن"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [AdminSurface.primary, Color(red: 0.85, green: 0.20, blue: 0.40)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .foregroundStyle(.white)
            }
            .disabled(isSubmitting)
        }
    }

    private func validateAndCreate() {
        let cleanCustomer = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPhone = customerPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPet = petName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanCustomer.isEmpty else {
            validationError = Language.get("Hotel_Err_CustomerNameRequired", alter: "يرجى إدخال اسم العميل.")
            return
        }

        guard !cleanPhone.isEmpty else {
            validationError = Language.get("Hotel_Err_CustomerPhoneRequired", alter: "يرجى إدخال رقم هاتف العميل.")
            return
        }

        guard !cleanPet.isEmpty else {
            validationError = Language.get("Hotel_Err_PetNameRequired", alter: "يرجى إدخال اسم الحيوان الأليف.")
            return
        }

        let depositMinor = (Int(depositPaidQAR.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) * 100

        let draft = AdminHotelPetDraft(
            name: cleanPet,
            categoryName: petSpecies,
            breed: petBreed,
            weightKg: petWeight,
            accommodationTypeId: selectedTypeId,
            specialDiet: specialDiet,
            allergies: allergies,
            requiresMedication: requiresMedication
        )

        validationError = nil
        isSubmitting = true

        Task {
            let success = await viewModel.createReservation(
                customerUid: "",
                customerName: cleanCustomer,
                customerPhone: cleanPhone,
                customerEmail: customerEmail.isEmpty ? nil : customerEmail,
                pets: [draft],
                wing: selectedWing,
                arrivalAt: arrivalDate,
                departureAt: departureDate,
                depositMinor: depositMinor,
                emergencyName: emergencyName.isEmpty ? nil : emergencyName,
                emergencyPhone: emergencyPhone.isEmpty ? nil : emergencyPhone,
                notes: notes.isEmpty ? nil : notes,
                confirmImmediately: confirmImmediately
            )
            isSubmitting = false
            if success {
                dismiss()
            }
        }
    }
}

// MARK: - Sovereign Extend Stay Dialog
public struct AdminPetsHotelExtendStayDialog: View {
    let reservation: AdminHotelReservation
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var newDepartureDate: Date = Date()
    @State private var reasonCode: String = "customer_request"
    @State private var isSubmitting: Bool = false

    public init(reservation: AdminHotelReservation, viewModel: AdminPetsHotelViewModel) {
        self.reservation = reservation
        self.viewModel = viewModel
        _newDepartureDate = State(initialValue: reservation.checkOutDate.addingTimeInterval(86400 * 2))
    }

    public var body: some View {
        VStack(spacing: 0) {
            AdminSovereignNavigationBar(
                title: Language.get("Hotel_Res_ExtendStay", alter: "تمديد الإقامة"),
                subtitle: "\(reservation.petName) • \(reservation.reservationNumber)",
                statusDotColor: Color(uiColor: .ppSuccess),
                isModal: true,
                onBack: { dismiss() }
            )

            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Language.get("Hotel_ExtendStay_Title", alter: "تمديد فترة إقامة الحجز"))
                        .font(Font.custom("Beiruti-Bold", size: 18))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(Language.get("Hotel_ExtendStay_Description", alter: "حدد تاريخ المغادرة الجديد لتحديث الحجز وسجلات الغرف تلقائياً."))
                        .font(Font.custom("Beiruti-Medium", size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                DatePicker(Language.get("Hotel_NewDepartureDate", alter: "تاريخ المغادرة الجديد:"), selection: $newDepartureDate, in: reservation.checkOutDate..., displayedComponents: [.date, .hourAndMinute])
                    .font(Font.custom("Beiruti-Bold", size: 14))
                    .padding(14)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Spacer()

                Button {
                    isSubmitting = true
                    Task {
                        let success = await viewModel.extendReservation(
                            reservation: reservation,
                            newDepartureAt: newDepartureDate,
                            reasonCode: reasonCode
                        )
                        isSubmitting = false
                        if success {
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        }
                        Text(Language.get("Hotel_ConfirmExtendStayCTA", alter: "تأكيد التمديد"))
                            .font(Font.custom("Beiruti-Bold", size: 16))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AdminSurface.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
                }
                .disabled(isSubmitting)
            }
            .padding(18)
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}

// MARK: - Sovereign Reason Dialog Sheet (لإلغاء أو رفض الحجز مع السبب)
public struct AdminPetsHotelReasonSheet: View {
    let reservation: AdminHotelReservation
    let action: String
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedReasonCode: String = "customer_request"
    @State private var note: String = ""
    @State private var isSubmitting: Bool = false

    private let reasonOptions: [(id: String, title: String)] = [
        ("customer_request", Language.get("Hotel_Reason_CustomerRequest", alter: "طلب العميل إلغاء الحجز")),
        ("no_show", Language.get("Hotel_Reason_NoShow", alter: "العميل لم يحضر بالموعد")),
        ("health_issue", Language.get("Hotel_Reason_HealthIssue", alter: "عائق صحي أو عدم اكتمال التطعيمات")),
        ("capacity_conflict", Language.get("Hotel_Reason_CapacityConflict", alter: "عدم توفر جناح مناسب")),
        ("operator_override", Language.get("Hotel_Reason_OperatorOverride", alter: "قرار إداري استثنائي"))
    ]

    public init(reservation: AdminHotelReservation, action: String, viewModel: AdminPetsHotelViewModel) {
        self.reservation = reservation
        self.action = action
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            AdminSovereignNavigationBar(
                title: Language.get("Hotel_Res_CancelReservation", alter: "إلغاء الحجز"),
                subtitle: "\(reservation.petName) • \(reservation.reservationNumber)",
                statusDotColor: Color(uiColor: .ppError),
                isModal: true,
                onBack: { dismiss() }
            )

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("Hotel_Reason_SheetTitle", alter: "سبب إلغاء أو تعديل حالة الحجز"))
                        .font(Font.custom("Beiruti-Bold", size: 16))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(Language.get("Hotel_Reason_SheetHint", alter: "يتطلب النظام تسجيل رمز سبب موثق في سجل الرقابة."))
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Reason Selection Matrix
                VStack(spacing: 8) {
                    ForEach(reasonOptions, id: \.id) { option in
                        let isSelected = selectedReasonCode == option.id
                        Button {
                            selectedReasonCode = option.id
                        } label: {
                            HStack {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(isSelected ? Color.red : AdminSurface.secondaryText)

                                Text(option.title)
                                    .font(Font.custom("Beiruti-Medium", size: 14))
                                    .foregroundStyle(AdminSurface.primaryText)

                                Spacer()
                            }
                            .padding(12)
                            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                TextField(Language.get("Notes_Optional", alter: "ملاحظات إضافية توضيحية..."), text: $note)
                    .font(Font.custom("Beiruti-Medium", size: 13))
                    .padding(12)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Spacer()

                Button {
                    isSubmitting = true
                    Task {
                        let success = await viewModel.transitionReservation(
                            reservation: reservation,
                            action: action,
                            reasonCode: selectedReasonCode,
                            note: note.isEmpty ? nil : note
                        )
                        isSubmitting = false
                        if success {
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        }
                        Text(Language.get("Hotel_ConfirmCancellationCTA", alter: "تأكيد إلغاء الحجز"))
                            .font(Font.custom("Beiruti-Bold", size: 16))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
                }
                .disabled(isSubmitting)
            }
            .padding(18)
        }
        .background(AdminSurface.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
    }
}
