#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EATester : NSObject
@property (nonatomic, copy) void (^logger)(NSString *line);
- (void)begin;
- (void)showPicker;
- (void)openSession;
- (void)sendTest;
- (void)sendAmbient:(int)level;
- (void)sendNC;
@end

NS_ASSUME_NONNULL_END
