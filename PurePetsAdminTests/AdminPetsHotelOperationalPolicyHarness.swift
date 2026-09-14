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
            "status": "available"
        ])
        precondition(verdict?.accommodationId == "room-b103")
        precondition(verdict?.rejections == ["species_not_allowed", "capacity_exceeded"])
        precondition(verdict?.isAssignable == false)
        precondition(verdict?.remainingCapacity == 0)
        print("Admin Hotel operational policy harness passed")
    }
}
