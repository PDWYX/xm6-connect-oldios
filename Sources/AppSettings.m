#import "AppSettings.h"

static NSString *const kFileLog = @"fileLogEnabled";
static NSString *const kShowLog = @"showLogEnabled";

@implementation AppSettings

+ (BOOL)fileLogEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kFileLog];
}

+ (void)setFileLogEnabled:(BOOL)value {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:kFileLog];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (BOOL)showLogEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kShowLog];
}

+ (void)setShowLogEnabled:(BOOL)value {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:kShowLog];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
