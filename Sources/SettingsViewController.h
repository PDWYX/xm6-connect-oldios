#import <UIKit/UIKit.h>

@interface SettingsViewController : UIViewController
@property (nonatomic, copy) void (^onClose)(void);
@end
