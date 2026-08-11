import SwiftUI

@MainActor
struct CommandCenterView: View {
    let session: AdminSession
    @ObservedObject var router: AdminRouter
    @ObservedObject var state: CommandCenterState
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(session: AdminSession, router: AdminRouter, state: CommandCenterState) {
        self.session = session
        self.router = router
        self.state = state
    }

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        commandHeader
                        phaseContent(availableWidth: geometry.size.width)
                            .transition(.opacity)
                            .animation(
                                reduceMotion ? nil : .easeOut(duration: 0.25),
                                value: phaseAnimationKey
                            )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 30)
                }
                .background(AdminSurface.background.ignoresSafeArea())
                .refreshable { await waitForRefresh() }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .onAppear {
            state.loadIfNeeded()
            router.consumePendingRoute(session: session)
        }
    }

    private func waitForRefresh() async {
        state.refresh()
        while state.isRefreshing {
            do {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 50_000_000)
            } catch {
                break
            }
        }
    }

    private var phaseAnimationKey: Int {
        switch state.phase {
        case .idle, .loading: return 0
        case .loaded: return 1
        case .empty: return 2
        case .failed: return 3
        }
    }

    private var commandHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(Language.get("CommandCenter_Eyebrow", alter: nil))
                        .font(AdminType.captionBold)
                        .foregroundColor(AdminSurface.primary)
                        .textCase(.uppercase)
                    Text(Language.get("CommandCenter_Title", alter: nil))
                        .font(AdminType.title)
                        .foregroundColor(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button(action: state.refresh) {
                    Group {
                        if state.isRefreshing {
                            ProgressView().tint(AdminSurface.primary)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .frame(width: 44, height: 44)
                    .background(AdminSurface.control, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(state.isRefreshing)
                .accessibilityLabel(Language.get("CommandCenter_Refresh", alter: nil))
            }

            Text(session.displayName)
                .font(AdminType.calloutBold)
                .foregroundColor(AdminSurface.primaryText)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        roleMetadata
                        snapshotMetadata
                    }
                } else {
                    HStack(spacing: 10) {
                        roleMetadata
                        Spacer(minLength: 12)
                        snapshotMetadata
                    }
                }
            }
            .font(AdminType.footnote)
            .foregroundColor(AdminSurface.secondaryText)
            .accessibilityElement(children: .combine)
        }
    }

    private var roleMetadata: some View {
        Label(session.localizedRoleName, systemImage: "person.badge.shield.checkmark")
    }

    @ViewBuilder
    private var snapshotMetadata: some View {
        if let snapshot = state.currentSnapshot {
            Label(
                String(
                    format: Language.get("CommandCenter_Updated_Format", alter: nil),
                    formattedTime(snapshot.generatedAt)
                ),
                systemImage: "clock"
            )
            .accessibilityLabel(Text(Language.get("CommandCenter_Last_Updated", alter: nil)))
            .accessibilityValue(Text(formattedTime(snapshot.generatedAt)))
        } else {
            Label(Language.get("CommandCenter_Live", alter: nil), systemImage: "waveform.path.ecg")
        }
    }

    @ViewBuilder
    private func phaseContent(availableWidth: CGFloat) -> some View {
        switch state.phase {
        case .idle, .loading:
            loadingState
        case let .loaded(snapshot):
            loadedContent(snapshot, availableWidth: availableWidth)
        case let .empty(snapshot):
            emptyState(snapshot)
        case let .failed(snapshot):
            failedState(snapshot)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView().tint(AdminSurface.primary)
            Text(Language.get("CommandCenter_Loading", alter: nil))
                .font(AdminType.callout)
                .foregroundColor(AdminSurface.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AdminSurface.hairline))
        .accessibilityElement(children: .combine)
    }

    private func emptyState(_ snapshot: AdminCommandSnapshot) -> some View {
        VStack(spacing: 16) {
            ContentUnavailableCompat(
                title: Language.get("CommandCenter_Empty_Title", alter: nil),
                message: Language.get("CommandCenter_Empty_Message", alter: nil),
                symbol: "lock.shield"
            )
            Button(Language.get("Retry", alter: nil), action: state.refresh)
                .buttonStyle(.borderedProminent)
                .tint(AdminSurface.primary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(Text(snapshot.requestedAreas.isEmpty
                                ? Language.get("CommandCenter_Empty_Message", alter: nil)
                                : Language.get("Retry", alter: nil)))
    }

    private func failedState(_ snapshot: AdminCommandSnapshot) -> some View {
        VStack(spacing: 16) {
            ContentUnavailableCompat(
                title: Language.get("CommandCenter_FullFailure_Title", alter: nil),
                message: String(
                    format: Language.get("CommandCenter_FullFailure_Message_Format", alter: nil),
                    snapshot.failedAreas.map(localizedArea).joined(separator: Language.isRTL() ? "، " : ", ")
                ),
                symbol: "exclamationmark.triangle"
            )
            Button(Language.get("Retry", alter: nil), action: state.refresh)
                .buttonStyle(.borderedProminent)
                .tint(AdminSurface.primary)
        }
    }

    @ViewBuilder
    private func loadedContent(_ snapshot: AdminCommandSnapshot, availableWidth: CGFloat) -> some View {
        let showsExpandedReadout = availableWidth >= 760 && !dynamicTypeSize.isAccessibilitySize

        operationalBriefing(snapshot)

        if !snapshot.failedAreas.isEmpty {
            partialFailure(snapshot.failedAreas)
        }

        if snapshot.attentionItems.count > 1 {
            attentionSection(Array(snapshot.attentionItems.dropFirst()))
        }

        metricSection(
            titleKey: "CommandCenter_Live_Operations",
            detailKey: "CommandCenter_Live_Operations_Detail",
            metrics: operationsMetrics(snapshot.operations),
            showsExpandedReadout: showsExpandedReadout
        )
        metricSection(
            titleKey: "CommandCenter_Business_Snapshot",
            detailKey: "CommandCenter_Business_Snapshot_Detail",
            metrics: businessMetrics(snapshot.business),
            showsExpandedReadout: showsExpandedReadout
        )

        contextualActions
    }

    private func operationalBriefing(_ snapshot: AdminCommandSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .center, spacing: 10) {
                    Label(
                        Language.get("CommandCenter_Operational_State", alter: nil),
                        systemImage: healthSymbol(snapshot.health)
                    )
                    .font(AdminType.captionBold)
                    .foregroundColor(healthColor(snapshot.health))

                    Spacer(minLength: 12)

                    Text(healthCount(snapshot.health))
                        .font(AdminType.largeTitle)
                        .foregroundColor(AdminSurface.primaryText)
                        .monospacedDigit()
                }

                Text(healthTitle(snapshot.health))
                    .font(AdminType.title2)
                    .foregroundColor(AdminSurface.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(healthDetail(snapshot.health))
                    .font(AdminType.callout)
                    .foregroundColor(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            if let priorityItem = snapshot.attentionItems.first {
                Divider().overlay(healthColor(snapshot.health).opacity(0.24))
                priorityDispatch(priorityItem)
            }

            Text(Language.get("CommandCenter_Operational_Signal", alter: nil))
                .font(AdminType.footnote)
                .foregroundColor(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(AdminSurface.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(healthColor(snapshot.health).opacity(0.34)))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(healthColor(snapshot.health))
                .frame(width: 4)
                .padding(.vertical, 22)
                .accessibilityHidden(true)
        }
    }

    private func priorityDispatch(_ item: AttentionItem) -> some View {
        Button { router.present(item.route, session: session) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(severityColor(item.severity))
                        .frame(width: 34, height: 34)
                        .background(
                            severityColor(item.severity).opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                        .accessibilityHidden(true)

                    Text(Language.get("CommandCenter_Next_Move", alter: nil))
                        .font(AdminType.captionBold)
                        .foregroundColor(severityColor(item.severity))

                    Spacer(minLength: 8)

                    Text(formattedCount(item.count))
                        .font(AdminType.title2)
                        .foregroundColor(severityColor(item.severity))
                        .monospacedDigit()
                }

                Text(Language.get(item.titleKey, alter: nil))
                    .font(AdminType.headline)
                    .foregroundColor(AdminSurface.primaryText)

                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(Language.get(item.detailKey, alter: nil))
                        .font(AdminType.footnote)
                        .foregroundColor(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                        .foregroundColor(AdminSurface.primary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(Language.get(item.titleKey, alter: nil)))
        .accessibilityValue(Text(formattedCount(item.count)))
        .accessibilityHint(Language.get("CommandCenter_Open_Detail", alter: nil))
    }

    private func attentionSection(_ items: [AttentionItem]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionHeader("CommandCenter_Also_In_Queue", detailKey: "CommandCenter_Also_In_Queue_Detail")
            VStack(spacing: 0) {
                ForEach(items) { item in
                    Button { router.present(item.route, session: session) } label: {
                        attentionRow(item)
                    }
                    .buttonStyle(.plain)
                    if item.id != items.last?.id {
                        Divider().overlay(AdminSurface.hairline)
                    }
                }
            }
            .padding(.horizontal, 15)
            .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(AdminSurface.hairline))
        }
    }

    private func metricSection(
        titleKey: String,
        detailKey: String,
        metrics: [CommandMetric],
        showsExpandedReadout: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionHeader(titleKey, detailKey: detailKey)
            if metrics.isEmpty {
                ContentUnavailableCompat(
                    title: Language.get("CommandCenter_No_Metrics_Title", alter: nil),
                    message: Language.get("CommandCenter_No_Metrics_Message", alter: nil),
                    symbol: "eye.slash"
                )
            } else if showsExpandedReadout {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(metrics) { metric in
                        metricReadout(metric)
                        if metric.id != metrics.last?.id {
                            Divider().overlay(AdminSurface.hairline)
                        }
                    }
                }
                .padding(.vertical, 8)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(AdminSurface.hairline))
            } else {
                VStack(spacing: 0) {
                    ForEach(metrics) { metric in
                        Group {
                            if let route = metric.route {
                                Button { router.present(route, session: session) } label: {
                                    metricRow(metric)
                                }
                                .buttonStyle(.plain)
                            } else {
                                metricRow(metric)
                            }
                        }
                        if metric.id != metrics.last?.id {
                            Divider().overlay(AdminSurface.hairline)
                        }
                    }
                }
                .padding(.horizontal, 15)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(AdminSurface.hairline))
            }
        }
    }

    @ViewBuilder
    private func metricReadout(_ metric: CommandMetric) -> some View {
        if let route = metric.route {
            Button { router.present(route, session: session) } label: {
                metricReadoutContent(metric)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Language.get("CommandCenter_Open_Detail", alter: nil))
        } else {
            metricReadoutContent(metric)
        }
    }

    private func metricReadoutContent(_ metric: CommandMetric) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: metric.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AdminSurface.primary)
                    .accessibilityHidden(true)

                Spacer(minLength: 8)

                if metric.route != nil {
                    Image(systemName: Language.isRTL() ? "arrow.left" : "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AdminSurface.secondaryText)
                        .accessibilityHidden(true)
                }
            }

            Text(metric.value.map { formattedCount($0) } ?? Language.get("PaymentMgmt_Value_NotAvailable", alter: nil))
                .font(AdminType.largeTitle)
                .foregroundColor(AdminSurface.primaryText)
                .monospacedDigit()

            Text(Language.get(metric.titleKey, alter: nil))
                .font(AdminType.footnote)
                .foregroundColor(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func partialFailure(_ failedAreas: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .foregroundColor(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Language.get("CommandCenter_Partial_Title", alter: nil))
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(String(
                        format: Language.get("CommandCenter_Partial_Message_Format", alter: nil),
                        failedAreas.map(localizedArea).joined(separator: Language.isRTL() ? "، " : ", ")
                    ))
                    .font(AdminType.callout)
                    .foregroundColor(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button(action: state.refresh) {
                Label(Language.get("Retry", alter: nil), systemImage: "arrow.clockwise")
                    .font(AdminType.calloutBold)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(Color(uiColor: .ppWarning))
            .disabled(state.isRefreshing)
        }
        .padding(16)
        .background(Color(uiColor: .ppWarning).opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func sectionHeader(_ titleKey: String, detailKey: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Language.get(titleKey, alter: nil))
                .font(AdminType.title2)
                .foregroundColor(AdminSurface.primaryText)
                .accessibilityAddTraits(.isHeader)
            Text(Language.get(detailKey, alter: nil))
                .font(AdminType.footnote)
                .foregroundColor(AdminSurface.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func attentionRow(_ item: AttentionItem) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    attentionSymbol(item)
                    Text(Language.get(item.titleKey, alter: nil))
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(Language.get(item.detailKey, alter: nil))
                    .font(AdminType.footnote)
                    .foregroundColor(AdminSurface.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(formattedCount(item.count))
                        .font(AdminType.title2)
                        .foregroundColor(severityColor(item.severity))
                        .monospacedDigit()
                    Spacer(minLength: 8)
                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .foregroundColor(AdminSurface.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityHint(Language.get("CommandCenter_Open_Detail", alter: nil))
        } else {
            HStack(spacing: 13) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(severityColor(item.severity))
                    .frame(width: 4, height: 42)
                    .accessibilityHidden(true)

                attentionSymbol(item)

                VStack(alignment: .leading, spacing: 3) {
                    Text(Language.get(item.titleKey, alter: nil))
                        .font(AdminType.headline)
                        .foregroundColor(AdminSurface.primaryText)
                    Text(Language.get(item.detailKey, alter: nil))
                        .font(AdminType.footnote)
                        .foregroundColor(AdminSurface.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
                Text(formattedCount(item.count))
                    .font(AdminType.title2)
                    .foregroundColor(severityColor(item.severity))
                    .monospacedDigit()
                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                    .foregroundColor(AdminSurface.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityHint(Language.get("CommandCenter_Open_Detail", alter: nil))
        }
    }

    private func attentionSymbol(_ item: AttentionItem) -> some View {
        Image(systemName: item.symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(severityColor(item.severity))
            .frame(width: 34, height: 34)
            .background(
                severityColor(item.severity).opacity(0.11),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func metricRow(_ metric: CommandMetric) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    metricSymbol(metric)
                    Text(Language.get(metric.titleKey, alter: nil))
                        .font(AdminType.callout)
                        .foregroundColor(AdminSurface.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    metricValue(metric)
                    Spacer(minLength: 8)
                    if metric.route != nil {
                        Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                            .foregroundColor(AdminSurface.secondaryText)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: 13) {
                metricSymbol(metric)

                Text(Language.get(metric.titleKey, alter: nil))
                    .font(AdminType.callout)
                    .foregroundColor(AdminSurface.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                metricValue(metric)

                if metric.route != nil {
                    Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                        .foregroundColor(AdminSurface.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
    }

    private func metricSymbol(_ metric: CommandMetric) -> some View {
        Image(systemName: metric.symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(AdminSurface.primary)
            .frame(width: 34, height: 34)
            .background(
                AdminSurface.primary.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private func metricValue(_ metric: CommandMetric) -> some View {
        Text(metric.value.map { formattedCount($0) } ?? Language.get("PaymentMgmt_Value_NotAvailable", alter: nil))
            .font(AdminType.headline)
            .foregroundColor(AdminSurface.primaryText)
            .monospacedDigit()
    }

    private var contextualActions: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionHeader("CommandCenter_Contextual_Actions", detailKey: "CommandCenter_Contextual_Actions_Detail")
            let routes = contextualRoutes
            if routes.isEmpty {
                ContentUnavailableCompat(
                    title: Language.get("CommandCenter_No_Actions_Title", alter: nil),
                    message: Language.get("CommandCenter_No_Actions_Message", alter: nil),
                    symbol: "lock"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(routes) { route in
                        Button { router.present(route, session: session) } label: {
                            HStack(spacing: 13) {
                                Image(systemName: route.symbol)
                                    .foregroundColor(AdminSurface.primary)
                                    .frame(width: 34, height: 34)
                                    .background(AdminSurface.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                    .accessibilityHidden(true)
                                Text(Language.get(route.titleKey, alter: nil))
                                    .font(AdminType.calloutBold)
                                    .foregroundColor(AdminSurface.primaryText)
                                Spacer(minLength: 8)
                                Image(systemName: Language.isRTL() ? "chevron.left" : "chevron.right")
                                    .foregroundColor(AdminSurface.secondaryText)
                                    .accessibilityHidden(true)
                            }
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if route.id != routes.last?.id {
                            Divider().overlay(AdminSurface.hairline)
                        }
                    }
                }
                .padding(.horizontal, 15)
                .background(AdminSurface.control, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(AdminSurface.hairline))
            }
        }
    }

    private var contextualRoutes: [AdminRoute] {
        [.paymentSettings, .notifications, .homeControl, .audit]
            .filter { $0.isAuthorized(for: session) }
    }

    private func operationsMetrics(_ operations: OperationsSnapshot) -> [CommandMetric] {
        [
            CommandMetric(id: "orders", titleKey: "CommandCenter_Metric_Active_Orders", value: operations.activeOrders, symbol: "creditcard", route: .payments),
            CommandMetric(id: "fulfillment", titleKey: "CommandCenter_Metric_Awaiting_Fulfillment", value: operations.awaitingFulfillment, symbol: "shippingbox", route: .fulfillment),
            CommandMetric(id: "delivery", titleKey: "CommandCenter_Metric_Active_Deliveries", value: operations.activeDeliveries, symbol: "truck.box", route: .delivery),
            CommandMetric(id: "providers", titleKey: "CommandCenter_Metric_Pending_Providers", value: operations.pendingProviderApplications, symbol: "person.badge.clock", route: .providerApplications),
        ].filter { metric in
            if metric.id == "orders" {
                return session.hasAnyPermission(["payments.view", "payments.manage", "payments.refund", "accounting.manage"])
            }
            if metric.id == "fulfillment" {
                return session.hasAnyPermission(["payments.view", "payments.manage"])
            }
            if metric.id == "delivery" {
                return session.hasPermission("payments.manage") || session.hasGlobalScope
            }
            guard let route = metric.route else { return true }
            return route.isAuthorized(for: session)
        }
    }

    private func businessMetrics(_ business: BusinessSnapshot) -> [CommandMetric] {
        [
            CommandMetric(id: "listings", titleKey: "CommandCenter_Metric_Listings", value: business.listings, symbol: "list.bullet.clipboard", route: .listings),
            CommandMetric(id: "users", titleKey: "CommandCenter_Metric_Users", value: business.users, symbol: "person.2", route: .users),
            CommandMetric(id: "stock", titleKey: "CommandCenter_Metric_Accessories", value: business.accessories, symbol: "shippingbox", route: .accessories),
        ].filter { metric in
            if metric.id == "users" {
                return session.hasAnyPermission(["users.view", "users.manage"])
            }
            if metric.id == "stock" {
                return session.hasAnyPermission(["stock.view", "stock.manage"])
            }
            guard let route = metric.route else { return true }
            return route.isAuthorized(for: session)
        }
    }

    private func healthTitle(_ health: OperationalHealth) -> String {
        switch health {
        case .stable: return Language.get("CommandCenter_Health_Stable", alter: nil)
        case .attention: return Language.get("CommandCenter_Health_Attention", alter: nil)
        case .partial: return Language.get("CommandCenter_Health_Partial", alter: nil)
        }
    }

    private func healthDetail(_ health: OperationalHealth) -> String {
        switch health {
        case .stable:
            return Language.get("CommandCenter_Health_Stable_Detail", alter: nil)
        case let .attention(count):
            return String(format: Language.get("CommandCenter_Health_Attention_Format", alter: nil), formattedCount(count))
        case let .partial(count):
            return String(format: Language.get("CommandCenter_Health_Partial_Format", alter: nil), formattedCount(count))
        }
    }

    private func healthCount(_ health: OperationalHealth) -> String {
        switch health {
        case .stable: return formattedCount(0)
        case let .attention(count), let .partial(count): return formattedCount(count)
        }
    }

    private func healthSymbol(_ health: OperationalHealth) -> String {
        switch health {
        case .stable: return "checkmark.shield.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .partial: return "arrow.triangle.2.circlepath"
        }
    }

    private func healthColor(_ health: OperationalHealth) -> Color {
        switch health {
        case .stable: return Color(uiColor: .ppSuccess)
        case .attention: return Color(uiColor: .ppWarning)
        case .partial: return AdminSurface.primary
        }
    }

    private func severityColor(_ severity: AttentionSeverity) -> Color {
        switch severity {
        case .critical: return Color(uiColor: .ppError)
        case .actionRequired: return Color(uiColor: .ppWarning)
        case .watch: return Color(uiColor: .ppInfo)
        case .normal: return Color(uiColor: .ppSuccess)
        }
    }

    private func localizedArea(_ area: String) -> String {
        Language.get("CommandCenter_Area_\(area)", alter: area)
    }

    private func formattedCount(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    private func formattedTime(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(locale))
    }
}
