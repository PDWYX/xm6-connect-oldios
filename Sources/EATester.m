#import "EATester.h"
#import <UIKit/UIKit.h>
#import <ExternalAccessory/ExternalAccessory.h>
#import "AppSettings.h"

static NSString *const kSonyProtocol = @"jp.co.sony.songpal.mdr.link2";

static NSString *EAHex(NSData *d) {
    if (d.length == 0) return @"(empty)";
    const uint8_t *p = d.bytes;
    NSMutableString *s = [NSMutableString stringWithCapacity:d.length * 3];
    for (NSUInteger i = 0; i < d.length; i++) [s appendFormat:@"%02X ", p[i]];
    return s;
}

// MDR v2: 3E | type | seq(1) | len(4 BE) | payload | checksum | 3C
static NSData *MDRFrame(uint8_t type, uint8_t seq, NSData *payload) {
    NSMutableData *d = [NSMutableData data];
    uint8_t head[2] = {0x3E, type};
    [d appendBytes:head length:2];
    [d appendBytes:&seq length:1];
    uint32_t len = (uint32_t)payload.length;
    uint8_t l[4] = { (uint8_t)(len >> 24), (uint8_t)(len >> 16), (uint8_t)(len >> 8), (uint8_t)len };
    [d appendBytes:l length:4];
    [d appendData:payload];
    uint8_t sum = 0;
    const uint8_t *p = d.bytes;
    for (NSUInteger i = 1; i < d.length; i++) sum = (uint8_t)(sum + p[i]);
    uint8_t ck = sum, end = 0x3C;
    [d appendBytes:&ck length:1];
    [d appendBytes:&end length:1];
    return d;
}

@interface EATester () <NSStreamDelegate>
@property (nonatomic, strong) EAAccessory *accessory;
@property (nonatomic, strong) EASession *session;
@property (nonatomic, strong) NSMutableData *rxBuf;
@property (nonatomic, strong) NSFileHandle *logFile;
@property (nonatomic, strong) NSDateFormatter *df;
@property (nonatomic) BOOL connNotified;
@property (nonatomic, strong) NSTimer *bootstrapTimer;
@property (nonatomic) int bootstrapTries;
@property (nonatomic) BOOL linkReady;
@property (nonatomic) BOOL appActive;
@property (nonatomic) int reopenTries;
- (void)queryState;
- (void)sendBootstrap;
- (void)scheduleReopen;
@property (nonatomic) uint8_t seq;
@property (nonatomic, strong) NSMutableData *outQueue;
@property (nonatomic) BOOL outOpened;
@property (nonatomic) BOOL bootstrapSent;
@property (nonatomic) BOOL handshakeReplied;
@property (nonatomic, strong) NSTimer *previewTimer;
@property (nonatomic) int pendingPreview;
@property (nonatomic, strong) NSTimer *resendTimer;
@property (nonatomic) int resendCount;
@property (nonatomic, strong) NSData *lastCommit;
@property (nonatomic) int lastCommitMode;
@property (nonatomic, strong) NSDate *lastTxTime;
@end

@implementation EATester

- (BOOL)connected { return self.session != nil && self.session.outputStream.streamStatus == NSStreamStatusOpen; }

- (void)log:(NSString *)fmt, ... {
    va_list args;
    va_start(args, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    if (![AppSettings showLogEnabled] && ![AppSettings fileLogEnabled]) return;
    if (self.logger) self.logger(s);
    if ([AppSettings fileLogEnabled]) [self fileLog:s];
}

- (void)fileLog:(NSString *)s {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *path = [docs stringByAppendingPathComponent:@"xm6.log"];
    if (self.logFile == nil) {
        if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:nil];
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
        if ([attrs fileSize] > 1024 * 1024) {
            [fm removeItemAtPath:path error:nil];
            [fm createFileAtPath:path contents:nil attributes:nil];
        }
        self.logFile = [NSFileHandle fileHandleForWritingAtPath:path];
        [self.logFile seekToEndOfFile];
    }
    if (self.df == nil) {
        self.df = [[NSDateFormatter alloc] init];
        self.df.dateFormat = @"HH:mm:ss";
    }
    NSString *line = [NSString stringWithFormat:@"[%@] EA %@\n", [self.df stringFromDate:[NSDate date]], s];
    [self.logFile writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)begin {
    if (!self.rxBuf) self.rxBuf = [NSMutableData data];
    if (!self.outQueue) self.outQueue = [NSMutableData data];
    self.pendingPreview = -1;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(accConnected:) name:EAAccessoryDidConnectNotification object:nil];
    [nc addObserver:self selector:@selector(accDisconnected:) name:EAAccessoryDidDisconnectNotification object:nil];
    [[EAAccessoryManager sharedAccessoryManager] registerForLocalNotifications];
    self.appActive = YES;
    [nc addObserver:self selector:@selector(appDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(appWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];

    NSArray *accs = [[EAAccessoryManager sharedAccessoryManager] connectedAccessories];
    [self log:@"已连接配件: %lu", (unsigned long)accs.count];
    if (accs.count) { self.accessory = accs.firstObject; [self openSession]; }
}

- (void)accConnected:(NSNotification *)n {
    EAAccessory *a = n.userInfo[EAAccessoryKey];
    [self log:@"配件接入: %@", a.name];
    self.accessory = a;
    // 刚接入时耳机链路还没就绪，立即开会话会导致 INIT 丢进黑洞，稍等再开
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(openSession) object:nil];
    [self performSelector:@selector(openSession) withObject:nil afterDelay:1.2];
}

- (void)accDisconnected:(NSNotification *)n {
    EAAccessory *a = n.userInfo[EAAccessoryKey];
    [self log:@"配件断开: %@", a.name];
    if (a.connectionID == self.accessory.connectionID) {
        [self closeSession];
        self.accessory = nil;
    }
}

// iOS 会在 App 进入后台时把 EA 会话拆掉，回前台拿到的是一对已经死掉的流。
// 所以回前台/流结束/流错误都走这里：自动重开会话，而不是让用户手点重新连接。
- (void)scheduleReopen {
    if (!self.appActive) { [self log:@"在后台，暂不重开"]; return; }
    if (!self.accessory) {
        NSArray *accs = [[EAAccessoryManager sharedAccessoryManager] connectedAccessories];
        if (accs.count) self.accessory = accs.firstObject;
    }
    if (!self.accessory) { [self log:@"没有配件可重开"]; return; }
    if (self.reopenTries >= 8) { [self log:@"重开次数过多，停止"]; return; }
    self.reopenTries++;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(openSession) object:nil];
    [self performSelector:@selector(openSession) withObject:nil afterDelay:0.8];
}

- (void)appWillResignActive:(NSNotification *)n {
    [self log:@"进入后台"];
    self.appActive = NO;
}

- (void)appDidBecomeActive:(NSNotification *)n {
    [self log:@"回到前台"];
    self.appActive = YES;
    self.reopenTries = 0;
    if (!self.accessory) {
        NSArray *accs = [[EAAccessoryManager sharedAccessoryManager] connectedAccessories];
        if (accs.count) self.accessory = accs.firstObject;
    }
    if (!self.accessory) return;
    BOOL dead = (self.session == nil);
    if (!dead) {
        NSStreamStatus s = self.session.inputStream.streamStatus;
        if (s == NSStreamStatusClosed || s == NSStreamStatusError || s == NSStreamStatusNotOpen) dead = YES;
    }
    if (dead) { [self log:@"会话已失效，自动重开"]; [self scheduleReopen]; }
}

- (void)openSession {
    if (self.session) {
        [[self.session inputStream] close];
        [[self.session outputStream] close];
        self.session = nil;
    }
    if (!self.accessory) {
        NSArray *accs = [[EAAccessoryManager sharedAccessoryManager] connectedAccessories];
        if (accs.count) self.accessory = accs.firstObject;
    }
    if (!self.accessory) { [self log:@"没有配件"]; return; }
    NSString *proto = nil;
    for (NSString *p in self.accessory.protocolStrings) if ([p isEqualToString:kSonyProtocol]) proto = p;
    if (!proto) proto = self.accessory.protocolStrings.firstObject;
    self.session = [[EASession alloc] initWithAccessory:self.accessory forProtocol:proto];
    if (!self.session) { [self log:@"EASession 创建失败"]; return; }
    self.reopenTries = 0;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(openSession) object:nil];
    self.rxBuf.length = 0;
    self.seq = 0;
    NSInputStream *in = self.session.inputStream;
    NSOutputStream *out = self.session.outputStream;
    in.delegate = self; out.delegate = self;
    [in scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [out scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outQueue setLength:0];
    self.outOpened = NO;
    self.bootstrapSent = NO;
    self.handshakeReplied = NO;
    self.linkReady = NO;
    self.bootstrapTries = 0;
    [self.bootstrapTimer invalidate];
    self.bootstrapTimer = nil;
    self.seq = 0;
    [in open];
    [out open];
    [self log:@"会话已打开 %@", proto];
    [self notifyConnected:YES];
}

- (void)notifyConnected:(BOOL)c {
    if (self.connNotified == c) return;
    self.connNotified = c;
    if (self.connectionHandler) self.connectionHandler(c);
}

- (void)closeSession {
    [self.previewTimer invalidate]; self.previewTimer = nil;
    [self.resendTimer invalidate]; self.resendTimer = nil;
    self.pendingPreview = -1;
    self.outOpened = NO;
    if (self.outQueue) [self.outQueue setLength:0];
    [self notifyConnected:NO];
    if (self.session) {
        [[self.session inputStream] close];
        [[self.session outputStream] close];
        self.session = nil;
    }
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)event {
    if (event == NSStreamEventOpenCompleted && stream == self.session.outputStream) {
        self.outOpened = YES;
        [self log:@"输出流就绪"];
        [self pump];
        if (!self.bootstrapSent) {
            self.bootstrapSent = YES;
            [self sendBootstrap];
        }
        return;
    }
    if (event == NSStreamEventHasSpaceAvailable) {
        [self pump];
        return;
    }
    if (event == NSStreamEventHasBytesAvailable && stream == self.session.inputStream) {
        uint8_t buf[2048];
        NSInteger n = [(NSInputStream *)stream read:buf maxLength:sizeof(buf)];
        if (n > 0) {
            [self.rxBuf appendData:[NSData dataWithBytes:buf length:(NSUInteger)n]];
            [self parseFrames];
        }
    } else if (event == NSStreamEventErrorOccurred) {
        [self log:@"流错误: %@", stream.streamError.localizedDescription];
        [self notifyConnected:NO];
        [self scheduleReopen];
    } else if (event == NSStreamEventEndEncountered) {
        [self log:@"流结束"];
        [self notifyConnected:NO];
        [self scheduleReopen];
    }
}

- (NSData *)frameOfType:(uint8_t)type payload:(NSData *)payload {
    NSData *f = MDRFrame(type, self.seq, payload);
    self.seq ^= 1;
    return f;
}

- (void)pump {
    NSOutputStream *out = self.session.outputStream;
    if (!out) return;
    if (!self.outOpened && out.streamStatus != NSStreamStatusOpen) return;
    while (self.outQueue.length > 0) {
        if (![out hasSpaceAvailable]) return;
        NSInteger n = [out write:self.outQueue.bytes maxLength:self.outQueue.length];
        if (n <= 0) return;
        [self.outQueue replaceBytesInRange:NSMakeRange(0, (NSUInteger)n) withBytes:NULL length:0];
    }
}

- (void)writeRaw:(NSData *)d label:(NSString *)label {
    if (!self.session) return;
    if (self.outQueue.length > 2048) {
        [self log:@"队列积压，丢弃"];
        [self.outQueue setLength:0];
    }
    [self.outQueue appendData:d];
    self.lastTxTime = [NSDate date];
    [self pump];
}

- (void)sendBootstrap {
    [self writeFrameType:0x0C payload:[NSData dataWithBytes:(uint8_t[]){0x00,0x00} length:2] label:@"INIT"];
    [self.bootstrapTimer invalidate];
    self.bootstrapTimer = [NSTimer scheduledTimerWithTimeInterval:1.5 target:self selector:@selector(bootstrapTick) userInfo:nil repeats:NO];
}

- (void)bootstrapTick {
    if (!self.session) return;
    if (self.linkReady) return;
    if (self.bootstrapTries >= 4) {
        [self log:@"耳机无响应，放弃 INIT"];
        return;
    }
    self.bootstrapTries++;
    [self log:@"链路未就绪，重发 INIT (%d)", self.bootstrapTries];
    [self sendBootstrap];
}

- (void)writeFrameType:(uint8_t)type payload:(NSData *)payload label:(NSString *)label {
    if (!self.session) return;
    NSData *f = [self frameOfType:type payload:payload];
    [self log:@"TX %@ %@", label, EAHex(payload)];
    [self writeRaw:f label:label];
}

- (void)sendAck:(uint8_t)seq {
    uint8_t ackSeq = (uint8_t)((seq + 1) & 0x01);
    NSData *f = MDRFrame(0x01, ackSeq, [NSData data]);
    [self writeRaw:f label:@"ACK"];
}

- (void)parseFrames {
    while (self.rxBuf.length >= 8) {
        const uint8_t *p = self.rxBuf.bytes;
        if (p[0] != 0x3E) {
            [self.rxBuf setLength:0];
            return;
        }
        uint32_t len = ((uint32_t)p[3] << 24) | ((uint32_t)p[4] << 16) | ((uint32_t)p[5] << 8) | p[6];
        if (len > 4096) { [self.rxBuf setLength:0]; return; }
        NSUInteger total = 7 + len + 2;
        if (self.rxBuf.length < total) return;
        uint8_t type = p[1], fseq = p[2];
        if (!self.linkReady) {
            self.linkReady = YES;
            [self.bootstrapTimer invalidate];
            self.bootstrapTimer = nil;
            [self log:@"链路就绪"];
        }
        NSData *payload = [self.rxBuf subdataWithRange:NSMakeRange(7, len)];
        [self.rxBuf replaceBytesInRange:NSMakeRange(0, total) withBytes:NULL length:0];
        if (type == 0x01) continue;  // 对端 ACK
        [self sendAck:fseq];
        [self handleType:type payload:payload];
    }
}

- (void)queryState {
    if (!self.session) return;
    [self writeFrameType:0x0C payload:[NSData dataWithBytes:(uint8_t[]){0x66,0x19} length:2] label:@"GET-STATE"];
}

- (void)handleType:(uint8_t)type payload:(NSData *)payload {
    const uint8_t *p = payload.bytes;
    NSUInteger n = payload.length;
    if (type == 0x0C && n >= 4 && p[0] == 0x01 && p[1] == 0x00 && p[2] == 0x03 && p[3] == 0x00) {
        [self log:@"握手请求"];
        if (!self.handshakeReplied) {
            self.handshakeReplied = YES;
            [self writeFrameType:0x0C payload:[NSData dataWithBytes:(uint8_t[]){0x02,0x00} length:2] label:@"HANDSHAKE"];
            [self performSelector:@selector(queryState) withObject:nil afterDelay:0.35];
        }
        return;
    }
    if (type == 0x0C && n >= 9 && p[0] == 0x69 && p[1] == 0x19) {
        int mode = 0;
        if (p[3]) mode = p[4] ? 2 : 1;
        int level = p[6];
        [self log:@"状态: %@ level=%d", mode == 2 ? @"环境声" : (mode == 1 ? @"降噪" : @"关闭"), level];
        if (self.lastCommit && mode == self.lastCommitMode) {
            [self.resendTimer invalidate]; self.resendTimer = nil;
            self.lastCommit = nil;
        }
        if (self.stateHandler) self.stateHandler(mode, level);
        return;
    }
    if (type == 0x0C && n >= 9 && p[0] == 0x67 && p[1] == 0x19) {
        int mode = 0;
        if (p[3]) mode = p[4] ? 2 : 1;
        int level = p[6];
        [self log:@"查询状态: %@ level=%d", mode == 2 ? @"环境声" : (mode == 1 ? @"降噪" : @"关闭"), level];
        if (self.stateHandler) self.stateHandler(mode, level);
        return;
    }
    if (type == 0x0C && n >= 5 && p[0] == 0xC9) {
        // 设置项推送: C9 01 [len][key ascii][value..]
        NSString *key = [[NSString alloc] initWithBytes:p + 3 length:MIN((NSUInteger)p[2], n - 3) encoding:NSUTF8StringEncoding];
        [self log:@"推送 %@", key ?: EAHex(payload)];
        return;
    }
    if (type == 0x0C && n >= 3 && p[0] == 0xA9) {
        [self log:@"耳机通知会话将挂起 (A9 %@)", EAHex(payload)];
        return;
    }
    if (type == 0x0C && n == 2 && p[0] == 0x00) return; // 心跳
    [self log:@"RX t=%02X %@", type, EAHex(payload)];
}

- (NSData *)ambientPayload:(uint8_t)level commit:(BOOL)commit nc:(BOOL)nc off:(BOOL)off {
    uint8_t b[9];
    b[0] = 0x68; b[1] = 0x19;
    b[2] = commit ? 0x01 : 0x00;
    b[3] = off ? 0x00 : 0x01;
    b[4] = (off || nc) ? 0x00 : 0x01;
    b[5] = 0x00;
    b[6] = level;
    b[7] = 0x00; b[8] = 0x00;
    return [NSData dataWithBytes:b length:9];
}

- (void)scheduleResendForPayload:(NSData *)payload mode:(int)mode {
    [self.resendTimer invalidate];
    self.lastCommit = payload;
    self.lastCommitMode = mode;
    self.resendCount = 0;
    self.resendTimer = [NSTimer scheduledTimerWithTimeInterval:0.8 target:self selector:@selector(resendTick) userInfo:nil repeats:NO];
}

- (void)resendTick {
    if (!self.session || !self.lastCommit) return;
    if (self.resendCount >= 2) { [self log:@"命令无回应，放弃"]; return; }
    self.resendCount++;
    [self log:@"补发第 %d 次", self.resendCount];
    [self writeFrameType:0x0C payload:self.lastCommit label:@"RESEND"];
    self.resendTimer = [NSTimer scheduledTimerWithTimeInterval:0.8 target:self selector:@selector(resendTick) userInfo:nil repeats:NO];
}

- (void)previewTick {
    if (self.pendingPreview < 0) { self.previewTimer = nil; return; }
    int lv = self.pendingPreview;
    self.pendingPreview = -1;
    [self writeFrameType:0x0C payload:[self ambientPayload:(uint8_t)lv commit:NO nc:NO off:NO]
                   label:[NSString stringWithFormat:@"AMBIENT %d(拖动)", lv]];
}

- (void)setAmbient:(uint8_t)level commit:(BOOL)commit {
    if (!commit) {
        self.pendingPreview = level;
        if (!self.previewTimer) {
            self.previewTimer = [NSTimer scheduledTimerWithTimeInterval:0.10 target:self selector:@selector(previewTick) userInfo:nil repeats:YES];
        }
        return;
    }
    [self.previewTimer invalidate]; self.previewTimer = nil;
    self.pendingPreview = -1;
    NSData *p = [self ambientPayload:level commit:YES nc:NO off:NO];
    [self writeFrameType:0x0C payload:p label:[NSString stringWithFormat:@"AMBIENT %d", level]];
    [self scheduleResendForPayload:p mode:2];
}

- (void)setNCWithLevel:(uint8_t)level {
    NSData *p = [self ambientPayload:level commit:YES nc:YES off:NO];
    [self writeFrameType:0x0C payload:p label:@"NC"];
    [self scheduleResendForPayload:p mode:1];
}

- (void)setOffWithLevel:(uint8_t)level {
    NSData *p = [self ambientPayload:level commit:YES nc:NO off:YES];
    [self writeFrameType:0x0C payload:p label:@"OFF"];
    [self scheduleResendForPayload:p mode:0];
}

@end