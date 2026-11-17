#import "ProbeViewController.h"
#import <ExternalAccessory/ExternalAccessory.h>
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
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *levelLabel;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) EATester *ea;
@property (nonatomic, strong) NSMutableString *logBuffer;
@property (nonatomic) BOOL suppress;
@end

@implementation ProbeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.logBuffer = [NSMutableString string];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"正在连接耳机…";
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.font = [UIFont boldSystemFontOfSize:17];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;

    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"降噪", @"环境声", @"关闭"]];
    self.modeControl.selectedSegmentIndex = UISegmentedControlNoSegment;
    [self.modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];

    self.levelLabel = [[UILabel alloc] init];
    self.levelLabel.text = @"环境声级别 10";
    self.levelLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    self.levelLabel.font = [UIFont systemFontOfSize:14];
    self.levelLabel.textAlignment = NSTextAlignmentCenter;

    self.slider = [[UISlider alloc] init];
    self.slider.minimumValue = 1;
    self.slider.maximumValue = 20;
    self.slider.value = 10;
    [self.slider addTarget:self action:@selector(sliderMoved:) forControlEvents:UIControlEventValueChanged];
    [self.slider addTarget:self action:@selector(sliderDone:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    UIButton *reconnect = [UIButton buttonWithType:UIButtonTypeSystem];
    [reconnect setTitle:@"重新连接" forState:UIControlStateNormal];
    [reconnect setTitleColor:[UIColor colorWithWhite:0.6 alpha:1.0] forState:UIControlStateNormal];
    [reconnect addTarget:self action:@selector(reconnectTapped) forControlEvents:UIControlEventTouchUpInside];

    UIButton *picker = [UIButton buttonWithType:UIButtonTypeSystem];
    [picker setTitle:@"选择设备" forState:UIControlStateNormal];
    [picker setTitleColor:[UIColor colorWithWhite:0.6 alpha:1.0] forState:UIControlStateNormal];
    [picker addTarget:self action:@selector(pickerTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *btnRow = [[UIStackView alloc] initWithArrangedSubviews:@[reconnect, picker]];
    btnRow.axis = UILayoutConstraintAxisHorizontal;
    btnRow.spacing = 24;
    btnRow.distribution = UIStackViewDistributionFillEqually;

    self.logView = [[UITextView alloc] init];
    self.logView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    self.logView.textColor = [UIColor colorWithRed:0.5 green:0.9 blue:0.5 alpha:1.0];
    self.logView.font = [UIFont fontWithName:@"Menlo" size:9] ?: [UIFont systemFontOfSize:9];
    self.logView.editable = NO;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.statusLabel, self.modeControl, self.levelLabel, self.slider, btnRow, self.logView]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:g.topAnchor constant:20],
        [stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-20],
        [stack.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-16],
        [self.modeControl.heightAnchor constraintEqualToConstant:38],
        [self.logView.heightAnchor constraintGreaterThanOrEqualToConstant:120],
        [self.slider.heightAnchor constraintEqualToConstant:40],
    ]];

    __weak typeof(self) weakSelf = self;
    self.ea = [[EATester alloc] init];
    self.ea.logger = ^(NSString *line) { [weakSelf appendLog:line]; };
    self.ea.stateHandler = ^(int mode, int level) { [weakSelf applyMode:mode level:level]; };
    [self.ea begin];
}

- (void)appendLog:(NSString *)line {
    [self.logBuffer appendFormat:@"%@\n", line];
    if (self.logBuffer.length > 8000) {
        [self.logBuffer deleteCharactersInRange:NSMakeRange(0, self.logBuffer.length - 6000)];
    }
    NSString *t = [self.logBuffer copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.logView.text = t;
        if (t.length) [self.logView scrollRangeToVisible:NSMakeRange(t.length, 0)];
        self.statusLabel.text = self.ea.connected ? @"WH-1000XM6 已连接" : @"未连接";
        self.statusLabel.textColor = self.ea.connected ? [UIColor whiteColor] : [UIColor redColor];
    });
}

- (void)applyMode:(int)mode level:(int)level {
    self.suppress = YES;
    if (mode == 1) self.modeControl.selectedSegmentIndex = 0;
    else if (mode == 2) self.modeControl.selectedSegmentIndex = 1;
    else self.modeControl.selectedSegmentIndex = 2;
    if (level >= 1 && level <= 20) {
        self.slider.value = level;
        self.levelLabel.text = [NSString stringWithFormat:@"环境声级别 %d", level];
    }
    self.slider.enabled = (mode == 2);
    self.suppress = NO;
}

- (int)level {
    return (int)lroundf(self.slider.value);
}

- (void)sliderMoved:(UISlider *)s {
    self.levelLabel.text = [NSString stringWithFormat:@"环境声级别 %d", [self level]];
    if (self.suppress) return;
    if (self.modeControl.selectedSegmentIndex != 1) {
        self.modeControl.selectedSegmentIndex = 1;
    }
    [self.ea setAmbient:(uint8_t)[self level] commit:NO];
}

- (void)sliderDone:(UISlider *)s {
    [self.ea setAmbient:(uint8_t)[self level] commit:YES];
}

- (void)modeChanged:(UISegmentedControl *)c {
    if (self.suppress) return;
    int lv = [self level];
    if (c.selectedSegmentIndex == 0) [self.ea setNCWithLevel:(uint8_t)lv];
    else if (c.selectedSegmentIndex == 1) [self.ea setAmbient:(uint8_t)lv commit:YES];
    else [self.ea setOffWithLevel:(uint8_t)lv];
    self.slider.enabled = (c.selectedSegmentIndex == 1);
}

- (void)pickerTapped {
    [self appendLog:@"--- 弹出配件选择器 ---"];
    [[EAAccessoryManager sharedAccessoryManager] showBluetoothAccessoryPickerWithNameFilter:nil completion:^(NSError *error) {
        [self appendLog:[NSString stringWithFormat:@"选择器结束 err=%@", error.localizedDescription ?: @"nil"]];
    }];
}

- (void)reconnectTapped {
    [self appendLog:@"--- 重新连接 ---"];
    [self.ea openSession];
}

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