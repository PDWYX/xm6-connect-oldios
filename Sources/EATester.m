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

// MDR v2 帧(实测): 3E | type | seq(1) | len(4 BE) | payload | checksum | 3C
// checksum = 从 type 到 payload 末字节的累加和
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
    const uint8_t *p = d.bytes + 1; // 跳过 0x3E
    for (NSUInteger i = 1; i < d.length; i++) sum = (uint8_t)(sum + p[i - 1]);
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
@end

@implementation EATester

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
    self.seq = 0;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(accConnected:) name:EAAccessoryDidConnectNotification object:nil];
    [nc addObserver:self selector:@selector(accDisconnected:) name:EAAccessoryDidDisconnectNotification object:nil];
    [[EAAccessoryManager sharedAccessoryManager] registerForLocalNotifications];

    NSArray *accs = [[EAAccessoryManager sharedAccessoryManager] connectedAccessories];
    [self log:@"EA 已连配件数: %lu", (unsigned long)accs.count];
    for (EAAccessory *a in accs) [self dumpAccessory:a];
    if (accs.count && !self.session) { self.accessory = accs.firstObject; [self openSession]; }
}

- (void)dumpAccessory:(EAAccessory *)a {
    [self log:@"--- 配件: %@", a.name];
    [self log:@"   厂商=%@ 型号=%@ 序列号=%@ 固件=%@", a.manufacturer, a.modelNumber, a.serialNumber, a.firmwareRevision];
    [self log:@"   connectionID=%lu 协议=%@", (unsigned long)a.connectionID, [a.protocolStrings componentsJoinedByString:@", "]];
}

- (void)accConnected:(NSNotification *)n {
    EAAccessory *a = n.userInfo[EAAccessoryKey];
    [self log:@"EA 配件接入!"];
    [self dumpAccessory:a];
    self.accessory = a;
    [self openSession];
}

- (void)accDisconnected:(NSNotification *)n {
    EAAccessory *a = n.userInfo[EAAccessoryKey];
    [self log:@"EA 配件断开: %@", a.name];
    if (a.connectionID == self.accessory.connectionID) {
        [self closeSession];
        self.accessory = nil;
    }
}

- (void)showPicker {
    [self log:@"弹出配件选择器..."];
    [[EAAccessoryManager sharedAccessoryManager] showBluetoothAccessoryPickerWithNameFilter:nil completion:^(NSError *error) {
        [self log:@"选择器结束 err=%@", error.localizedDescription ?: @"nil"];
        NSArray *accs = [[EAAccessoryManager sharedAccessoryManager] connectedAccessories];
        [self log:@"现在配件数: %lu", (unsigned long)accs.count];
        for (EAAccessory *a in accs) [self dumpAccessory:a];
        if (accs.count) { self.accessory = accs.firstObject; [self openSession]; }
    }];
}

- (NSString *)pickProtocol:(EAAccessory *)a {
    for (NSString *p in a.protocolStrings) if ([p isEqualToString:kSonyProtocol]) return p;
    return a.protocolStrings.firstObject;
}

- (void)openSession {
    if (self.session) { [self log:@"会话已存在，先关闭"]; [self closeSession]; }
    if (!self.accessory) {
        NSArray *accs = [[EAAccessoryManager sharedAccessoryManager] connectedAccessories];
        if (accs.count) self.accessory = accs.firstObject;
    }
    if (!self.accessory) { [self log:@"没有配件可开会话"]; return; }
    NSString *proto = [self pickProtocol:self.accessory];
    [self log:@"开会话 协议=%@", proto];
    self.session = [[EASession alloc] initWithAccessory:self.accessory forProtocol:proto];
    if (!self.session) { [self log:@"EASession 创建失败 (协议不被接受?)"]; return; }
    NSInputStream *in = self.session.inputStream;
    NSOutputStream *out = self.session.outputStream;
    in.delegate = self; out.delegate = self;
    [in scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [out scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    [in open]; [out open];
    [self log:@"流已打开 in=%ld out=%ld", (long)in.streamStatus, (long)out.streamStatus];
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
        uint8_t buf[1024];
        NSInteger n = [(NSInputStream *)stream read:buf maxLength:sizeof(buf)];
        if (n > 0) {
            NSData *d = [NSData dataWithBytes:buf length:(NSUInteger)n];
            [self.rxBuf appendData:d];
            [self parseFrames];
        }
    } else if (event == NSStreamEventErrorOccurred) {
        [self log:@"流错误: %@", stream.streamError.localizedDescription];
    } else if (event == NSStreamEventEndEncountered) {
        [self log:@"流结束"];
    } else if (event == NSStreamEventOpenCompleted) {
        [self log:@"%@ open completed", stream == self.session.inputStream ? @"in" : @"out"];
    }
}

- (void)writeRaw:(NSData *)d label:(NSString *)label {
    if (!self.session) { [self log:@"%@: 没有会话", label]; return; }
    NSOutputStream *out = self.session.outputStream;
    if (out.streamStatus != NSStreamStatusOpen) { [self log:@"%@: 输出流未打开 status=%ld", label, (long)out.streamStatus]; return; }
    NSInteger n = [out write:d.bytes maxLength:d.length];
    [self log:@"%@ TX %ld/%lu: %@", label, (long)n, (unsigned long)d.length, EAHex(d)];
}

- (void)sendLinkSync {
    uint8_t p[] = {0xFF, 0x55, 0x02, 0x00, 0xEE, 0x10};
    [self writeRaw:[NSData dataWithBytes:p length:sizeof(p)] label:@"LINK"];
}

- (void)sendInit {
    self.seq = 0;
    [self writeRaw:MDRFrame(0x0C, 0, [NSData dataWithBytes:(uint8_t[]){0x00,0x00} length:2]) label:@"INIT"];
}

- (void)sendAmbient:(int)level {
    uint8_t pl[] = {0x68, 0x15, 0x01, 0x00, 0x01, 0x00, (uint8_t)level};
    [self writeRaw:MDRFrame(0x0C, self.seq++, [NSData dataWithBytes:pl length:sizeof(pl)]) label:[NSString stringWithFormat:@"AMB%d", level]];
}

- (void)sendNC {
    uint8_t pl[] = {0x68, 0x15, 0x01, 0x01, 0x00, 0x00, 0x00};
    [self writeRaw:MDRFrame(0x0C, self.seq++, [NSData dataWithBytes:pl length:sizeof(pl)]) label:@"NC"];
}

- (void)sendOff {
    uint8_t pl[] = {0x68, 0x15, 0x01, 0x00, 0x00, 0x00, 0x00};
    [self writeRaw:MDRFrame(0x0C, self.seq++, [NSData dataWithBytes:pl length:sizeof(pl)]) label:@"OFF"];
}

// 带 iAP2 外层的 INIT：ff5a | len(2) | 40 | seq(2) | hck | payload | ck
- (void)sendWrappedInit {
    NSData *mdr = MDRFrame(0x0C, 0, [NSData dataWithBytes:(uint8_t[]){0x00,0x00} length:2]);
    NSMutableData *p = [NSMutableData data];
    uint8_t pre[] = {0x2B, 0x00, 0x02};
    [p appendBytes:pre length:3];
    [p appendData:mdr];
    [self writeRaw:p label:@"WRAPPED-INIT"];
}

- (void)parseFrames {
    while (self.rxBuf.length >= 8) {
        const uint8_t *p = self.rxBuf.bytes;
        if (p[0] != 0x3E) {
            [self log:@"RX 非帧数据(%luB): %@", (unsigned long)self.rxBuf.length, EAHex(self.rxBuf)];
            [self.rxBuf setLength:0];
            return;
        }
        uint32_t len = ((uint32_t)p[3] << 24) | ((uint32_t)p[4] << 16) | ((uint32_t)p[5] << 8) | p[6];
        NSUInteger total = 1 + 1 + 1 + 4 + len + 1 + 1;
        if (self.rxBuf.length < total) return;
        NSData *frame = [self.rxBuf subdataWithRange:NSMakeRange(0, total)];
        [self.rxBuf replaceBytesInRange:NSMakeRange(0, total) withBytes:NULL length:0];
        NSData *payload = [frame subdataWithRange:NSMakeRange(7, len)];
        [self log:@"RX type=%02X seq=%02X len=%lu %@", p[1], p[2], (unsigned long)len, EAHex(payload)];
    }
}

- (void)eaRun {
    [self log:@"=== 全流程 INIT -> 环境声10 ==="];
    self.seq = 0;
    [self sendInit];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self sendAmbient:10];
    });
}

@end