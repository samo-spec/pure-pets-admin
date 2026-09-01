//
//  main.m
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 20/08/2025.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import <sys/utsname.h>

static NSString *PPAdminDeviceModelString(void) {
    struct utsname systemInfo;
    if (uname(&systemInfo) != 0) {
        return UIDevice.currentDevice.model ?: @"Unknown";
    }
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding] ?: @"Unknown";
}

int main(int argc, char * argv[]) {
    NSString * appDelegateClassName;
    @autoreleasepool {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        formatter.timeZone = [NSTimeZone localTimeZone];
        NSString *timestamp = [formatter stringFromDate:[NSDate date]];
        
        NSLog(@"\n"
              @"=========================================================================\n"
              @"🚀 [PPADMIN LAUNCH] PurePets Admin Binary Process Bootstrap\n"
              @"=========================================================================\n"
              @"   ⏰ Timestamp    : %@\n"
              @"   🆔 Process ID   : %d\n"
              @"   📱 Device Model : %@\n"
              @"   ⚙️  OS Version   : iOS %@\n"
              @"   🏗️  Build Config : %@\n"
              @"=========================================================================",
              timestamp,
              getpid(),
              PPAdminDeviceModelString(),
              UIDevice.currentDevice.systemVersion,
#if DEBUG
              @"DEBUG (Development)"
#else
              @"RELEASE (Production)"
#endif
        );
        
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
    }
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}
