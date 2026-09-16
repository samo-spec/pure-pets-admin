import Foundation

@main
struct AdminPetsHotelOperationalPolicyHarness {
    static func main() {
        precondition(AdminHotelSpeciesPolicy.defaultSpecies(forWingRawValue: "birds") == ["bird"])
        precondition(AdminHotelSpeciesPolicy.defaultSpecies(forWingRawValue: "small_pets") == ["small_pets"])
        precondition(AdminHotelSpeciesPolicy.defaultSpecies(forWingRawValue: "isolation").isEmpty)
        precondition(AdminHotelCustomerIdentityPolicy.resolvedCustomerUid(providedUid: "guest-local", lookedUpUid: nil) == nil)
        precondition(AdminHotelCustomerIdentityPolicy.resolvedCustomerUid(providedUid: "", lookedUpUid: "real-user") == "real-user")
        precondition(AdminHotelCustomerIdentityPolicy.resolvedCustomerUid(providedUid: "real-user", lookedUpUid: nil) == "real-user")

        precondition(AdminHotelRatePolicy.resolvedNightlyRate(unitRateMinor: nil, typeRateMinor: 3500) == 3500)
        precondition(AdminHotelRatePolicy.resolvedNightlyRate(unitRateMinor: 4200, typeRateMinor: 3500) == 4200)
        precondition(AdminHotelRatePolicy.resolvedNightlyRate(unitRateMinor: nil, typeRateMinor: nil) == nil)

        let billingProjection = AdminHotelBillingProjectionPolicy.resolve([
            "pricing": ["quotedTotalMinor": NSNumber(value: 12500), "depositMinor": NSNumber(value: 2500)],
            "billingSummary": ["grandTotalMinor": NSNumber(value: 13000), "settledMinor": NSNumber(value: 5000)]
        ])
        precondition(billingProjection.totalMinor == 13000)
        precondition(billingProjection.settledMinor == 5000)
        precondition(billingProjection.depositMinor == 2500)

        // Pre-arrival / check-in where billingSummary is not yet settled (grandTotalMinor is 0)
        let preCheckInProjection = AdminHotelBillingProjectionPolicy.resolve([
            "pricing": ["quotedTotalMinor": NSNumber(value: 245000), "depositMinor": NSNumber(value: 0)],
            "billingSummary": ["grandTotalMinor": NSNumber(value: 0), "settledMinor": NSNumber(value: 0)]
        ])
        precondition(preCheckInProjection.totalMinor == 245000)
        precondition(preCheckInProjection.settledMinor == 0)

        // Pre-arrival reservation with deposit paid (depositMinor in pricing, billingSummary not yet populated, paymentStatus is deposit_held)
        let depositHeldProjection = AdminHotelBillingProjectionPolicy.resolve([
            "pricing": ["quotedTotalMinor": NSNumber(value: 45000), "depositMinor": NSNumber(value: 10000)],
            "billingSummary": ["grandTotalMinor": NSNumber(value: 0), "settledMinor": NSNumber(value: 0), "depositMinor": NSNumber(value: 0)],
            "paymentStatus": "deposit_held"
        ])
        precondition(depositHeldProjection.totalMinor == 45000)
        precondition(depositHeldProjection.depositMinor == 10000)
        precondition(depositHeldProjection.settledMinor == 10000)

        // In-house reservation with deposit where child stay ledger settledMinor is not yet rolled up
        let inHouseDepositProjection = AdminHotelBillingProjectionPolicy.resolve([
            "pricing": ["quotedTotalMinor": NSNumber(value: 45000), "depositMinor": NSNumber(value: 11200)],
            "billingSummary": ["grandTotalMinor": NSNumber(value: 45000), "settledMinor": NSNumber(value: 0), "depositMinor": NSNumber(value: 0)],
            "paymentStatus": "in_house"
        ])
        precondition(inHouseDepositProjection.totalMinor == 45000)
        precondition(inHouseDepositProjection.depositMinor == 11200)
        precondition(inHouseDepositProjection.settledMinor == 11200)

        let checkInOnly = AdminHotelPermissionPolicy.resolve(["hotel.view", "hotel.checkin"])
        precondition(checkInOnly.canViewHotel)
        precondition(checkInOnly.canCheckIn)
        precondition(checkInOnly.canCheckOut == false)
        precondition(checkInOnly.canViewCare == false)
        precondition(checkInOnly.canManageBilling == false)

        let billingViewer = AdminHotelPermissionPolicy.resolve(["hotel.view", "hotel.billing.view"])
        precondition(billingViewer.canViewBilling)
        precondition(billingViewer.canManageBilling == false)
        precondition(AdminHotelReservationActionPolicy.requiredPermission(for: "cancel_reservation") == "hotel.reservations.manage")
        precondition(AdminHotelReservationActionPolicy.requiredPermission(for: "mark_no_show") == "hotel.reservations.manage")
        precondition(AdminHotelReservationActionPolicy.requiredPermission(for: "complete_reservation") == "hotel.billing.manage")
        precondition(AdminHotelReservationActionPolicy.requiredPermission(for: "unexpected") == nil)
        precondition(AdminHotelReservationUpdatePolicy.identity(petId: "", species: "dog") == nil)
        precondition(AdminHotelReservationUpdatePolicy.identity(petId: "pet-1", species: "") == nil)
        precondition(AdminHotelReservationUpdatePolicy.identity(petId: " pet-1 ", species: " Bird ") == .init(petId: "pet-1", species: "bird"))

        let missingDiet = AdminHotelCheckInReadinessPolicy.evaluate(
            hasAuthoritativeStay: true,
            petIdentityVerified: true,
            vaccinationVerified: true,
            healthInspectionCompleted: true,
            dietConfirmed: false,
            emergencyContactConfirmed: true,
            agreementAcknowledged: true,
            medicationRequired: false,
            medicationConfirmed: false,
            depositRequired: false,
            depositSettled: false
        )
        precondition(missingDiet.isComplete == false)
        precondition(missingDiet.missingRequirementCodes == ["diet_allergy_confirmation"])
        precondition(missingDiet.completedCount == 5)
        precondition(missingDiet.totalCount == 6)

        let verdict = AdminHotelAvailabilityUnit.fromDictionary([
            "accommodationId": "room-b103",
            "assignable": false,
            "rejections": ["species_not_allowed", "capacity_exceeded"],
            "remainingInWindow": 0,
            "status": "available",
            "isReservedForThisStay": true,
            "allowedMainKindIds": [1, 2]
        ])
        precondition(verdict?.accommodationId == "room-b103")
        precondition(verdict?.rejections == ["species_not_allowed", "capacity_exceeded"])
        precondition(verdict?.isAssignable == false)
        precondition(verdict?.remainingCapacity == 0)
        precondition(verdict?.isReservedForThisStay == true)
        precondition(verdict?.allowedMainKindIds == [1, 2])

        // Structured availability snapshot with exactType and compatible alternatives
        let snapshot = AdminHotelAvailabilitySnapshot.fromDictionary([
            "units": [
                [
                    "accommodationId": "suite-101",
                    "accommodationTypeId": "type-cat-std",
                    "assignable": true,
                    "isReservedForThisStay": true,
                    "allowedMainKindIds": [2]
                ]
            ],
            "exactTypeAssignable": [
                [
                    "accommodationId": "suite-101",
                    "accommodationTypeId": "type-cat-std",
                    "assignable": true,
                    "isReservedForThisStay": true,
                    "allowedMainKindIds": [2]
                ]
            ],
            "exactTypeRejected": [],
            "compatibleAlternativeTypes": [
                [
                    "accommodationTypeId": "type-cat-vip",
                    "nameAr": "جناح القطط الملكي",
                    "nameEn": "Royal Cat Suite",
                    "wing": "cats",
                    "nightlyRateMinor": 4500,
                    "rateDeltaMinor": 1000,
                    "assignableUnits": [
                        [
                            "accommodationId": "suite-vip-1",
                            "accommodationTypeId": "type-cat-vip",
                            "assignable": true,
                            "allowedMainKindIds": [2]
                        ]
                    ]
                ]
            ]
        ])
        precondition(snapshot != nil)
        precondition(snapshot?.assignableUnits.count == 1)
        precondition(snapshot?.assignableUnits.first?.isReservedForThisStay == true)
        precondition(snapshot?.compatibleAlternativeTypes.count == 1)
        precondition(snapshot?.compatibleAlternativeTypes.first?.rateDeltaMinor == 1000)
        precondition(snapshot?.compatibleAlternativeTypes.first?.assignableUnits.count == 1)

        // Diagnostics
        let diag = AdminHotelDiagnostics.fromDictionary([
            "branchId": "branch-main",
            "hasBranchSettings": true,
            "hasAccommodationTypes": false,
            "hasPhysicalUnits": false,
            "totalTypesCount": 0,
            "totalUnitsCount": 0,
            "isReadyForOperations": false,
            "blockers": ["NO_ACCOMMODATION_TYPES", "NO_PHYSICAL_UNITS"]
        ])
        precondition(diag != nil)
        precondition(diag?.needsSetup == true)
        precondition(diag?.isReady == false)
        precondition(diag?.blockers.count == 2)

        // Reprice policy
        precondition(AdminHotelRepricePolicy.requiresConfirmation(rateDeltaMinor: 1000) == true)
        precondition(AdminHotelRepricePolicy.requiresConfirmation(rateDeltaMinor: 0) == false)
        precondition(AdminHotelRepricePolicy.formattedDelta(rateDeltaMinor: 1500) == "+15 QAR")
        precondition(AdminHotelRepricePolicy.formattedDelta(rateDeltaMinor: -500) == "-5 QAR")

        // Dominant Reason Policy
        precondition(AdminHotelDominantReasonPolicy.dominantReason(from: ["main_kind_not_allowed", "unit_out_of_service"]) == "main_kind_not_allowed")
        precondition(AdminHotelDominantReasonPolicy.dominantReason(from: ["unit_out_of_service", "capacity_exceeded"]) == "unit_out_of_service")
        precondition(!AdminHotelDominantReasonPolicy.localizedReason(for: "main_kind_not_allowed").isEmpty)

        print("Admin Hotel operational policy harness passed")
    }
}
