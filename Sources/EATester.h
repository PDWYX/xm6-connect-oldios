#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EATester : NSObject
@property (nonatomic, copy) void (^logger)(NSString *line);
@property (nonatomic, copy) void (^stateHandler)(int mode, int level); // mode: 0=off 1=NC 2=AMB
@property (nonatomic, readonly) BOOL connected;
- (void)begin;
- (void)openSession;
- (void)setAmbient:(uint8_t)level commit:(BOOL)commit;
- (void)setNCWithLevel:(uint8_t)level;
- (void)setOffWithLevel:(uint8_t)level;
@end

NS_ASSUME_NONNULL_END
