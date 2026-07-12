#!/usr/bin/env python3
"""
Fix SceneDelegate.m — replace startFlowForAuthUser: method
with Firebase Auth fallback + login-in-progress guard.
Run: python3 fix_scene_delegate.py
"""
import os

FILE = os.path.join(os.path.dirname(__file__), "PurePetsAdmin", "SceneDelegate.m")

with open(FILE, "r", encoding="utf-8") as f:
    content = f.read()

# ── Fix 1: Replace the startFlowForAuthUser: method body ──
# Find the method signature (unique in active code)
METHOD_SIG = "- (void)startFlowForAuthUser:(FIRUser * _Nullable)user userModel:(UserModel * _Nullable)userModel animated:(BOOL)animated {"
END_MARKER = "#pragma mark - Root switching"

start = content.find(METHOD_SIG)
end = content.find(END_MARKER, start)

if start == -1 or end == -1:
    print("ERROR: Could not locate startFlowForAuthUser: method")
    exit(1)

NEW_METHOD = """- (void)startFlowForAuthUser:(FIRUser * _Nullable)user userModel:(UserModel * _Nullable)userModel animated:(BOOL)animated {
     if (!user) {
          self.awaitingModel = NO;
          [self setRoot:AppRootLogin animated:animated];
          return;
     }
     
     self.awaitingModel = YES;
     [self setRoot:AppRootSplash animated:animated];
     
     __weak typeof(self) weakSelf = self;
     [UserManager.shared loadUserByUIDOrID:user.uid completion:^(UserModel * _Nullable loadedUser, NSError * _Nullable error) {
          
          weakSelf.awaitingModel = NO;
          UserModel *effectiveUser = loadedUser;

          // Fallback: build minimal UserModel from Firebase Auth data.
          // Mirrors Console approach: staff_users is the auth source,
          // UsersCol doc is optional (created asynchronously by ensureUserDoc).
          if (!effectiveUser) {
               FIRUser *authUser = [FIRAuth auth].currentUser;
               if (authUser) {
                    NSLog(@"[SceneDelegate] UsersCol doc not found — building from Firebase Auth");
                    effectiveUser = [[FUManager shared] userModelFromAuth:authUser doc:nil];
               }
          }

          if (effectiveUser) {
               UserManager.shared.currentUser = effectiveUser;
               [weakSelf setRoot:AppRootDashboard animated:YES];
               [weakSelf pp_tryHandlePendingPaymentOrderRouteAnimated:NO];
          } else {
               [weakSelf setRoot:AppRootLogin animated:YES];
          }
     }];
}

"""

content = content[:start] + NEW_METHOD + content[end:]

# ── Fix 2: Ensure login-in-progress guard is in pp_applyAdminRoutingForAuthUser: ──
# (Already added by edit tool — verify it exists)
if "PPAdminLoginInProgress()" not in content:
    print("WARNING: login-in-progress guard not found. Was it already added?")

# ── Write back ──
with open(FILE, "w", encoding="utf-8") as f:
    f.write(content)

print(f"SUCCESS: Patched {FILE}")
print("  - startFlowForAuthUser: now has Firebase Auth fallback")
print("  - Login-in-progress guard should already be in place")
