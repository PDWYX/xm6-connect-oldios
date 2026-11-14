#import "ProbeViewController.h"
#import <CoreBluetooth/CoreBluetooth.h>

static NSString *const kWriteChar  = @"5B833C10-6BC7-4802-8E9A-723CECA4BD8F";
static NSString *const kWriteChar11 = @"5B833C11-6BC7-4802-8E9A-723CECA4BD8F";
static NSString *const kNotifyChar = @"5B833C12-6BC7-4802-8E9A-723CECA4BD8F";

@interface BLETester : NSObject <CBCentralManagerDelegate, CBPeripheralDelegate>
@property (nonatomic, strong) CBCentralManager *central;
@property (nonatomic, strong) CBPeripheral *peripheral;
@property (nonatomic, strong) CBCharacteristic *writeChar;
@property (nonatomic, strong) CBCharacteristic *writeChar11;
@property (nonatomic, copy) void (^logger)(NSString *line);
@property (nonatomic, strong) NSMutableSet<NSString *> *seenUUIDs;
@property (nonatomic, strong) NSFileHandle *logFile;
@property (nonatomic, strong) CBPeripheralManager *pm;
- (void)begin;
- (void)sendLevel:(int)level;
- (void)writeVariant:(NSString *)variant level:(int)level;
@end

@interface ProbeViewController () <UITextViewDelegate>
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) BLETester *tester;
@property (nonatomic, strong) NSMutableString *logBuffer;
@end

@implementation ProbeViewController

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

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *row2 = [[UIStackView alloc] init];
    row2.axis = UILayoutConstraintAxisHorizontal;
    row2.distribution = UIStackViewDistributionFillEqually;
    row2.spacing = 6;

    NSArray *titles = @[@"连接", @"A帧", @"B帧", @"C帧"];
    NSArray *sels = @[@"doConnect", @"doA", @"doB", @"doC"];
    NSArray *titles2 = @[@"级别5", @"级别10", @"级别15", @"级别18"];
    NSArray *sels2 = @[@"lvl5", @"lvl10", @"lvl15", @"lvl18"];
    for (NSUInteger i = 0; i < titles2.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:titles2[i] forState:UIControlStateNormal];
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        b.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
        b.titleLabel.font = [UIFont systemFontOfSize:12];
        [b addTarget:self action:NSSelectorFromString(sels2[i]) forControlEvents:UIControlEventTouchUpInside];
        [row2 addArrangedSubview:b];
    }
    UIStackView *outer = [[UIStackView alloc] init];
    outer.axis = UILayoutConstraintAxisVertical;
    outer.spacing = 6;
    outer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:outer];
    [outer addArrangedSubview:stack];
    [outer addArrangedSubview:row2];
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:titles[i] forState:UIControlStateNormal];
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        b.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
        b.titleLabel.font = [UIFont systemFontOfSize:12];
        [b addTarget:self action:NSSelectorFromString(sels[i]) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:b];
    }

    if (@available(iOS 11.0, *)) {
        UILayoutGuide *g = self.view.safeAreaLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [self.textView.topAnchor constraintEqualToAnchor:g.topAnchor constant:8],
            [self.textView.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:8],
            [self.textView.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-8],
            [self.textView.bottomAnchor constraintEqualToAnchor:outer.topAnchor constant:-8],
            [outer.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:8],
            [outer.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-8],
            [outer.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-8],
            [stack.heightAnchor constraintEqualToConstant:40],
            [row2.heightAnchor constraintEqualToConstant:40],
        ]];
    }

    __weak typeof(self) weakSelf = self;
    self.tester = [[BLETester alloc] init];
    self.tester.logger = ^(NSString *line) { [weakSelf appendLog:line]; };
    [self.tester begin];
}

- (void)appendLog:(NSString *)line {
    [self.logBuffer appendFormat:@"%@\n", line];
    if (self.logBuffer.length > 20000) {
        [self.logBuffer deleteCharactersInRange:NSMakeRange(0, self.logBuffer.length - 16000)];
    }
    self.textView.text = self.logBuffer;
    NSRange r = NSMakeRange(self.textView.text.length, 0);
    [self.textView scrollRangeToVisible:r];
    NSLog(@"[XM6] %@", line);
}

- (void)doConnect { [self.tester begin]; }
- (void)doTest { [self.tester sendLevel:-1]; }
- (void)doA { [self.tester writeVariant:@"A" level:10]; }
- (void)doB { [self.tester writeVariant:@"B" level:10]; }
- (void)doC { [self.tester writeVariant:@"C" level:10]; }
- (void)lvl10 { [self.tester writeVariant:@"A" level:10]; }
- (void)lvl5 { [self.tester writeVariant:@"A" level:5]; }
- (void)lvl15 { [self.tester writeVariant:@"A" level:15]; }
- (void)lvl18 { [self.tester writeVariant:@"A" level:18]; }

@end

@implementation BLETester

- (void)log:(NSString *)fmt, ... {
    va_list args;
    va_start(args, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    if (self.logger) self.logger(s);

    if (self.logFile == nil) {
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *path = [docs stringByAppendingPathComponent:@"xm6.log"];
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        self.logFile = [NSFileHandle fileHandleForWritingAtPath:path];
        [self.logFile seekToEndOfFile];
        if (self.logFile == nil) NSLog(@"[XM6] cannot open log file at %@", path);
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
    [self log:@"=== scan start (state=%ld) ===", (long)self.central.state];
    [self.central scanForPeripheralsWithServices:nil
                                         options:@{CBCentralManagerScanOptionAllowDuplicatesKey: @YES}];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self log:@"isScanning=%d", (int)self.central.isScanning];
    });
    [self peripheralManagerSelfTest];
    // 已连接的 BLE 设备（系统帮我们连着的）也算线索
    NSArray *svcs = @[[CBUUID UUIDWithString:@"FD82"],
                      [CBUUID UUIDWithString:@"5B833E06-6BC7-4802-8E9A-723CECA4BD8F"],
                      [CBUUID UUIDWithString:@"5B833E26-6BC7-4802-8E9A-723CECA4BD8F"]];
    for (CBUUID *u in svcs) {
        NSArray *arr = [self.central retrieveConnectedPeripheralsWithServices:@[u]];
        [self log:@"retrieveConnected %@ -> %lu", u.UUIDString, (unsigned long)arr.count];
        for (CBPeripheral *pp in arr) [self log:@"   known %@ %@", pp.name, pp.identifier.UUIDString];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(13 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.seenUUIDs.count == 0) {
            [self log:@"=== 第二轮：只按索尼服务 UUID 扫描 ==="];
            [self.central stopScan];
            [self.central scanForPeripheralsWithServices:svcs
                                                 options:@{CBCentralManagerScanOptionAllowDuplicatesKey: @YES}];
        }
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.peripheral == nil) {
            [self log:@"--- 12s 内共发现 %lu 个 BLE 设备 ---", (unsigned long)self.seenUUIDs.count];
            if (self.seenUUIDs.count == 0) {
                [self log:@"提示：耳机可能正连着手机音频（设置-蓝牙），此时不广播 BLE"];
            }
        }
    });
}

- (void)peripheralManagerSelfTest {
    if (self.pm == nil) {
        self.pm = [[CBPeripheralManager alloc] initWithDelegate:nil queue:dispatch_get_main_queue()];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self log:@"peripheralManager state=%ld advertising=%d", (long)self.pm.state, (int)self.pm.isAdvertising];
    });
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    [self log:@"central state=%ld", (long)central.state];
    if (central.state == CBManagerStatePoweredOn) [self startScan];
    else if (central.state == CBManagerStateUnauthorized) [self log:@"蓝牙权限被拒绝"];
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral
              advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI {
    NSString *uuid = peripheral.identifier.UUIDString;
    BOOL first = ![self.seenUUIDs containsObject:uuid];
    if (first) {
        [self.seenUUIDs addObject:uuid];
        NSString *name = advertisementData[CBAdvertisementDataLocalNameKey] ?: peripheral.name ?: @"(no name)";
        NSMutableArray *svc = [NSMutableArray array];
        for (CBUUID *u in advertisementData[CBAdvertisementDataServiceUUIDsKey]) [svc addObject:u.UUIDString];
        [self log:@"ADV #%lu %@ rssi=%@ uuid=%@ svc=[%@]", (unsigned long)self.seenUUIDs.count, name, RSSI, uuid,
              [svc componentsJoinedByString:@","]];
    }
    if (self.peripheral != nil) return;
    NSString *name = advertisementData[CBAdvertisementDataLocalNameKey] ?: peripheral.name ?: @"";
    NSString *up = [name uppercaseString];
    if ([up containsString:@"XM6"] || [up containsString:@"1000X"] || [up containsString:@"SONY"]) {
        self.peripheral = peripheral;
        peripheral.delegate = self;
        [central stopScan];
        [self log:@"connecting %@ (%@)", name, uuid];
        [central connectPeripheral:peripheral options:nil];
    }
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    [self log:@"CONNECTED %@", peripheral.name];
    [peripheral discoverServices:nil];
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    [self log:@"FAILCONNECT %@", error];
    self.peripheral = nil;
    [self startScan];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    [self log:@"DISCONNECTED %@", error];
    self.peripheral = nil;
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
        NSString *u = c.UUID.UUIDString;
        [self log:@"  CH %@ props=%lu", u, (unsigned long)c.properties];
        if ([[u uppercaseString] isEqualToString:kWriteChar]) self.writeChar = c;
        if ([[u uppercaseString] isEqualToString:kWriteChar11]) self.writeChar11 = c;
        if ([[u uppercaseString] isEqualToString:kNotifyChar]) {
            [peripheral setNotifyValue:YES forCharacteristic:c];
        }
        if ((c.properties & CBCharacteristicPropertyNotify) && [[u uppercaseString] isEqualToString:kNotifyChar] == NO
            && [[u uppercaseString] containsString:@"5B833C13"]) {
            [peripheral setNotifyValue:YES forCharacteristic:c];
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    [self log:@"WROTE %@ err=%@", characteristic.UUID.UUIDString, error.localizedDescription ?: @"ok"];
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    NSData *d = characteristic.value;
    [self log:@"NOTIFY %@ (%lu bytes) %@", characteristic.UUID.UUIDString, (unsigned long)d.length, d];
}

static NSData *EscapeSpecials(NSData *raw) {
    NSMutableData *out = [NSMutableData data];
    const uint8_t *p = raw.bytes;
    for (NSUInteger i = 0; i < raw.length; i++) {
        uint8_t b = p[i];
        if (b == 0x3C) { uint8_t e[2] = {0x61, 0x2C}; [out appendBytes:e length:2]; }
        else if (b == 0x3D) { uint8_t e[2] = {0x61, 0x2D}; [out appendBytes:e length:2]; }
        else if (b == 0x3E) { uint8_t e[2] = {0x61, 0x2E}; [out appendBytes:e length:2]; }
        else [out appendBytes:&b length:1];
    }
    return out;
}

- (NSData *)v1FrameForPayload:(NSData *)payload dataType:(uint8_t)dataType seq:(uint8_t)seq markers:(BOOL)markers {
    NSMutableData *body = [NSMutableData data];
    uint8_t head[6] = {dataType, seq, 0, 0, 0, 0};
    uint32_t len = (uint32_t)payload.length;
    head[2] = (len >> 24) & 0xFF; head[3] = (len >> 16) & 0xFF;
    head[4] = (len >> 8) & 0xFF;  head[5] = len & 0xFF;
    [body appendBytes:head length:6];
    [body appendData:payload];
    uint8_t sum = 0;
    const uint8_t *bp = body.bytes;
    for (NSUInteger i = 0; i < body.length; i++) sum = (uint8_t)(sum + bp[i]);
    [body appendBytes:&sum length:1];
    NSData *escaped = EscapeSpecials(body);
    if (!markers) return escaped;
    NSMutableData *full = [NSMutableData data];
    uint8_t s = 0x3E, e = 0x3C;
    [full appendBytes:&s length:1];
    [full appendData:escaped];
    [full appendBytes:&e length:1];
    return full;
}

- (NSData *)ncasmPayloadWithLevel:(int)level {
    uint8_t p[8];
    p[0] = 0x68;
    p[1] = (level <= 0) ? 1 : 2;
    p[2] = (level <= 0) ? 0 : 1;
    p[3] = (level <= 0) ? 0 : 1;
    uint8_t dualSingle = (level == 0) ? 2 : 1;
    p[4] = dualSingle;
    p[5] = (level <= 0) ? 0 : 1;
    p[6] = 0;
    p[7] = (uint8_t)(level <= 0 ? 0 : level);
    return [NSData dataWithBytes:p length:8];
}

- (void)writeVariant:(NSString *)variant level:(int)level {
    if (self.peripheral == nil || self.writeChar == nil) {
        [self log:@"未连接，先按连接 (peripheral=%@ writeChar=%@)", self.peripheral, self.writeChar];
        return;
    }
    NSData *payload = [self ncasmPayloadWithLevel:level];
    NSData *frame;
    CBCharacteristicWriteType type = CBCharacteristicWriteWithResponse;
    if ([variant isEqualToString:@"A"]) {
        frame = [self v1FrameForPayload:payload dataType:0 seq:0 markers:YES];
    } else if ([variant isEqualToString:@"B"]) {
        frame = [self v1FrameForPayload:payload dataType:0 seq:0 markers:NO];
    } else {
        frame = payload;
        type = CBCharacteristicWriteWithoutResponse;
    }
    [self log:@"WRITE %@ lvl=%d (%lu B) %@", variant, level, (unsigned long)frame.length, frame];
    [self.peripheral writeValue:frame forCharacteristic:self.writeChar type:type];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self readStateChars];
    });
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

- (void)sendLevel:(int)level {
    if (self.peripheral == nil || self.writeChar == nil) {
        [self log:@"未连接，先按连接 (peripheral=%@ writeChar=%@)", self.peripheral, self.writeChar];
        return;
    }
    uint8_t seq = 0;
    if (level < 0) {
        NSData *payload = [self ncasmPayloadWithLevel:10];
        NSData *a = [self v1FrameForPayload:payload dataType:0 seq:seq markers:YES];
        NSData *b = [self v1FrameForPayload:payload dataType:0 seq:seq markers:NO];
        [self log:@"TEST A markers: %@", a];
        [self.peripheral writeValue:a forCharacteristic:self.writeChar type:CBCharacteristicWriteWithResponse];
        [self log:@"TEST B escaped: %@", b];
        [self.peripheral writeValue:b forCharacteristic:self.writeChar type:CBCharacteristicWriteWithoutResponse];
        [self log:@"TEST C raw: %@", payload];
        [self.peripheral writeValue:payload forCharacteristic:self.writeChar type:CBCharacteristicWriteWithoutResponse];
        return;
    }
    NSData *payload = [self ncasmPayloadWithLevel:level];
    NSData *frame = [self v1FrameForPayload:payload dataType:0 seq:seq markers:YES];
    [self log:@"WRITE level=%d frame=%@", level, frame];
    [self.peripheral writeValue:frame forCharacteristic:self.writeChar type:CBCharacteristicWriteWithResponse];
}

@end