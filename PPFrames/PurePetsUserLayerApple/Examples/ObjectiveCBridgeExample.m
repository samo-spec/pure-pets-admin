@import PurePetsUserKit;
#import "PurePets-Swift.h"

// Composition root owns this object strongly.
// self.currentUserBridge = [[PPCurrentUserBridge alloc] initWithSession:session];
// [self.currentUserBridge start];

BOOL canOpenChat = [self.currentUserBridge isAllowed:PPObjCUserCapabilityUseChat];
if (!canOpenChat) {
    NSString *reason = [self.currentUserBridge denialReasonCodeFor:PPObjCUserCapabilityUseChat];
    NSLog(@"Chat denied: %@", reason);
}
