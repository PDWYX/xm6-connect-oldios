#import "ProbeViewController.h"
#import <CoreBluetooth/CoreBluetooth.h>
#import "EATester.h"

static NSString *const kWriteChar  = @"5B833C10-6BC7-4802-8E9A-723CECA4BD8F";
static NSString *const kWriteChar11 = @"5B833C11-6BC7-4802-8E9A-723CECA4BD8F";
static NSString *const kNotifyChar = @"5B833C12-6BC7-4802-8E9A-723CECA4BD8F";

static NSString *Hex(NSData *d) {
    if (d.length == 0) return @"(empty)";
    const uint8_t *p = d.bytes;
    NSMutableString *s = [NSMutableString stringWithCapacity:d.length * 3];
    for (NSUInteger i = 0; i < d.length; i++) [s appendFormat:@"%02X ", p[i]];
    return s;
}

@interface BLETester : NSObject <CBCentralManagerDelegate, CBPeripheralDelegate>
@property (nonatomic, strong) CBCentralManager *central;
@property (nonatomic, strong) CBPeripheral *peripheral;
@property (nonatomic, strong) CBCharacteristic *writeChar;
@property (nonatomic, strong) CBCharacteristic *writeChar11;
@property (nonatomic, strong) CBCharacteristic *writeChar1C;
@property (nonatomic, strong) CBCharacteristic *notify12;
@property (nonatomic, strong) CBCharacteristic *notify13;
@property (nonatomic, strong) CBCharacteristic *notify1B;
@property (nonatomic, strong) NSArray *sweepTests;
@property (nonatomic) NSUInteger sweepIndex;
@property (nonatomic, strong) NSTimer *forceClock;
@property (nonatomic, strong) NSMutableArray *notifyChars;
@property (nonatomic, copy) void (^logger)(NSString *line);
@property (nonatomic, strong) NSMutableSet<NSString *> *seenUUIDs;
@property (nonatomic, strong) NSFileHandle *logFile;
@property (nonatomic) BOOL useAlt;
- (void)begin;
- (void)sendInit;
- (void)sendAmbientLevel:(int)level wind:(BOOL)wind;
- (void)sendNCWithWind:(BOOL)wind;
- (void)toggleAlt;
- (void)runSweep;
- (void)sweepStep;
- (void)readStateChars;
@end

@interface ProbeViewController ()
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) BLETester *tester;
@property (nonatomic, strong) EATester *eaTester;
@property (nonatomic, strong) NSMutableString *logBuffer;
@end

@implementation ProbeViewController

- (UIButton *)buttonWithTitle:(NSString *)title sel:(NSString *)sel bg:(CGFloat)bg {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.backgroundColor = [UIColor colorWithWhite:bg alpha:1.0];
    b.titleLabel.font = [UIFont systemFontOfSize:12];
    b.titleLabel.adjustsFontSizeToFitWidth = YES;
    [b addTarget:self action:NSSelectorFromString(sel) forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UIStackView *)rowWithTitles:(NSArray *)titles sels:(NSArray *)sels bg:(CGFloat)bg {
    UIStackView *row = [[UIStackView alloc] init];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.spacing = 6;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row.heightAnchor constraintEqualToConstant:40].active = YES;
    for (NSUInteger i = 0; i < titles.count; i++) {
        [row addArrangedSubview:[self buttonWithTitle:titles[i] sel:sels[i] bg:bg]];
    }
    return row;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.logBuffer = [NSMutableString string];

    self.textView = [[UITextView alloc] initWithFrame:CGRectZero];
    self.textView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    self.textView.textColor = [UIColor colorWithRed:0.55 green:1.0 blue:0.55 alpha:1.0];
    self.textView.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont systemFontOfSize:11];
    self.textView.editable = NO;
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.textView];

    UIStackView *outer = [[UIStackView alloc] init];
    outer.axis = UILayoutConstraintAxisVertical;
    outer.spacing = 6;
    outer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:outer];

    [outer addArrangedSubview:[self rowWithTitles:@[@"连接", @"INIT", @"扫描", @"读状态"]
                                            sels:@[@"doConnect", @"doInit", @"doSweep", @"doRead"] bg:0.28]];
    [outer addArrangedSubview:[self rowWithTitles:@[@"环境5", @"环境10", @"环境15", @"环境20"]
                                            sels:@[@"lvl5", @"lvl10", @"lvl15", @"lvl20"] bg:0.22]];
    [outer addArrangedSubview:[self rowWithTitles:@[@"降噪", @"通道2", @"环境8B"]
                                            sels:@[@"doNC", @"doAlt", @"doW10"] bg:0.22]];
    [outer addArrangedSubview:[self rowWithTitles:@[@"挑配件", @"开会话", @"EA-INIT", @"EA环境10"]
                                            sels:@[@"eaPicker", @"eaOpen", @"eaInit", @"eaAmb10"] bg:0.62]];
    [outer addArrangedSubview:[self rowWithTitles:@[@"EA降噪", @"EA关", @"EA-KILL", @"EA-WRAP"]
                                            sels:@[@"eaNC", @"eaOff", @"eaLink", @"eaWrap"] bg:0.62]];
    [outer addArrangedSubview:[self rowWithTitles:@[@"EA全流程", @"EA环境1", @"EA环境20", @"清屏"]
                                            sels:@[@"eaRun", @"eaAmb1", @"eaAmb20", @"eaClear"] bg:0.72]];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.textView.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
        [self.textView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:8],
        [self.textView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-8],
        [self.textView.bottomAnchor constraintEqualToAnchor:outer.topAnchor constant:-8],
        [outer.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:8],
        [outer.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-8],
        [outer.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-8],
    ]];

    __weak typeof(self) weakSelf = self;
    self.tester = [[BLETester alloc] init];
    self.tester.logger = ^(NSString *line) { [weakSelf appendLog:line]; };
    [self.tester begin];

    self.eaTester = [[EATester alloc] init];
    self.eaTester.logger = ^(NSString *line) { [weakSelf appendLog:line]; };
    [self.eaTester begin];
}

- (void)appendLog:(NSString *)line {
    [self.logBuffer appendFormat:@"%@\n", line];
    if (self.logBuffer.length > 20000) {
        [self.logBuffer deleteCharactersInRange:NSMakeRange(0, self.logBuffer.length - 16000)];
    }
    NSString *t = [self.logBuffer copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.textView.text = t;
        if (t.length) [self.textView scrollRangeToVisible:NSMakeRange(t.length, 0)];
    });
    NSLog(@"[XM6] %@", line);
}

- (void)doConnect { [self.tester begin]; }
- (void)doInit { [self.tester sendInit]; }
- (void)doSweep { [self.tester runSweep]; }
- (void)doAlt { [self.tester toggleAlt]; }
- (void)doRead { [self.tester readStateChars]; }
- (void)lvl5 { [self.tester sendAmbientLevel:5 wind:NO]; }
- (void)lvl10 { [self.tester sendAmbientLevel:10 wind:NO]; }
- (void)lvl15 { [self.tester sendAmbientLevel:15 wind:NO]; }
- (void)lvl20 { [self.tester sendAmbientLevel:20 wind:NO]; }
- (void)doNC { [self.tester sendNCWithWind:NO]; }
- (void)doW10 { [self.tester sendAmbientLevel:10 wind:YES]; }
- (void)doWNC { [self.tester sendNCWithWind:YES]; }
- (void)eaPicker { [self.eaTester showPicker]; }
- (void)eaList { [self.eaTester begin]; }
- (void)eaOpen { [self.eaTester openSession]; }
- (void)eaInit { [self.eaTester sendInit]; }
- (void)eaAmb10 { [self.eaTester sendAmbient:10]; }
- (void)eaNC { [self.eaTester sendNC]; }
- (void)eaOff { [self.eaTester sendOff]; }
- (void)eaLink { [self.eaTester sendLinkSync]; }
- (void)eaWrap { [self.eaTester sendWrappedInit]; }
- (void)eaRun { [self.eaTester eaRun]; }
- (void)eaAmb1 { [self.eaTester sendAmbient:1]; }
- (void)eaAmb20 { [self.eaTester sendAmbient:20]; }
- (void)eaClear { [self appendLog:@"----------- 清屏 -----------"]; }

@end

@implementation BLETester

- (instancetype)init {
    if (self = [super init]) {
        _notifyChars = [NSMutableArray array];
    }
    return self;
}

- (void)log:(NSString *)fmt, ... {
    va_list args;
    va_start(args, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    if (self.logger) self.logger(s);

    if (self.logFile == nil) {
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *path = [docs stringByAppendingPathComponent:@"xm6.log"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        }
        self.logFile = [NSFileHandle fileHandleForWritingAtPath:path];
        [self.logFile seekToEndOfFile];
    }
    if (self.logFile) {
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"HH:mm:ss";
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [df stringFromDate:[NSDate date]], s];
        [self.logFile writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [self.logFile synchronizeFile];
    }
}

- (void)begin {
    if (self.central == nil) {
        self.seenUUIDs = [NSMutableSet set];
        self.central = [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue()
                                                          options:@{CBCentralManagerOptionShowPowerAlertKey: @YES}];
    } else if (self.central.state == CBManagerStatePoweredOn) {
        [self.central stopScan];
        [self startScan];
    }
}

- (void)startScan {
    if (self.peripheral && self.peripheral.state == CBPeripheralStateConnected) {
        [self log:@"已经连着了 %@", self.peripheral.name];
        return;
    }
    [self log:@"=== scan start (state=%ld) ===", (long)self.central.state];
    [self.central scanForPeripheralsWithServices:nil
                                         options:@{CBCentralManagerScanOptionAllowDuplicatesKey: @YES}];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.peripheral == nil && self.central.isScanning) {
            [self log:@"--- 12s 内发现 %lu 个 BLE 设备，未见 XM6 ---", (unsigned long)self.seenUUIDs.count];
            [self log:@"提示：耳机若正连着音频（设置-蓝牙），可能不广播 BLE；可先断开系统连接再试"];
        }
    });
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    [self log:@"central state=%ld (5=已授权)", (long)central.state];
    if (central.state == CBManagerStatePoweredOn) [self startScan];
    else if (central.state == CBManagerStateUnauthorized) [self log:@"蓝牙权限被拒绝：设置里允许本 App 使用蓝牙"];
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral
              advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI {
    NSString *uuid = peripheral.identifier.UUIDString;
    BOOL first = ![self.seenUUIDs containsObject:uuid];
    NSString *name = advertisementData[CBAdvertisementDataLocalNameKey] ?: peripheral.name ?: @"";
    if (first) {
        [self.seenUUIDs addObject:uuid];
        NSMutableArray *svc = [NSMutableArray array];
        for (CBUUID *u in advertisementData[CBAdvertisementDataServiceUUIDsKey]) [svc addObject:u.UUIDString];
        [self log:@"ADV #%lu %@ rssi=%@ svc=[%@]", (unsigned long)self.seenUUIDs.count, name, RSSI,
              [svc componentsJoinedByString:@","]];
    }
    if (self.peripheral != nil) return;
    NSString *up = [name uppercaseString];
    if ([up containsString:@"XM6"] || [up containsString:@"1000X"] || [up containsString:@"SONY"] || [up containsString:@"WH-"]) {
        self.peripheral = peripheral;
        peripheral.delegate = self;
        [central stopScan];
        [self log:@"connecting %@", name];
        [central connectPeripheral:peripheral options:nil];
    }
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    [self log:@"CONNECTED %@", peripheral.name];
    [peripheral discoverServices:nil];
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    [self log:@"FAILCONNECT %@", error.localizedDescription];
    self.peripheral = nil;
    [self startScan];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    [self log:@"DISCONNECTED %@", error.localizedDescription];
    self.peripheral = nil;
    [self.notifyChars removeAllObjects];
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    if (error) { [self log:@"discoverServices error %@", error]; return; }
    for (CBService *s in peripheral.services) {
        [self log:@"SVC %@", s.UUID.UUIDString];
        [peripheral discoverCharacteristics:nil forService:s];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    if (error) { [self log:@"discoverChar error %@", error]; return; }
    for (CBCharacteristic *c in service.characteristics) {
        NSString *u = c.UUID.UUIDString.uppercaseString;
        [self log:@"  CH %@ props=%lu", u, (unsigned long)c.properties];
        if ([u isEqualToString:kWriteChar]) self.writeChar = c;
        if ([u isEqualToString:kWriteChar11]) self.writeChar11 = c;
        if ([u hasPrefix:@"5B833C1C"]) self.writeChar1C = c;
        if (c.properties & CBCharacteristicPropertyNotify) {
            if ([u hasPrefix:@"5B833C12"] || [u hasPrefix:@"5B833C13"] || [u hasPrefix:@"5B833C1B"]) {
                [peripheral setNotifyValue:YES forCharacteristic:c];
                if (![self.notifyChars containsObject:c]) [self.notifyChars addObject:c];
                if ([u hasPrefix:@"5B833C12"]) self.notify12 = c;
                if ([u hasPrefix:@"5B833C13"]) self.notify13 = c;
                if ([u hasPrefix:@"5B833C1B"]) self.notify1B = c;
                [self log:@"  -> 订阅 %@", u];
            }
        }
    }
}

- (CBCharacteristic *)activeWriteChar {
    if (self.useAlt && self.writeChar11) return self.writeChar11;
    return self.writeChar;
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    [self log:@"NOTIFY-STATE %@ on=%d err=%@", characteristic.UUID.UUIDString,
          (int)characteristic.isNotifying, error.localizedDescription ?: @"none"];
}

- (void)runSweep {
    if (self.peripheral == nil || self.writeChar == nil) { [self log:@"未连接或未找到写特征 C10"]; return; }
    NSData *body = [self frameWithType:0x0C seq:0 payload:[self ambientPayload:10 wind:NO]];
    NSData *raw = [self ambientPayload:10 wind:NO];
    NSMutableArray *tests = [NSMutableArray array];

    [tests addObject:@[@"A raw", self.writeChar, body]];
    for (NSNumber *h in @[@0x00, @0x01, @0x02, @0x40, @0x80, @0xFF]) {
        NSMutableData *d = [NSMutableData dataWithBytes:(uint8_t[]){h.unsignedCharValue} length:1];
        [d appendData:body];
        [tests addObject:@[[NSString stringWithFormat:@"H%02X", h.unsignedCharValue], self.writeChar, d]];
    }
    [tests addObject:@[@"no-markers", self.writeChar, [NSData dataWithBytes:(const uint8_t[]){0x0C,0x00,0,0,0,7,0x68,0x15,0x01,0x00,0x01,0x00,0x0A} length:13]]];
    [tests addObject:@[@"raw-payload", self.writeChar, raw]];
    if (self.writeChar11) [tests addObject:@[@"C11 frame", self.writeChar11, body]];
    if (self.writeChar1C) {
        [tests addObject:@[@"C1C frame", self.writeChar1C, body]];
        NSMutableData *d = [NSMutableData dataWithBytes:(uint8_t[]){0x00} length:1];
        [d appendData:body];
        [tests addObject:@[@"C1C H00", self.writeChar1C, d]];
    }
    [tests addObject:@[@"byte 00", self.writeChar, [NSData dataWithBytes:(uint8_t[]){0x00} length:1]]];
    [tests addObject:@[@"byte 01", self.writeChar, [NSData dataWithBytes:(uint8_t[]){0x01} length:1]]];

    self.sweepTests = tests;
    self.sweepIndex = 0;
    [self.forceClock invalidate];
    self.forceClock = nil;
    [self log:@"=== sweep 开始（%lu 个变体，每个 1.6s）===", (unsigned long)tests.count];
    [self sweepStep];
}

- (void)sweepStep {
    [self.forceClock invalidate];
    self.forceClock = nil;
    if (self.sweepIndex >= self.sweepTests.count) {
        [self log:@"=== sweep 结束 ==="];
        self.sweepTests = nil;
        return;
    }
    NSArray *t = self.sweepTests[self.sweepIndex];
    self.sweepIndex++;
    CBCharacteristic *ch = t[1];
    NSData *data = t[2];
    [self log:@"### %@ -> %@  %@", t[0], ch.UUID.UUIDString, Hex(data)];
    if (ch != nil && data != nil && self.peripheral.state == CBPeripheralStateConnected) {
        [self.peripheral writeValue:data forCharacteristic:ch type:CBCharacteristicWriteWithResponse];
    } else {
        [self log:@"  跳过（特征或数据为空）"];
    }
    self.forceClock = [NSTimer scheduledTimerWithTimeInterval:1.6 target:self
                                                     selector:@selector(sweepStep) userInfo:nil repeats:NO];
}

- (NSData *)ambientPayload:(int)level wind:(BOOL)wind {
    uint8_t p[8];
    NSUInteger n = 0;
    p[n++] = 0x68; p[n++] = wind ? 0x17 : 0x15; p[n++] = 0x01; p[n++] = 0x00; p[n++] = 0x01;
    if (wind) p[n++] = 0x02;
    p[n++] = 0x00; p[n++] = (uint8_t)level;
    return [NSData dataWithBytes:p length:n];
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    [self log:@"WROTE-OK %@ err=%@", characteristic.UUID.UUIDString, error.localizedDescription ?: @"none"];
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    NSData *d = characteristic.value;
    [self log:@"<<< %@ (%luB) %@", characteristic.UUID.UUIDString, (unsigned long)d.length, Hex(d)];
}

- (void)toggleAlt {
    self.useAlt = !self.useAlt;
    [self log:@"写入通道切换为 %@", self.useAlt ? @"5B833C11" : @"5B833C10"];
}

static NSData *EscapeBody(NSData *raw) {
    NSMutableData *out = [NSMutableData data];
    const uint8_t *p = raw.bytes;
    for (NSUInteger i = 0; i < raw.length; i++) {
        uint8_t b = p[i];
        if (b == 0x3C || b == 0x3D || b == 0x3E) {
            uint8_t e[2] = {0x3D, (uint8_t)(b & 0xEF)};
            [out appendBytes:e length:2];
        } else {
            [out appendBytes:&b length:1];
        }
    }
    return out;
}

- (NSData *)frameWithType:(uint8_t)type seq:(uint8_t)seq payload:(NSData *)payload {
    NSMutableData *body = [NSMutableData data];
    uint8_t head[6];
    head[0] = type;
    head[1] = seq;
    uint32_t len = (uint32_t)payload.length;
    head[2] = (len >> 24) & 0xFF; head[3] = (len >> 16) & 0xFF;
    head[4] = (len >> 8) & 0xFF;  head[5] = len & 0xFF;
    [body appendBytes:head length:6];
    [body appendData:payload];
    uint8_t sum = 0;
    const uint8_t *bp = body.bytes;
    for (NSUInteger i = 0; i < body.length; i++) sum = (uint8_t)(sum + bp[i]);
    [body appendBytes:&sum length:1];

    NSMutableData *full = [NSMutableData data];
    uint8_t s = 0x3E, e = 0x3C;
    [full appendBytes:&s length:1];
    [full appendData:EscapeBody(body)];
    [full appendBytes:&e length:1];
    return full;
}

- (void)writePayload:(NSData *)payload label:(NSString *)label {
    CBCharacteristic *ch = [self activeWriteChar];
    if (self.peripheral == nil || ch == nil) {
        [self log:@"未连接（peripheral=%@ char=%@），先按“连接”", self.peripheral, ch];
        return;
    }
    NSData *frame = [self frameWithType:0x0C seq:0 payload:payload];
    [self log:@"WRITE %@ payload=%@", label, Hex(payload)];
    [self log:@"       frame=%@", Hex(frame)];
    [self.peripheral writeValue:frame forCharacteristic:ch type:CBCharacteristicWriteWithResponse];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self readStateChars];
    });
}

- (void)sendInit {
    const uint8_t p[2] = {0x00, 0x00};
    [self writePayload:[NSData dataWithBytes:p length:2] label:@"INIT"];
}

- (void)sendAmbientLevel:(int)level wind:(BOOL)wind {
    NSMutableData *p = [NSMutableData data];
    uint8_t b0 = 0x68, b1 = wind ? 0x17 : 0x15, b2 = 0x01, nc = 0x00, amb = 0x01, windByte = 0x02, focus = 0x00;
    [p appendBytes:&b0 length:1];
    [p appendBytes:&b1 length:1];
    [p appendBytes:&b2 length:1];
    [p appendBytes:&nc length:1];
    [p appendBytes:&amb length:1];
    if (wind) [p appendBytes:&windByte length:1];
    [p appendBytes:&focus length:1];
    uint8_t lv = (uint8_t)level;
    [p appendBytes:&lv length:1];
    [self writePayload:p label:[NSString stringWithFormat:@"AMBIENT %d%@", level, wind ? @" (8B)" : @""]];
}

- (void)sendNCWithWind:(BOOL)wind {
    NSMutableData *p = [NSMutableData data];
    uint8_t b0 = 0x68, b1 = wind ? 0x17 : 0x15, b2 = 0x01, nc = 0x01, amb = 0x00, windByte = 0x02, focus = 0x00, lv = 0x00;
    [p appendBytes:&b0 length:1];
    [p appendBytes:&b1 length:1];
    [p appendBytes:&b2 length:1];
    [p appendBytes:&nc length:1];
    [p appendBytes:&amb length:1];
    if (wind) [p appendBytes:&windByte length:1];
    [p appendBytes:&focus length:1];
    [p appendBytes:&lv length:1];
    [self writePayload:p label:wind ? @"NC (8B)" : @"NC"];
}

- (void)readStateChars {
    if (self.peripheral == nil) return;
    for (CBService *s in self.peripheral.services) {
        for (CBCharacteristic *c in s.characteristics) {
            NSString *u = c.UUID.UUIDString.uppercaseString;
            if ([u hasPrefix:@"5B833C68"] || [u hasPrefix:@"76C13022"] || [u hasPrefix:@"2A50"] || [u hasPrefix:@"8E0C0001"]) {
                [self.peripheral readValueForCharacteristic:c];
            }
        }
    }
}

@end