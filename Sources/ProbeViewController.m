#import "ProbeViewController.h"
#import <CoreBluetooth/CoreBluetooth.h>

static NSString *const kWriteChar = @"5B833C10-6BC7-4802-8E9A-723CECA4BD8F";
static NSString *const kNotifyChar = @"5B833C12-6BC7-4802-8E9A-723CECA4BD8F";

@interface BLETester : NSObject <CBCentralManagerDelegate, CBPeripheralDelegate>
@property (nonatomic, strong) CBCentralManager *central;
@property (nonatomic, strong) CBPeripheral *peripheral;
@property (nonatomic, strong) CBCharacteristic *writeChar;
@property (nonatomic, strong) CBCharacteristic *writeChar11;
@property (nonatomic, copy) void (^logger)(NSString *line);
@property (nonatomic, assign) BOOL startedTests;
- (void)begin;
- (void)sendLevel:(int)level;
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
    [self.view addSubview:stack];

    NSArray *titles = @[@"连接", @"测试帧", @"环境声10", @"环境声5", @"环境声18"];
    NSArray *sels = @[@"doConnect", @"doTest", @"lvl10", @"lvl5", @"lvl18"];
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
            [self.textView.bottomAnchor constraintEqualToAnchor:stack.topAnchor constant:-8],
            [stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:8],
            [stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-8],
            [stack.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-8],
            [stack.heightAnchor constraintEqualToConstant:44],
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
- (void)lvl10 { [self.tester sendLevel:10]; }
- (void)lvl5 { [self.tester sendLevel:5]; }
- (void)lvl18 { [self.tester sendLevel:18]; }

@end

@implementation BLETester

- (void)log:(NSString *)fmt, ... {
    va_list args;
    va_start(args, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    if (self.logger) self.logger(s);
}

- (void)begin {
    if (self.central == nil) {
        self.central = [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue()];
    } else if (self.central.state == CBManagerStatePoweredOn) {
        [self startScan];
    }
}

- (void)startScan {
    [self log:@"scan... center.state=%ld", (long)self.central.state];
    [self.central scanForPeripheralsWithServices:nil options:@{CBCentralManagerScanOptionAllowDuplicatesKey: @NO}];
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    [self log:@"central state=%ld", (long)central.state];
    if (central.state == CBManagerStatePoweredOn) [self startScan];
    else if (central.state == CBManagerStateUnauthorized) [self log:@"蓝牙权限被拒绝"];
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI {
    NSString *name = advertisementData[CBAdvertisementDataLocalNameKey] ?: peripheral.name ?: @"?";
    [self log:@"ADV %@ rssi=%@", name, RSSI];
    if (self.peripheral != nil) return;
    NSString *up = [name uppercaseString];
    if ([up containsString:@"XM6"] || [up containsString:@"1000X"] || [up containsString:@"SONY"]) {
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
    [self log:@"FAILCONNECT %@", error];
    self.peripheral = nil;
    [self startScan];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    [self log:@"DISCONNECT %@", error];
    self.peripheral = nil;
    self.writeChar = nil;
    self.writeChar11 = nil;
    self.startedTests = NO;
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    for (CBService *s in peripheral.services) {
        [self log:@"SERVICE %@", s.UUID.UUIDString];
        [peripheral discoverCharacteristics:nil forService:s];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    for (CBCharacteristic *c in service.characteristics) {
        NSString *u = c.UUID.UUIDString;
        if ([u hasPrefix:@"5B833C"] || [u hasPrefix:@"2A"]) {
            [self log:@"  CHAR %@ props=%lu", u, (unsigned long)c.properties];
        }
        if ([u isEqualToString:kWriteChar]) self.writeChar = c;
        if ([u isEqualToString:kNotifyChar]) {
            self.writeChar11 = self.writeChar11;
            [peripheral setNotifyValue:YES forCharacteristic:c];
            [self log:@"  subscribe %@", u];
        }
        if ([u isEqualToString:@"5B833C13-6BC7-4802-8E9A-723CECA4BD8F"] ||
            [u isEqualToString:@"5B833C1B-6BC7-4802-8E9A-723CECA4BD8F"]) {
            [peripheral setNotifyValue:YES forCharacteristic:c];
            [self log:@"  subscribe %@", u];
        }
    }
    if (self.writeChar && !self.startedTests) {
        self.startedTests = YES;
        [self log:@"ready: write char found"];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    NSData *d = characteristic.value ?: [NSData data];
    [self log:@"NOTIFY %@ len=%lu %@", characteristic.UUID.UUIDString, (unsigned long)d.length, [self hex:d]];
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if (error) [self log:@"WRITE-ERR %@ %@", characteristic.UUID.UUIDString, error];
}

- (NSString *)hex:(NSData *)d {
    const uint8_t *b = d.bytes;
    NSMutableString *s = [NSMutableString string];
    for (NSUInteger i = 0; i < d.length; i++) [s appendFormat:@"%02x ", b[i]];
    return s;
}

static NSData *EscapeSpecials(NSData *src) {
    NSMutableData *out = [NSMutableData data];
    const uint8_t *b = src.bytes;
    for (NSUInteger i = 0; i < src.length; i++) {
        if (b[i] == 60 || b[i] == 61 || b[i] == 62) {
            uint8_t e[2] = {61, (uint8_t)(b[i] == 60 ? 44 : (b[i] == 61 ? 45 : 46))};
            [out appendBytes:e length:2];
        } else {
            [out appendBytes:&b[i] length:1];
        }
    }
    return out;
}

static NSData *V1Frame(NSData *payload, uint8_t dataType, uint8_t seq, BOOL markers) {
    NSMutableData *body = [NSMutableData data];
    uint8_t head[6] = {dataType, seq, 0, 0, 0, (uint8_t)payload.length};
    [body appendBytes:head length:6];
    [body appendData:payload];
    const uint8_t *b = body.bytes;
    uint8_t sum = 0;
    for (NSUInteger i = 0; i < body.length; i++) sum = (uint8_t)(sum + b[i]);
    [body appendBytes:&sum length:1];
    NSData *esc = EscapeSpecials(body);
    if (!markers) return esc;
    NSMutableData *out = [NSMutableData data];
    uint8_t s = 62, e = 60;
    [out appendBytes:&s length:1];
    [out appendData:esc];
    [out appendBytes:&e length:1];
    return out;
}

static NSData *NCASMPayload(int level, int effect, int dualSingle) {
    uint8_t p[8] = {0x68, 0x02, (uint8_t)effect, 0x01, (uint8_t)dualSingle, 0x01, 0x00, (uint8_t)level};
    return [NSData dataWithBytes:p length:8];
}

- (void)sendLevel:(int)level {
    if (self.writeChar == nil || self.peripheral == nil) { [self log:@"未连接，先按连接"]; return; }
    if (level < 0) {
        NSArray *tests = @[
            @[@"A_v1_markers", V1Frame(NCASMPayload(10, 0x11, 0), 12, 0, YES)],
            @[@"B_v1_nomarkers", V1Frame(NCASMPayload(11, 0x11, 0), 12, 1, NO)],
            @[@"C_raw_payload", NCASMPayload(12, 0x11, 0)],
        ];
        [self runTests:tests index:0];
    } else {
        int ds = level == 1 ? 1 : (level == 0 ? 2 : 0);
        NSData *f = V1Frame(NCASMPayload(level, 0x11, ds), 12, (uint8_t)(level & 0xff), YES);
        [self log:@"SEND level=%d %@", level, [self hex:f]];
        [self.peripheral writeValue:f forCharacteristic:self.writeChar type:CBCharacteristicWriteWithResponse];
    }
}

- (void)runTests:(NSArray *)tests index:(NSUInteger)idx {
    if (idx >= tests.count) { [self log:@"tests done"]; return; }
    NSArray *t = tests[idx];
    NSData *d = t[1];
    [self log:@"WRITE %@ len=%lu %@", t[0], (unsigned long)d.length, [self hex:d]];
    [self.peripheral writeValue:d forCharacteristic:self.writeChar type:CBCharacteristicWriteWithResponse];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self runTests:tests index:idx + 1];
    });
}

@end
