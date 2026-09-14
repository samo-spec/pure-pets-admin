import XCTest
@testable import PurePetsAdmin

final class AdminPetsHotelDomainPolicyTests: XCTestCase {
    func testBirdWingDefaultsToBirdSpecies() {
        XCTAssertEqual(AdminHotelSpeciesPolicy.defaultSpecies(forWingRawValue: HotelWing.birds.rawValue), ["bird"])
    }

    func testSmallPetsWingDefaultsToSmallPetsSpecies() {
        XCTAssertEqual(AdminHotelSpeciesPolicy.defaultSpecies(forWingRawValue: HotelWing.smallPets.rawValue), ["small_pets"])
    }

    func testGuestIdentityFailsClosedInsteadOfSubstitutingAnotherCustomer() {
        XCTAssertNil(AdminHotelCustomerIdentityPolicy.resolvedCustomerUid(providedUid: "guest-local", lookedUpUid: nil))
        XCTAssertEqual(AdminHotelCustomerIdentityPolicy.resolvedCustomerUid(providedUid: "", lookedUpUid: "real-user"), "real-user")
    }

    func testAvailabilityVerdictPreservesBackendRejections() {
        let verdict = AdminHotelAvailabilityUnit.fromDictionary([
            "accommodationId": "room-b103",
            "assignable": false,
            "rejections": ["species_not_allowed", "capacity_exceeded"],
            "remainingInWindow": 0,
            "status": "available"
        ])

        XCTAssertEqual(verdict?.accommodationId, "room-b103")
        XCTAssertEqual(verdict?.rejections, ["species_not_allowed", "capacity_exceeded"])
        XCTAssertEqual(verdict?.isAssignable, false)
        XCTAssertEqual(verdict?.remainingCapacity, 0)
    }
}
