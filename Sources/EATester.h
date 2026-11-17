#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EATester : NSObject
@property (nonatomic, copy) void (^logger)(NSString *line);
- (void)begin;
- (void)showPicker;
- (void)openSession;
- (void)sendLinkSync;
- (void)sendInit;
- (void)sendAmbient:(int)level;
- (void)sendNC;
- (void)sendOff;
- (void)sendWrappedInit;
@end

NS_ASSUME_NONNULL_END
