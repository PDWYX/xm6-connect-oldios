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

@interface EATester () <NSStreamDelegate>
@property (nonatomic, strong) EAAccessory *accessory;
@property (nonatomic, strong) EASession *session;
@property (nonatomic, strong) NSMutableData *rxBuf;
@property (nonatomic) uint16_t txSeq;
@end

@implementation EATester

- (void)log:(NSString *)fmt, ... {
    va_list args;
    va_start(args, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    if (self.logger) self.logger(s);
    NSLog(@"[XM6EA] %@", s);
}

- (void)begin {
    self.rxBuf = [NSMutableData data];
    self.txSeq = 0xee00;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(accConnected:) name:EAAccessoryDidConnectNotification object:nil];
    [nc addObserver:self selector:@selector(accDisconnected:) name:EAAccessoryDidDisconnectNotification object:nil];
    [[EAAccessoryManager sharedAccessoryManager] registerForLocalNotifications];

    NSArray *accs = [[EAAccessoryManager sharedAccessoryManager] connectedAccessories];
    [self log:@"EA 已连配件数: %lu", (unsigned long)accs.count];
    for (EAAccessory *a in accs) [self dumpAccessory:a];
    if (accs.count == 0) [self log:@"(没有 EA 配件，点“挑配件”让系统弹出选择器)"];
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
    [self log:@"流已打开 in=%@ out=%@", in.streamStatus == NSStreamStatusOpen ? @"open" : @(in.streamStatus),
                                       out.streamStatus == NSStreamStatusOpen ? @"open" : @(out.streamStatus)];
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
        uint8_t buf[512];
        NSInteger n = [(NSInputStream *)stream read:buf maxLength:sizeof(buf)];
        if (n > 0) {
            NSData *d = [NSData dataWithBytes:buf length:(NSUInteger)n];
            [self.rxBuf appendData:d];
            [self log:@"RX %ld: %@", (long)n, EAHex(d)];
        }
    } else if (event == NSStreamEventErrorOccurred) {
        [self log:@"流错误: %@", stream.streamError.localizedDescription];
    } else if (event == NSStreamEventEndEncountered) {
        [self log:@"流结束"];
    } else if (event == NSStreamEventOpenCompleted) {
        [self log:@"%@ open completed", stream == self.session.inputStream ? @"in" : @"out"];
    }
}

- (void)writeRaw:(NSData *)d {
    if (!self.session) { [self log:@"没有会话，先开会话"]; return; }
    NSOutputStream *out = self.session.outputStream;
    if (out.streamStatus != NSStreamStatusOpen) { [self log:@"输出流未打开 status=%ld", (long)out.streamStatus]; return; }
    NSInteger n = [out write:d.bytes maxLength:d.length];
    [self log:@"TX %ld/%lu: %@", (long)n, (unsigned long)d.length, EAHex(d)];
}

// 送一个最小 iAP2 包，看耳机/iOS 是否理我们
- (void)sendTest {
    uint8_t pkt[] = {0xFF, 0x5A, 0x00, 0x04, 0x40, 0x00, 0x01, 0x00};
    [self writeRaw:[NSData dataWithBytes:pkt length:sizeof(pkt)]];
}

- (void)sendAmbient:(int)level {
    [self log:@"(EA) 环境声 %d — 具体帧待定", level];
}

- (void)sendNC {
    [self log:@"(EA) 降噪 — 具体帧待定"];
}

@end
