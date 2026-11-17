#import <Foundation/Foundation.h>

@interface AppSettings : NSObject
+ (BOOL)fileLogEnabled;
+ (void)setFileLogEnabled:(BOOL)value;
+ (BOOL)showLogEnabled;
+ (void)setShowLogEnabled:(BOOL)value;
@end
