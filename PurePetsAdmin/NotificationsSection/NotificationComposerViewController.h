//
//  NotificationComposerViewController.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 24/08/2025.
//


// NotificationComposerViewController.h
#import <UIKit/UIKit.h>
#import "XLForm.h"
#import "UserModel.h"
#import "NotificationModel.h"
@interface NotificationComposerViewController : XLFormViewController
@property (nonatomic, assign) BOOL isUpdatingTargets;

// New:
@property (nonatomic, strong) NSArray<UserModel *> *cachedUsers;
@property (nonatomic, strong) NSMutableArray<NSString *> *selectedUIDs;
@end
