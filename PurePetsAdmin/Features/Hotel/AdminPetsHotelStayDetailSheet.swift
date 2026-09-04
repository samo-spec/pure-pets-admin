//
//  AdminPetsHotelStayDetailSheet.swift
//  PurePetsAdmin
//
//  Category-defining guest dossier and stay inspector for Pets Hotel.
//  Pulls live clinical care, belongings, ledger, and timeline from hotelReadOperations.
//

import SwiftUI

public struct AdminPetsHotelStayDetailSheet: View {
    let stay: AdminHotelStay
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var activeStay: AdminHotelStay {
        if let current = viewModel.selectedStayDetail, current.id == stay.id {
            return current
        }
        return stay
    }

    public var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    // Hero Identity Deck
                    guestHeroDeck

                    // Clinical & Special Attention Banner (if not normal)
                    if activeStay.guestStatus != .normal {
                        clinicalAttentionBanner
                    }

                    // Room & Horizon Twin Pillar
                    roomAndHorizonPillars

                    // Financial Ledger Pill (if available)
                    if viewModel.canViewBilling && activeStay.grandTotalMinor > 0 {
                        financialLedgerCard
                    }

                    // Care Schedule & Daily Tasks
                    if viewModel.canViewCare {
                        careTasksSection

                        // Belongings Inventory Checklist
                        belongingsSection
                    }

                    // Owner Contact Flight Deck
                    ownerContactSection

                    // Action Controls: Check Out / Manage
                    actionControls
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(activeStay.petName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                }
            }
            .task {
                if viewModel.canViewCare {
                    await viewModel.loadStayDossier(stayId: stay.id, updatePresentedDetail: true)
                }
            }
        }
    }

    // MARK: - Hero Identity Deck
    private var guestHeroDeck: some View {
        HStack(spacing: 16) {
            // Pet Avatar Squircle
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(activeStay.wing.tint.opacity(0.18))
                    .frame(width: 76, height: 76)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(activeStay.wing.tint.opacity(0.4), lineWidth: 1)
                    )

                Image(systemName: activeStay.wing.icon)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(activeStay.wing.tint)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(activeStay.petName)
                        .font(Font.custom("Beiruti-Bold", size: 24))
                        .foregroundStyle(AdminSurface.primaryText)

                    // Guest Status Pill
                    HStack(spacing: 4) {
                        Image(systemName: activeStay.guestStatus.icon)
                            .font(.system(size: 11, weight: .bold))
                        Text(activeStay.guestStatus.title)
                            .font(Font.custom("Beiruti-Bold", size: 12))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(activeStay.guestStatus.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(activeStay.guestStatus.color)
                }

                Text("\(activeStay.petBreed) • \(activeStay.petSpecies)")
                    .font(Font.custom("Beiruti-Medium", size: 15))
                    .foregroundStyle(AdminSurface.secondaryText)

                HStack(spacing: 6) {
                    Text(Language.get("Hotel_StayNo", alter: "رقم الإقامة:"))
                        .font(Font.custom("Beiruti-Medium", size: 12))
                        .foregroundStyle(AdminSurface.secondaryText)
                    Text(activeStay.stayNumber)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(AdminSurface.primary)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AdminSurface.control)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.04), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
        )
    }

    // MARK: - Clinical Attention Banner
    private var clinicalAttentionBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(activeStay.guestStatus.color)

            VStack(alignment: .leading, spacing: 4) {
                Text(Language.get("Hotel_Clinical_Alert", alter: "تنبيه رعاية خاصة"))
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(activeStay.guestStatus.color)

                if let notes = activeStay.internalNotes, !notes.isEmpty {
                    Text(notes)
                        .font(Font.custom("Beiruti-Regular", size: 13))
                        .foregroundStyle(AdminSurface.primaryText)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(activeStay.guestStatus.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(activeStay.guestStatus.color.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Room & Horizon Pillars
    private var roomAndHorizonPillars: some View {
        HStack(spacing: 12) {
            // Room Pillar
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(activeStay.wing.tint)
                    Text(Language.get("Hotel_AssignedRoom", alter: "الجناح المقيم به"))
                        .font(Font.custom("Beiruti-Medium", size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Text(activeStay.roomNumber)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AdminSurface.primaryText)

                Text(activeStay.wing.title)
                    .font(Font.custom("Beiruti-Medium", size: 12))
                    .foregroundStyle(activeStay.wing.tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
            )

            // Horizon / Duration Pillar
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 14))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("Hotel_StayPeriod", alter: "فترة الإقامة"))
                        .font(Font.custom("Beiruti-Medium", size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Text(formatDateRange(from: activeStay.checkInTime, to: activeStay.expectedCheckOutTime))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AdminSurface.primaryText)

                // Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AdminSurface.surface)
                            .frame(height: 6)
                        Capsule()
                            .fill(AdminSurface.primary)
                            .frame(width: geo.size.width * CGFloat(activeStay.stayProgress), height: 6)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
            )
        }
    }

    // MARK: - Financial Ledger Card
    private var financialLedgerCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Language.get("Hotel_Ledger_Total", alter: "إجمالي الحساب:"))
                    .font(Font.custom("Beiruti-Medium", size: 12))
                    .foregroundStyle(AdminSurface.secondaryText)
                Text(String(format: "%.0f %@", Double(activeStay.grandTotalMinor) / 100.0, Language.get("Currency_QAR", alter: "ر.ق")))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AdminSurface.primaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(Language.get("Hotel_Ledger_Balance", alter: "المتبقي للدفع:"))
                    .font(Font.custom("Beiruti-Medium", size: 12))
                    .foregroundStyle(AdminSurface.secondaryText)
                Text(String(format: "%.0f %@", Double(activeStay.outstandingMinor) / 100.0, Language.get("Currency_QAR", alter: "ر.ق")))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(activeStay.outstandingMinor > 0 ? Color.orange : Color(red: 0.16, green: 0.72, blue: 0.44))
            }
        }
        .padding(14)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
        )
    }

    // MARK: - Care Schedule & Daily Tasks
    private var careTasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(Language.get("Hotel_CareSchedule", alter: "جدول الرعاية والمهام اليومية"), systemImage: "heart.text.square.fill")
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
                Text("\(activeStay.dailyCareTasks.filter { $0.isCompleted }.count)/\(activeStay.dailyCareTasks.count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AdminSurface.secondaryText)
            }

            if activeStay.dailyCareTasks.isEmpty {
                Text(Language.get("Hotel_NoTasksScheduled", alter: "لا توجد مهام رعاية متبقية لهذا النزيل"))
                    .font(Font.custom("Beiruti-Medium", size: 13))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(activeStay.dailyCareTasks) { task in
                        Button {
                            viewModel.toggleCareTask(stay: activeStay, task: task)
                        } label: {
                            HStack(spacing: 12) {
                                // Status Circle
                                ZStack {
                                    Circle()
                                        .strokeBorder(task.isCompleted ? Color(red: 0.16, green: 0.72, blue: 0.44) : Color.gray.opacity(0.4), lineWidth: 2)
                                        .frame(width: 24, height: 24)
                                    if task.isCompleted {
                                        Circle()
                                            .fill(Color(red: 0.16, green: 0.72, blue: 0.44))
                                            .frame(width: 14, height: 14)
                                    }
                                }

                                Image(systemName: task.taskType.icon)
                                    .font(.system(size: 15))
                                    .foregroundStyle(task.isCompleted ? Color(red: 0.16, green: 0.72, blue: 0.44) : AdminSurface.primary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.taskType.title)
                                        .strikethrough(task.isCompleted)
                                        .font(Font.custom("Beiruti-Bold", size: 15))
                                        .foregroundColor(task.isCompleted ? AdminSurface.secondaryText : AdminSurface.primaryText)

                                    if let by = task.completedByStaffName, task.isCompleted {
                                        Text("\(Language.get("Hotel_CompletedBy", alter: "بواسطة:")) \(by)")
                                            .font(Font.custom("Beiruti-Regular", size: 11))
                                            .foregroundStyle(AdminSurface.secondaryText)
                                    }
                                }

                                Spacer()

                                Text(task.scheduledTime)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(task.isCompleted ? AdminSurface.secondaryText : AdminSurface.primary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(!viewModel.canTransitionCareTask(task))
                    }
                }
                .padding(14)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
                )
            }
        }
    }

    // MARK: - Belongings Inventory
    private var belongingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_BelongingsInventory", alter: "محتويات وأغراض النزيل"), systemImage: "shippingbox.fill")
                .font(Font.custom("Beiruti-Bold", size: 16))
                .foregroundStyle(AdminSurface.primaryText)

            if activeStay.belongings.isEmpty {
                Text(Language.get("Hotel_NoBelongings", alter: "لا توجد أغراض مسجلة عند الدخول"))
                    .font(Font.custom("Beiruti-Medium", size: 13))
                    .foregroundStyle(AdminSurface.secondaryText)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(activeStay.belongings) { item in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))

                            Text(item.name)
                                .font(Font.custom("Beiruti-Medium", size: 14))
                                .foregroundStyle(AdminSurface.primaryText)

                            Spacer()

                            Text("x\(item.quantity)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(14)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
                )
            }
        }
    }

    // MARK: - Owner Contact Section
    private var ownerContactSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_PetOwner", alter: "بيانات مالك الحيوان"), systemImage: "person.crop.circle.fill")
                .font(Font.custom("Beiruti-Bold", size: 16))
                .foregroundStyle(AdminSurface.primaryText)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(activeStay.customerName)
                        .font(Font.custom("Beiruti-Bold", size: 15))
                        .foregroundStyle(AdminSurface.primaryText)
                    Text(activeStay.customerPhone)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AdminSurface.secondaryText)
                }

                Spacer()

                // Quick Call Button
                if let url = URL(string: "tel:\(activeStay.customerPhone.replacingOccurrences(of: " ", with: ""))") {
                    Link(destination: url) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.15))
                                .frame(width: 40, height: 40)
                            Image(systemName: "phone.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color(red: 0.16, green: 0.72, blue: 0.44))
                        }
                    }
                }

                // WhatsApp Button
                if let waURL = URL(string: "whatsapp://send?phone=\(activeStay.customerPhone.filter("0123456789".contains))") {
                    Link(destination: waURL) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.18, green: 0.80, blue: 0.44).opacity(0.15))
                                .frame(width: 40, height: 40)
                            Image(systemName: "message.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color(red: 0.18, green: 0.80, blue: 0.44))
                        }
                    }
                }
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
            )
        }
    }

    // MARK: - Action Controls
    private var actionControls: some View {
        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                viewModel.checkOutModalStay = activeStay
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.to.line")
                    .font(.system(size: 15, weight: .bold))
                Text(Language.get("Hotel_Execute_Checkout", alter: "تسجيل المغادرة وتسليم النزيل"))
                    .font(Font.custom("Beiruti-Bold", size: 16))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color(red: 0.82, green: 0.15, blue: 0.35), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color(red: 0.82, green: 0.15, blue: 0.35).opacity(0.3), radius: 10, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!viewModel.canCheckOut)
        .opacity(viewModel.canCheckOut ? 1 : 0.45)
    }

    private func formatDateRange(from: Date, to: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: Language.currentLanguageCode())
        df.dateFormat = "d MMM"
        return "\(df.string(from: from)) - \(df.string(from: to))"
    }
}
