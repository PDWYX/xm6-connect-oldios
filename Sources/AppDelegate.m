#import "AppDelegate.h"
#import "ProbeViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    if ([self.window respondsToSelector:@selector(setOverrideUserInterfaceStyle:)]) {
        self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }
    ProbeViewController *vc = [[ProbeViewController alloc] init];
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];
    return YES;
}

@end