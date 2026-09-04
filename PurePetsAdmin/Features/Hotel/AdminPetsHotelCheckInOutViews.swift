//
//  AdminPetsHotelCheckInOutViews.swift
//  PurePetsAdmin
//
//  Category-defining Express Check-in, Check-out, and Room Status Studios
//  for Pets Hotel (فندق ورعاية الحيوانات الأليفة).
//  Directly integrated with authoritative backend callables.
//

import SwiftUI

// MARK: - Express Check-In Sheet
public struct AdminPetsHotelCheckInSheet: View {
    let reservation: AdminHotelReservation
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRoom: AdminHotelAccommodation?
    @State private var verification = AdminHotelCheckInVerification()
    @State private var belongings: [AdminHotelBelongingItem] = [
        AdminHotelBelongingItem(name: "طعام مخصص للحيوان", quantity: 1),
        AdminHotelBelongingItem(name: "طوق أو حزام مشي", quantity: 1)
    ]
    @State private var newBelongingName: String = ""
    @State private var internalNotes: String = ""
    @State private var showVerificationDetails: Bool = true

    public var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // Header Card
                    guestSummaryCard

                    // Error Alert Banner
                    if let err = viewModel.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(err)
                                .font(Font.custom("Beiruti-Medium", size: 13))
                                .foregroundStyle(.red)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    // Available Rooms in Wing Picker
                    roomSelectionSection

                    // Clinical & Operational Intake Verification
                    intakeVerificationSection

                    // Belongings Intake Checklist
                    belongingsIntakeSection

                    // Intake Notes
                    notesSection

                    // Confirm Intake Button
                    confirmButton
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(Language.get("Hotel_CheckIn_Title", alter: "تسجيل دخول النزيل"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        dismiss()
                    }
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminSurface.secondaryText)
                }
            }
            .onAppear {
                autoSuggestAvailableRoom()
            }
        }
    }

    private var guestSummaryCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(reservation.wing.tint.opacity(0.18))
                    .frame(width: 60, height: 60)
                Image(systemName: reservation.wing.icon)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(reservation.wing.tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(reservation.petName)
                    .font(Font.custom("Beiruti-Bold", size: 20))
                    .foregroundStyle(AdminSurface.primaryText)

                Text("\(reservation.petBreed) • \(reservation.customerName)")
                    .font(Font.custom("Beiruti-Medium", size: 14))
                    .foregroundStyle(AdminSurface.secondaryText)

                Text(reservation.formattedTotal)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AdminSurface.primary)
            }
            Spacer()
        }
        .padding(14)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
        )
    }

    private var roomSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_SelectRoom", alter: "اختر الجناح / الغرفة"), systemImage: "bed.double.fill")
                .font(Font.custom("Beiruti-Bold", size: 16))
                .foregroundStyle(AdminSurface.primaryText)

            let availableRooms = viewModel.accommodations.filter { $0.wing == reservation.wing && $0.status == .available }

            if availableRooms.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(Language.get("Hotel_NoAvailableRoomsInWing", alter: "لا توجد أجنحة شاغرة في هذا الجناح حالياً"))
                        .font(Font.custom("Beiruti-Medium", size: 13))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(availableRooms) { room in
                            let isSelected = selectedRoom?.id == room.id
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedRoom = room
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(room.accommodationNumber)
                                            .font(Font.custom("Beiruti-Bold", size: 16))
                                            .foregroundStyle(isSelected ? .white : AdminSurface.primaryText)
                                        Spacer()
                                        if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 14))
                                                .foregroundStyle(.white)
                                        }
                                    }

                                    Text(room.name)
                                        .font(Font.custom("Beiruti-Medium", size: 12))
                                        .foregroundStyle(isSelected ? .white.opacity(0.9) : AdminSurface.secondaryText)
                                        .lineLimit(1)

                                    Text(room.formattedRate)
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(isSelected ? .white.opacity(0.85) : AdminSurface.primary)
                                }
                                .padding(12)
                                .frame(width: 130, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(isSelected ? AdminSurface.primary : AdminSurface.control)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(isSelected ? AdminSurface.primary : Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var intakeVerificationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(Language.get("Hotel_VerificationTitle", alter: "متطلبات الدخول والتحقق الإلزامي"), systemImage: "checklist")
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminSurface.primaryText)
                Spacer()
                Button {
                    withAnimation(.spring()) {
                        showVerificationDetails.toggle()
                    }
                } label: {
                    Image(systemName: showVerificationDetails ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .foregroundStyle(AdminSurface.secondaryText)
                }
            }

            if showVerificationDetails {
                VStack(spacing: 8) {
                    verificationToggleRow(
                        title: Language.get("Hotel_VerifyIdentity", alter: "التحقق من هوية الحيوان والمالك"),
                        icon: "person.text.rectangle.fill",
                        binding: $verification.petIdentityVerified
                    )
                    verificationToggleRow(
                        title: Language.get("Hotel_VerifyVaccination", alter: "شهادة التطعيمات سارية وموثقة"),
                        icon: "syringe.fill",
                        binding: $verification.vaccinationVerified
                    )
                    verificationToggleRow(
                        title: Language.get("Hotel_VerifyInspection", alter: "الفحص السريري الأولي سليم"),
                        icon: "stethoscope",
                        binding: $verification.healthInspectionCompleted
                    )
                    verificationToggleRow(
                        title: Language.get("Hotel_VerifyDiet", alter: "تأكيد النظام الغذائي والحساسيات"),
                        icon: "fork.knife",
                        binding: $verification.dietConfirmed
                    )
                    verificationToggleRow(
                        title: Language.get("Hotel_VerifyEmergency", alter: "تأكيد رقم الطوارئ البديل"),
                        icon: "phone.badge.checkmark",
                        binding: $verification.emergencyContactConfirmed
                    )
                    verificationToggleRow(
                        title: Language.get("Hotel_VerifyAgreement", alter: "الموافقة على شروط الرعاية الفندقية"),
                        icon: "doc.text.fill",
                        binding: $verification.agreementAcknowledged
                    )
                }
                .padding(12)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
                )
            }
        }
    }

    private func verificationToggleRow(title: String, icon: String, binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(binding.wrappedValue ? Color(red: 0.16, green: 0.72, blue: 0.44) : AdminSurface.secondaryText)
                Text(title)
                    .font(Font.custom("Beiruti-Medium", size: 14))
                    .foregroundStyle(AdminSurface.primaryText)
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.16, green: 0.72, blue: 0.44)))
    }

    private var belongingsIntakeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Language.get("Hotel_RecordBelongings", alter: "تسجيل أغراض النزيل عند الاستلام"), systemImage: "shippingbox.fill")
                .font(Font.custom("Beiruti-Bold", size: 16))
                .foregroundStyle(AdminSurface.primaryText)

            VStack(spacing: 8) {
                ForEach(belongings) { item in
                    HStack {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(AdminSurface.primary)

                        Text(item.name)
                            .font(Font.custom("Beiruti-Medium", size: 14))
                            .foregroundStyle(AdminSurface.primaryText)

                        Spacer()

                        Button {
                            belongings.removeAll(where: { $0.id == item.id })
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(.red.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Add belonging row
                HStack(spacing: 10) {
                    TextField(Language.get("Hotel_AddBelongingPrompt", alter: "أضف غرضاً (مثل: دواء، بطانية)..."), text: $newBelongingName)
                        .font(Font.custom("Beiruti-Medium", size: 14))

                    Button {
                        guard !newBelongingName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        belongings.append(AdminHotelBelongingItem(name: newBelongingName.trimmingCharacters(in: .whitespaces)))
                        newBelongingName = ""
                    } label: {
                        Text(Language.get("Add", alter: "إضافة"))
                            .font(Font.custom("Beiruti-Bold", size: 14))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AdminSurface.primary, in: Capsule())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(14)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
            )
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(Language.get("Hotel_IntakeNotes", alter: "ملاحظات الدخول الخاصة"), systemImage: "note.text")
                .font(Font.custom("Beiruti-Bold", size: 16))
                .foregroundStyle(AdminSurface.primaryText)

            TextField(Language.get("Hotel_IntakeNotesPlaceholder", alter: "أي تعليمات تتعلق بالطعام، الحساسية، أو السلوك..."), text: $internalNotes)
                .font(Font.custom("Beiruti-Medium", size: 14))
                .padding(14)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
                )
        }
    }

    private var confirmButton: some View {
        Button {
            guard let room = selectedRoom else { return }
            Task {
                await viewModel.executeCheckIn(
                    reservation: reservation,
                    assignedRoom: room,
                    belongings: belongings,
                    verification: verification,
                    notes: internalNotes.isEmpty ? nil : internalNotes
                )
                if viewModel.errorMessage == nil {
                    dismiss()
                }
            }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isSubmitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                }
                Text(Language.get("Hotel_ConfirmCheckIn", alter: "تأكيد الدخول وتسكين النزيل"))
                    .font(Font.custom("Beiruti-Bold", size: 16))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                (selectedRoom == nil || viewModel.isSubmitting)
                    ? Color.gray.opacity(0.4)
                    : Color(red: 0.16, green: 0.72, blue: 0.44),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .shadow(color: selectedRoom == nil ? .clear : Color(red: 0.16, green: 0.72, blue: 0.44).opacity(0.3), radius: 10, y: 4)
        }
        .disabled(selectedRoom == nil || viewModel.isSubmitting)
        .buttonStyle(PlainButtonStyle())
    }

    private func autoSuggestAvailableRoom() {
        if let assignedId = reservation.assignedAccommodationId,
           let match = viewModel.accommodations.first(where: { $0.id == assignedId && $0.status == .available }) {
            selectedRoom = match
        } else if let match = viewModel.accommodations.first(where: { $0.wing == reservation.wing && $0.status == .available }) {
            selectedRoom = match
        }
    }
}

// MARK: - Express Check-Out Sheet
public struct AdminPetsHotelCheckOutSheet: View {
    let stay: AdminHotelStay
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var sendRoomForCleaning: Bool = true
    @State private var verification = AdminHotelCheckOutVerification()
    @State private var earlyReason: String = "early_departure_by_owner"

    private var isEarly: Bool {
        Date() < stay.expectedCheckOutTime
    }

    public var body: some View {
        NavigationView {
            VStack(spacing: 18) {
                // Stay Discharge Hero
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.82, green: 0.15, blue: 0.35).opacity(0.15))
                            .frame(width: 68, height: 68)
                        Image(systemName: "door.left.hand.open")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Color(red: 0.82, green: 0.15, blue: 0.35))
                    }

                    Text(stay.petName)
                        .font(Font.custom("Beiruti-Bold", size: 24))
                        .foregroundStyle(AdminSurface.primaryText)

                    Text(Language.get("Hotel_CheckoutPrompt", alter: "إجراءات مغادرة النزيل وتسليم الأغراض وتفريغ الجناح"))
                        .font(Font.custom("Beiruti-Medium", size: 14))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)

                // Error Alert Banner
                if let err = viewModel.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(err)
                            .font(Font.custom("Beiruti-Medium", size: 13))
                            .foregroundStyle(.red)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                // Verification Checklist
                VStack(spacing: 10) {
                    Toggle(isOn: $verification.belongingsReturned) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("Hotel_BelongingsHandedBack", alter: "تسليم كافة الأغراض للمالك"))
                                .font(Font.custom("Beiruti-Bold", size: 15))
                                .foregroundStyle(AdminSurface.primaryText)
                            Text(Language.get("Hotel_BelongingsVerifySub", alter: "تم التحقق من تطابق العهدة ومحتوياتها"))
                                .font(Font.custom("Beiruti-Medium", size: 12))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.16, green: 0.72, blue: 0.44)))

                    Divider()

                    Toggle(isOn: $verification.healthCheckCompleted) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("Hotel_DischargeHealthCheck", alter: "فحص المؤشرات الصحية قبل المغادرة"))
                                .font(Font.custom("Beiruti-Bold", size: 15))
                                .foregroundStyle(AdminSurface.primaryText)
                            Text(Language.get("Hotel_DischargeHealthSub", alter: "النزيل بحالة طبيعية ومستقرة"))
                                .font(Font.custom("Beiruti-Medium", size: 12))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.16, green: 0.72, blue: 0.44)))

                    Divider()

                    Toggle(isOn: $sendRoomForCleaning) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("Hotel_SendRoomCleaningPrompt", alter: "إرسال الجناح (\(stay.roomNumber)) للتعقيم والتنظيف فوراً"))
                                .font(Font.custom("Beiruti-Bold", size: 15))
                                .foregroundStyle(AdminSurface.primaryText)
                            Text(Language.get("Hotel_SendRoomCleaningDetail", alter: "سيتغير وضع الجناح إلى 'قيد التنظيف' حتى إشعاره جاهزاً"))
                                .font(Font.custom("Beiruti-Medium", size: 12))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: AdminSurface.primary))
                }
                .padding(16)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 0.75)
                )

                // Early Checkout Notice
                if isEarly {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 18))
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Language.get("Hotel_EarlyCheckoutAlert", alter: "مغادرة مبكرة قبل الموعد المقرر"))
                                .font(Font.custom("Beiruti-Bold", size: 14))
                                .foregroundStyle(AdminSurface.primaryText)
                            Text(Language.get("Hotel_EarlyCheckoutSub", alter: "سيتم احتساب الليالي الفعلية وفق السياسة التشغيلية"))
                                .font(Font.custom("Beiruti-Medium", size: 12))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Spacer()

                // Execute Departure Button
                Button {
                    Task {
                        await viewModel.executeCheckOut(
                            stay: stay,
                            verification: verification,
                            markRoomCleaning: sendRoomForCleaning,
                            earlyReason: isEarly ? earlyReason : nil
                        )
                        if viewModel.errorMessage == nil {
                            dismiss()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.right.to.line")
                                .font(.system(size: 16, weight: .bold))
                        }
                        Text(Language.get("Hotel_ConfirmCheckoutButton", alter: "إتمام المغادرة وتسليم النزيل"))
                            .font(Font.custom("Beiruti-Bold", size: 16))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        viewModel.isSubmitting
                            ? Color.gray.opacity(0.4)
                            : Color(red: 0.82, green: 0.15, blue: 0.35),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .shadow(color: Color(red: 0.82, green: 0.15, blue: 0.35).opacity(0.3), radius: 10, y: 4)
                }
                .disabled(viewModel.isSubmitting)
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(Language.get("Hotel_Checkout_Title", alter: "تسجيل المغادرة"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        dismiss()
                    }
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminSurface.secondaryText)
                }
            }
        }
    }
}

// MARK: - Room Status Quick Dial Sheet
public struct AdminPetsHotelRoomStatusSheet: View {
    let room: AdminHotelAccommodation
    @ObservedObject var viewModel: AdminPetsHotelViewModel
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(room.wing.tint.opacity(0.18))
                            .frame(width: 52, height: 52)
                        Image(systemName: room.wing.icon)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(room.wing.tint)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(room.name)
                            .font(Font.custom("Beiruti-Bold", size: 18))
                            .foregroundStyle(AdminSurface.primaryText)
                        Text("\(room.accommodationNumber) • \(room.wing.title)")
                            .font(Font.custom("Beiruti-Medium", size: 13))
                            .foregroundStyle(AdminSurface.secondaryText)
                    }
                    Spacer()
                }
                .padding(14)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text(Language.get("Hotel_ChangeStatusPrompt", alter: "تحديث الحالة التشغيلية للجناح:"))
                    .font(Font.custom("Beiruti-Bold", size: 15))
                    .foregroundStyle(AdminSurface.secondaryText)

                // Status Options List
                VStack(spacing: 8) {
                    ForEach([HotelAccommodationStatus.available, .cleaning, .inspection, .maintenance, .blocked], id: \.self) { status in
                        let isCurrent = room.status == status
                        Button {
                            viewModel.setRoomStatus(room: room, newStatus: status)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(status.color.opacity(0.15))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: status.icon)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(status.color)
                                }

                                Text(status.title)
                                    .font(Font.custom("Beiruti-Bold", size: 15))
                                    .foregroundStyle(AdminSurface.primaryText)

                                Spacer()

                                if isCurrent {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(status.color)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(isCurrent ? status.color.opacity(0.1) : AdminSurface.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(isCurrent ? status.color.opacity(0.4) : Color(uiColor: .ppSurfaceBorder).opacity(0.5), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .background(AdminSurface.background.ignoresSafeArea())
            .navigationTitle(Language.get("Hotel_RoomStatusTitle", alter: "حالة الجناح"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(Language.get("Cancel", alter: "إلغاء")) {
                        dismiss()
                    }
                    .font(Font.custom("Beiruti-Bold", size: 16))
                    .foregroundStyle(AdminSurface.secondaryText)
                }
            }
        }
    }
}
