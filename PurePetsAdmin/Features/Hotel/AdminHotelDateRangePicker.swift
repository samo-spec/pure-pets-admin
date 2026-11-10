//
//  AdminHotelDateRangePicker.swift
//  PurePetsAdmin
//
//  Category-Defining Sovereign Date Range Studio for Pets Hotel.
//  First-Principles Calendar Grid with Continuous Horizon Ribbon,
//  Stay Length Presets, Time Steppers, and 100% Strict Beiruti Typography.
//

import SwiftUI
import UIKit

// MARK: - Local Typography Helper (100% Beiruti Strict Mandate)

private struct DatePickerBeiruti {
    static func bold(_ size: CGFloat) -> Font {
        PPBrandFont.bold(size: size)
    }
    static func semiBold(_ size: CGFloat) -> Font {
        PPBrandFont.bold(size: size)
    }
    static func medium(_ size: CGFloat) -> Font {
        PPBrandFont.medium(size: size)
    }
    static func regular(_ size: CGFloat) -> Font {
        PPBrandFont.regular(size: size)
    }
}

// MARK: - Stay Quick Preset

public enum HotelStayDurationPreset: String, CaseIterable, Identifiable {
    case weekend = "weekend"
    case threeNights = "three_nights"
    case week = "week"
    case twoWeeks = "two_weeks"
    case month = "month"

    public var id: String { rawValue }

    public var nights: Int {
        switch self {
        case .weekend: return 2
        case .threeNights: return 3
        case .week: return 7
        case .twoWeeks: return 14
        case .month: return 30
        }
    }

    public var localizedTitle: String {
        switch self {
        case .weekend: return Language.get("Hotel_StayPreset_Weekend", alter: "عطلة نهاية الأسبوع (ليلتان)")
        case .threeNights: return Language.get("Hotel_StayPreset_3Nights", alter: "3 ليالٍ")
        case .week: return Language.get("Hotel_StayPreset_Week", alter: "أسبوع (7 ليالٍ)")
        case .twoWeeks: return Language.get("Hotel_StayPreset_2Weeks", alter: "أسبوعان (14 ليلة)")
        case .month: return Language.get("Hotel_StayPreset_Month", alter: "شهر (30 ليلة)")
        }
    }
}

// MARK: - Sovereign Custom Date Range Picker

public struct AdminHotelDateRangePicker: View {
    @Binding public var arrivalDate: Date
    @Binding public var departureDate: Date
    public var onRangeChanged: ((Date, Date) -> Void)? = nil

    @State private var currentDisplayedMonth: Date = Date()
    @State private var isSelectingDeparture: Bool = false
    @State private var showTimeControls: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activePreset: HotelStayDurationPreset? {
        HotelStayDurationPreset.allCases.first { $0.nights == numberOfNights }
    }

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: Language.currentLanguageCode())
        return cal
    }()

    public init(
        arrivalDate: Binding<Date>,
        departureDate: Binding<Date>,
        onRangeChanged: ((Date, Date) -> Void)? = nil
    ) {
        self._arrivalDate = arrivalDate
        self._departureDate = departureDate
        self.onRangeChanged = onRangeChanged
        self._currentDisplayedMonth = State(initialValue: arrivalDate.wrappedValue)
    }

    private var numberOfNights: Int {
        let d1 = calendar.startOfDay(for: arrivalDate)
        let d2 = calendar.startOfDay(for: departureDate)
        let diff = calendar.dateComponents([.day], from: d1, to: d2).day ?? 1
        return max(1, diff)
    }

    public var body: some View {
        VStack(spacing: AdminSpacing.base) {
            if dynamicTypeSize.isAccessibilitySize {
                nativeDateControls
                presetsScrollBar
            } else {
                horizonSummaryHeader
                presetsScrollBar
                calendarDeck
                timeControlsBar
            }
        }
        .padding(AdminSpacing.base)
        .background(AdminSurface.card, in: RoundedRectangle(
            cornerRadius: AdminRadius.card,
            style: .continuous
        ))
        .overlay {
            RoundedRectangle(cornerRadius: AdminRadius.card, style: .continuous)
                .stroke(AdminSurface.hairline, lineWidth: AdminStroke.thin)
        }
        .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
        .environment(\.locale, Locale(identifier: Language.currentLanguageCode() ?? "ar"))
        .onChange(of: [arrivalDate, departureDate]) { _ in
            onRangeChanged?(arrivalDate, departureDate)
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    /// System date controls retain semantic labels and a complete editing path
    /// when a seven-column calendar cannot grow with accessibility text.
    private var nativeDateControls: some View {
        VStack(alignment: .leading, spacing: AdminSpacing.base) {
            DatePicker(
                Language.get("Hotel_Arrival_Title", alter: "الوصول"),
                selection: Binding(
                    get: { arrivalDate },
                    set: { date in
                        let duration = max(1, departureDate.timeIntervalSince(arrivalDate))
                        arrivalDate = date
                        if departureDate <= date {
                            departureDate = date.addingTimeInterval(duration)
                        }
                    }
                ),
                in: min(arrivalDate, calendar.startOfDay(for: Date()))...,
                displayedComponents: [.date, .hourAndMinute]
            )
            DatePicker(
                Language.get("Hotel_Departure_Title", alter: "المغادرة"),
                selection: $departureDate,
                in: arrivalDate.addingTimeInterval(1)...,
                displayedComponents: [.date, .hourAndMinute]
            )
        }
        .datePickerStyle(.compact)
        .font(AdminType.body)
    }

    // MARK: - 1. Horizon Summary Header

    private var horizonSummaryHeader: some View {
        HStack(alignment: .center, spacing: AdminSpacing.sm) {
            dateSummary(
                title: Language.get("Hotel_Arrival_Title", alter: "الوصول"),
                date: arrivalDate,
                isDeparture: false
            )

            VStack(spacing: AdminSpacing.xs) {
                Image(systemName: "moon.stars")
                    .accessibilityHidden(true)
                Text("\(numberOfNights) \(Language.get("Hotel_NightsPluralUnit", alter: "ليالٍ"))")
                    .font(AdminType.footnoteBold)
            }
            .foregroundStyle(AdminSurface.primary)
            .padding(AdminSpacing.sm)
            .accessibilityElement(children: .combine)

            dateSummary(
                title: Language.get("Hotel_Departure_Title", alter: "المغادرة"),
                date: departureDate,
                isDeparture: true
            )
        }
    }

    private func dateSummary(title: String, date: Date, isDeparture: Bool) -> some View {
        let isSelected = isSelectingDeparture == isDeparture
        let accent = isDeparture ? AdminSurface.amber : AdminSurface.emerald
        return Button {
            isSelectingDeparture = isDeparture
        } label: {
            VStack(alignment: .leading, spacing: AdminSpacing.xs) {
                Text(title)
                    .font(AdminType.footnote)
                    .foregroundStyle(AdminSurface.secondaryText)
                Text(formatShortDate(date))
                    .font(AdminType.headline)
                    .foregroundStyle(AdminSurface.primaryText)
                Text(formatTimeString(date))
                    .font(AdminType.footnote)
                    .foregroundStyle(accent)
            }
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.minimum, alignment: .leading)
            .padding(AdminSpacing.sm)
            .background(AdminSurface.control, in: RoundedRectangle(
                cornerRadius: AdminRadius.medium,
                style: .continuous
            ))
            .overlay {
                RoundedRectangle(cornerRadius: AdminRadius.medium, style: .continuous)
                    .stroke(isSelected ? accent : AdminSurface.hairline, lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(fullDateLabel(date))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - 2. Presets Scroll Bar

    private var presetsScrollBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(HotelStayDurationPreset.allCases) { preset in
                    let isSelected = (activePreset == preset && numberOfNights == preset.nights)
                    Button {
                        applyPreset(preset)
                    } label: {
                        Text(preset.localizedTitle)
                            .font(DatePickerBeiruti.bold(isSelected ? 12 : 11))
                            .foregroundStyle(isSelected ? Color.white : AdminSurface.primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(minHeight: AdminTouchTarget.minimum)
                            .background(
                                isSelected ? AdminSurface.primary : Color(uiColor: .ppForeground),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(isSelected ? Color.clear : AdminSurface.hairline, lineWidth: 0.6)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 3. Interactive Calendar Grid

    private var calendarDeck: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            calendarContent
                .frame(minWidth: AdminTouchTarget.minimum * 7 + AdminSpacing.md * 2)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var calendarContent: some View {
        VStack(spacing: 8) {
            // Month Switcher Header
            HStack {
                Button {
                    navigateMonth(by: -1)
                } label: {
                    Image(systemName: Language.isRTL() ? "chevron.right" : "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AdminSurface.primaryText)
                        .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                        .background(AdminSurface.control, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Language.get("Hotel_Calendar_PreviousMonth", alter: "الشهر السابق"))

                Spacer()

                Text(monthYearTitle(for: currentDisplayedMonth))
                    .font(DatePickerBeiruti.bold(15))
                    .foregroundStyle(AdminSurface.primaryText)

                Spacer()

                Button {
                    navigateMonth(by: 1)
                } label: {
                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AdminSurface.primaryText)
                        .frame(width: AdminTouchTarget.minimum, height: AdminTouchTarget.minimum)
                        .background(AdminSurface.control, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Language.get("Hotel_Calendar_NextMonth", alter: "الشهر التالي"))
            }
            .padding(.horizontal, 4)

            // Weekday symbols
            let symbols = localizedWeekdaySymbols()
            HStack(spacing: 0) {
                ForEach(symbols, id: \.self) { sym in
                    Text(sym)
                        .font(DatePickerBeiruti.bold(11))
                        .foregroundStyle(AdminSurface.secondaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 4)

            // 7-Column Days Grid
            let days = daysInDisplayedMonth()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(days, id: \.id) { item in
                    if let date = item.date {
                        calendarDayCell(date)
                    } else {
                        Color.clear
                            .frame(height: AdminTouchTarget.minimum)
                    }
                }
            }
        }
        .padding(12)
        .background(
            Color(uiColor: .ppForeground).opacity(0.6),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    @ViewBuilder
    private func calendarDayCell(_ date: Date) -> some View {
        let isArrival = calendar.isDate(date, inSameDayAs: arrivalDate)
        let isDeparture = calendar.isDate(date, inSameDayAs: departureDate)
        let isInRange = (date > arrivalDate && date < departureDate)
        let isPast = date < calendar.startOfDay(for: Date())
        let isToday = calendar.isDateInToday(date)

        ZStack {
            // Range ribbon background
            if isInRange {
                Rectangle()
                    .fill(AdminSurface.primary.opacity(0.14))
                    .frame(height: 34)
            } else if isArrival && departureDate > arrivalDate {
                HStack(spacing: 0) {
                    Spacer()
                    Rectangle()
                        .fill(AdminSurface.primary.opacity(0.14))
                        .frame(height: 34)
                }
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            } else if isDeparture && departureDate > arrivalDate {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(AdminSurface.primary.opacity(0.14))
                        .frame(height: 34)
                    Spacer()
                }
                .environment(\.layoutDirection, Language.isRTL() ? .rightToLeft : .leftToRight)
            }

            // Interactive Day Button
            Button {
                guard !isPast else { return }
                handleDateTapped(date)
            } label: {
                ZStack {
                    if isArrival {
                        Circle()
                            .fill(Color(uiColor: .systemGreen))
                            .frame(width: 32, height: 32)
                            .shadow(color: Color(uiColor: .systemGreen).opacity(0.4), radius: 4, y: 1)
                    } else if isDeparture {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 32, height: 32)
                            .shadow(color: Color.orange.opacity(0.4), radius: 4, y: 1)
                    } else if isToday {
                        Circle()
                            .strokeBorder(AdminSurface.primary, lineWidth: 1.2)
                            .frame(width: 30, height: 30)
                    }

                    Text("\(calendar.component(.day, from: date))")
                        .font(DatePickerBeiruti.bold(isArrival || isDeparture ? 13 : 12))
                        .foregroundStyle(
                            isArrival || isDeparture ? Color.white :
                            isPast ? AdminSurface.secondaryText.opacity(0.3) :
                            isInRange ? AdminSurface.primaryText :
                            AdminSurface.primaryText
                        )
                }
                .frame(maxWidth: .infinity, minHeight: AdminTouchTarget.minimum)
            }
            .buttonStyle(.plain)
            .disabled(isPast)
            .accessibilityLabel(fullDateLabel(date))
            .accessibilityValue(
                isArrival ? Language.get("Hotel_Arrival_Title", alter: "الوصول") :
                isDeparture ? Language.get("Hotel_Departure_Title", alter: "المغادرة") :
                isInRange ? Language.get("Hotel_Calendar_InRange", alter: "ضمن فترة الإقامة") : ""
            )
            .accessibilityAddTraits(isArrival || isDeparture ? .isSelected : [])
        }
    }

    // MARK: - 4. Integrated Check-in & Check-out Time Strip

    private var timeControlsBar: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showTimeControls.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AdminSurface.primary)
                    Text(Language.get("Hotel_AdjustArrivalDepartureTimes", alter: "تعديل أوقات الوصول والمغادرة"))
                        .font(DatePickerBeiruti.bold(12))
                        .foregroundStyle(AdminSurface.primary)
                    Spacer()
                    Image(systemName: showTimeControls ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AdminSurface.secondaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(minHeight: AdminTouchTarget.minimum)
                .background(AdminSurface.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            if showTimeControls {
                HStack(spacing: 12) {
                    // Check-in Time Picker
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Circle().fill(Color(uiColor: .systemGreen)).frame(width: 6, height: 6)
                            Text(Language.get("Hotel_CheckinTime_Label", alter: "وقت تسجيل الوصول"))
                                .font(DatePickerBeiruti.medium(11))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }

                        DatePicker(Language.get("Hotel_CheckinTime_Label", alter: "وقت تسجيل الوصول"), selection: $arrivalDate, displayedComponents: [.hourAndMinute])
                            .labelsHidden()
                            .font(DatePickerBeiruti.bold(12))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color(uiColor: .ppForeground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    // Check-out Time Picker
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.orange).frame(width: 6, height: 6)
                            Text(Language.get("Hotel_CheckoutTime_Label", alter: "وقت تسجيل المغادرة"))
                                .font(DatePickerBeiruti.medium(11))
                                .foregroundStyle(AdminSurface.secondaryText)
                        }

                        DatePicker(Language.get("Hotel_CheckoutTime_Label", alter: "وقت تسجيل المغادرة"), selection: $departureDate, displayedComponents: [.hourAndMinute])
                            .labelsHidden()
                            .font(DatePickerBeiruti.bold(12))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color(uiColor: .ppForeground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Logic & Date Calculation

    private func handleDateTapped(_ date: Date) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let cleanTapped = calendar.startOfDay(for: date)
        let cleanArrival = calendar.startOfDay(for: arrivalDate)

        if !isSelectingDeparture {
            // Selecting Check-in date: preserve existing time components
            let newArrival = combine(date: cleanTapped, withTimeFrom: arrivalDate)
            arrivalDate = newArrival

            // If departure is now before or same day as arrival, push departure forward
            if departureDate <= newArrival {
                departureDate = calendar.date(byAdding: .day, value: 1, to: newArrival) ?? newArrival.addingTimeInterval(86400)
            }
            // Automatically prompt to select departure next
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isSelectingDeparture = true
            }
        } else {
            // Selecting Check-out date
            if cleanTapped > cleanArrival {
                departureDate = combine(date: cleanTapped, withTimeFrom: departureDate)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isSelectingDeparture = false
                }
            } else {
                // Tapped on or before arrival -> treat as new check-in date
                let newArrival = combine(date: cleanTapped, withTimeFrom: arrivalDate)
                arrivalDate = newArrival
                departureDate = calendar.date(byAdding: .day, value: 1, to: newArrival) ?? newArrival.addingTimeInterval(86400)
            }
        }
    }

    private func applyPreset(_ preset: HotelStayDurationPreset) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let nights = preset.nights
        let cleanArrival = calendar.startOfDay(for: arrivalDate)

        if let targetDeparture = calendar.date(byAdding: .day, value: nights, to: cleanArrival) {
            departureDate = combine(date: targetDeparture, withTimeFrom: departureDate)
            isSelectingDeparture = false
        }
    }

    private func navigateMonth(by amount: Int) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let next = calendar.date(byAdding: .month, value: amount, to: currentDisplayedMonth) {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentDisplayedMonth = next
            }
        }
    }

    private func combine(date: Date, withTimeFrom source: Date) -> Date {
        let timeComps = calendar.dateComponents([.hour, .minute], from: source)
        var dateComps = calendar.dateComponents([.year, .month, .day], from: date)
        dateComps.hour = timeComps.hour ?? 14
        dateComps.minute = timeComps.minute ?? 0
        return calendar.date(from: dateComps) ?? date
    }

    private func monthYearTitle(for date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: Language.currentLanguageCode())
        df.dateFormat = "LLLL yyyy"
        return df.string(from: date).capitalized
    }

    private func fullDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Language.currentLanguageCode() ?? "ar")
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    private func formatShortDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: Language.currentLanguageCode())
        df.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return df.string(from: date)
    }

    private func formatTimeString(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: Language.currentLanguageCode())
        df.dateFormat = "hh:mm a"
        return df.string(from: date)
    }

    private func localizedWeekdaySymbols() -> [String] {
        let df = DateFormatter()
        df.locale = Locale(identifier: Language.currentLanguageCode())
        // Start from Saturday for Arabic culture, or calendar default
        var syms = df.shortStandaloneWeekdaySymbols ?? ["Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri"]
        // Align standard Gregorian (Sunday first) to Saturday-first if RTL
        if Language.isRTL() && syms.count == 7 {
            // Saturday is index 6 in standard Sunday-first array
            let sat = syms.removeLast()
            syms.insert(sat, at: 0)
        }
        return syms
    }

    private struct DaySlot: Identifiable {
        let id: String
        let date: Date?
    }

    private func daysInDisplayedMonth() -> [DaySlot] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentDisplayedMonth),
              let range = calendar.range(of: .day, in: .month, for: currentDisplayedMonth) else {
            return []
        }

        let firstDay = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstDay) // 1 = Sunday ... 7 = Saturday

        // Convert to Saturday-first offset if RTL
        let leadingSpaces: Int
        if Language.isRTL() {
            // Sunday = 1 -> index 1
            // Saturday = 7 -> index 0
            leadingSpaces = (firstWeekday % 7)
        } else {
            // Standard Sunday-first (0 spaces for Sunday)
            leadingSpaces = firstWeekday - 1
        }

        var slots: [DaySlot] = []

        // Blank leading slots
        for i in 0..<leadingSpaces {
            slots.append(DaySlot(id: "blank-leading-\(i)", date: nil))
        }

        // Actual days
        for day in range {
            if let dayDate = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                slots.append(DaySlot(id: "day-\(day)", date: dayDate))
            }
        }

        return slots
    }
}
