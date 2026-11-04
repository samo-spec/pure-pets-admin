"""Static contract gates for the UIKit driver cockpit (no simulator required)."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "PurePetsAdmin"
COCKPIT = (ROOT / "Delivery" / "PPDriverWorkspaceViewController.m").read_text()
MANAGEMENT = (ROOT / "Features" / "Delivery" / "DeliveryListView.swift").read_text()


class DriverCockpitContractTests(unittest.TestCase):
    def test_presence_does_not_claim_to_control_dispatch(self):
        self.assertIn("availabilityDispatchLabel", COCKPIT)
        self.assertIn("Driver_Presence_Online", COCKPIT)
        self.assertIn("Driver_Dispatch_Enabled", COCKPIT)
        self.assertIn("Driver_Account_Status_Unknown", COCKPIT)

    def test_pending_fleet_actions_are_not_disabled_by_parent_card(self):
        self.assertIn("self.availabilityCard.userInteractionEnabled = hasFleet && !self.pendingCommand", COCKPIT)
        self.assertIn("[header addArrangedSubview:actionRow];", COCKPIT)
        self.assertIn("self.availabilityActionRow.hidden = hasFleet && !paused;", COCKPIT)

    def test_capacity_and_shift_blockers_are_visible_to_drivers(self):
        self.assertIn("availabilityBlockerLabel", COCKPIT)
        self.assertIn("Driver_Readiness_Capacity", COCKPIT)
        self.assertIn("Driver_Readiness_Dispatch_Fix", COCKPIT)

    def test_unverified_telemetry_is_not_shown_as_verified(self):
        self.assertNotIn('DL(@"Driver_Diag_GPS")', COCKPIT)
        self.assertNotIn('DL(@"Driver_Diag_Network")', COCKPIT)

    def test_unverified_otp_cannot_be_submitted_as_delivery_proof(self):
        self.assertIn('DFlag(proof[@"otpRequired"])', COCKPIT)
        self.assertNotIn('command[@"otp"] = otp;', COCKPIT)
        self.assertNotIn('command[@"otpVerified"] = @YES;', COCKPIT)
        self.assertIn('Driver_Proof_Assistance_Title', COCKPIT)

    def test_admin_assignment_and_account_actions_are_explained_separately(self):
        self.assertIn("Delivery_Driver_Assignment_Control_Subtitle", MANAGEMENT)
        self.assertIn("Delivery_Driver_Account_Control_Subtitle", MANAGEMENT)

    def test_dispatch_availability_counts_only_eligible_drivers(self):
        self.assertIn("driver.eligible", MANAGEMENT)
        self.assertIn("driverCanReceiveOffers(", MANAGEMENT)

    def test_contact_dispatch_uses_authoritative_qatar_hotline(self):
        self.assertIn('tel://+97459997720', COCKPIT)

    def test_proof_receiver_respects_rtl_and_bidi_isolation(self):
        self.assertIn('[Language alignmentForCurrentLanguage]', COCKPIT)
        self.assertIn(r'\u2068#%@\u2069', COCKPIT)

    def test_telemetry_beacon_respects_reduce_motion(self):
        self.assertIn('PPDriverPulseBeaconView', COCKPIT)
        self.assertIn('UIAccessibilityIsReduceMotionEnabled()', COCKPIT)


if __name__ == "__main__":
    unittest.main()
