#import "EATester.h"
#import <ExternalAccessory/ExternalAccessory.h>

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
@property (nonatomic) uint8_t seq;
@property (nonatomic) int lastLevel;
@end

@implementation EATester

- (BOOL)connected { return self.session != nil && self.session.outputStream.streamStatus == NSStreamStatusOpen; }

- (void)log:(NSString *)fmt, ... {
    va_list args;
    va_start(args, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    if (self.logger) self.logger(s);
    NSLog(@"[XM6EA] %@", s);
    [self fileLog:s];
}

- (void)fileLog:(NSString *)s {
    if (self.logFile == nil) {
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *path = [docs stringByAppendingPathComponent:@"xm6.log"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        }
        self.logFile = [NSFileHandle fileHandleForWritingAtPath:path];
        [self.logFile seekToEndOfFile];
    }
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"[%@] EA %@\n", [df stringFromDate:[NSDate date]], s];
    [self.logFile writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [self.logFile synchronizeFile];
}

- (void)begin {
    if (!self.rxBuf) self.rxBuf = [NSMutableData data];
    self.lastLevel = 10;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(accConnected:) name:EAAccessoryDidConnectNotification object:nil];
    [nc addObserver:self selector:@selector(accDisconnected:) name:EAAccessoryDidDisconnectNotification object:nil];
    [[EAAccessoryManager sharedAccessoryManager] registerForLocalNotifications];

    NSArray *accs = [[EAAccessoryManager sharedAccessoryManager] connectedAccessories];
    [self log:@"已连接配件: %lu", (unsigned long)accs.count];
    if (accs.count) { self.accessory = accs.firstObject; [self openSession]; }
}

- (void)accConnected:(NSNotification *)n {
    EAAccessory *a = n.userInfo[EAAccessoryKey];
    [self log:@"配件接入: %@", a.name];
    self.accessory = a;
    [self openSession];
}

- (void)accDisconnected:(NSNotification *)n {
    EAAccessory *a = n.userInfo[EAAccessoryKey];
    [self log:@"配件断开: %@", a.name];
    if (a.connectionID == self.accessory.connectionID) {
        [self closeSession];
        self.accessory = nil;
    }
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
    self.rxBuf.length = 0;
    self.seq = 0;
    NSInputStream *in = self.session.inputStream;
    NSOutputStream *out = self.session.outputStream;
    in.delegate = self; out.delegate = self;
    [in scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [out scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [in open]; [out open];
    [self log:@"会话已打开 %@", proto];
    // 主动发 INIT
    self.seq = 0;
    [self writeFrameType:0x0C payload:[NSData dataWithBytes:(uint8_t[]){0x00,0x00} length:2] label:@"INIT"];
}

- (void)closeSession {
    if (self.session) {
        [[self.session inputStream] close];
        [[self.session outputStream] close];
        self.session = nil;
    }
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)event {
    if (event == NSStreamEventHasBytesAvailable && stream == self.session.inputStream) {
        uint8_t buf[2048];
        NSInteger n = [(NSInputStream *)stream read:buf maxLength:sizeof(buf)];
        if (n > 0) {
            [self.rxBuf appendData:[NSData dataWithBytes:buf length:(NSUInteger)n]];
            [self parseFrames];
        }
    } else if (event == NSStreamEventErrorOccurred) {
        [self log:@"流错误: %@", stream.streamError.localizedDescription];
    } else if (event == NSStreamEventEndEncountered) {
        [self log:@"流结束"];
    }
}

- (NSData *)frameOfType:(uint8_t)type payload:(NSData *)payload {
    return MDRFrame(type, self.seq++, payload);
}

- (void)writeRaw:(NSData *)d label:(NSString *)label {
    NSOutputStream *out = self.session.outputStream;
    if (out.streamStatus != NSStreamStatusOpen) { [self log:@"%@: 流未打开", label]; return; }
    NSInteger n = [out write:d.bytes maxLength:d.length];
    if (n != (NSInteger)d.length) [self log:@"%@ 写失败 %ld/%lu", label, (long)n, (unsigned long)d.length];
}

- (void)writeFrameType:(uint8_t)type payload:(NSData *)payload label:(NSString *)label {
    if (!self.session) return;
    NSData *f = [self frameOfType:type payload:payload];
    [self log:@"TX %@ %@", label, EAHex(payload)];
    [self writeRaw:f label:label];
}

- (void)sendAck:(uint8_t)seq {
    NSData *f = MDRFrame(0x01, seq, [NSData data]);
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
        NSData *payload = [self.rxBuf subdataWithRange:NSMakeRange(7, len)];
        [self.rxBuf replaceBytesInRange:NSMakeRange(0, total) withBytes:NULL length:0];
        if (type == 0x01) continue;  // 对端 ACK
        [self sendAck:fseq];
        [self handleType:type payload:payload];
    }
}

- (void)handleType:(uint8_t)type payload:(NSData *)payload {
    const uint8_t *p = payload.bytes;
    NSUInteger n = payload.length;
    if (type == 0x0C && n >= 9 && p[0] == 0x69 && p[1] == 0x19) {
        int mode = 0;
        if (p[3]) mode = p[4] ? 2 : 1;
        int level = p[6];
        [self log:@"状态: %@ level=%d", mode == 2 ? @"环境声" : (mode == 1 ? @"降噪" : @"关闭"), level];
        if (self.stateHandler) self.stateHandler(mode, level);
        return;
    }
    if (type == 0x0C && n >= 5 && p[0] == 0xC9) {
        // 设置项推送: C9 01 [len][key ascii][value..]
        NSString *key = [[NSString alloc] initWithBytes:p + 3 length:MIN((NSUInteger)p[2], n - 3) encoding:NSUTF8StringEncoding];
        [self log:@"推送 %@", key ?: EAHex(payload)];
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

- (void)setAmbient:(uint8_t)level commit:(BOOL)commit {
    self.lastLevel = level;
    [self writeFrameType:0x0C payload:[self ambientPayload:level commit:commit nc:NO off:NO]
                   label:[NSString stringWithFormat:@"AMBIENT %d%@", level, commit ? @"" : @"(拖动)"]];
}

- (void)setNCWithLevel:(uint8_t)level {
    self.lastLevel = level;
    [self writeFrameType:0x0C payload:[self ambientPayload:level commit:YES nc:YES off:NO] label:@"NC"];
}

- (void)setOffWithLevel:(uint8_t)level {
    [self writeFrameType:0x0C payload:[self ambientPayload:level commit:YES nc:NO off:YES] label:@"OFF"];
}

@end
