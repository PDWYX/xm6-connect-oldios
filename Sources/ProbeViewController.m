#import "ProbeViewController.h"
#import <ExternalAccessory/ExternalAccessory.h>
#import "EATester.h"
#import "AppSettings.h"
#import "SettingsViewController.h"
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

    UIButton *settings = [UIButton buttonWithType:UIButtonTypeSystem];
    [settings setTitle:@"设置" forState:UIControlStateNormal];
    [settings setTitleColor:[UIColor colorWithWhite:0.6 alpha:1.0] forState:UIControlStateNormal];
    [settings addTarget:self action:@selector(settingsTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *btnRow = [[UIStackView alloc] initWithArrangedSubviews:@[reconnect, picker, settings]];
    btnRow.axis = UILayoutConstraintAxisHorizontal;
    btnRow.spacing = 12;
    btnRow.distribution = UIStackViewDistributionFillEqually;

    self.logView = [[UITextView alloc] init];
    self.logView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
    self.logView.textColor = [UIColor colorWithRed:0.5 green:0.9 blue:0.5 alpha:1.0];
    self.logView.font = [UIFont fontWithName:@"Menlo" size:9] ?: [UIFont systemFontOfSize:9];
    self.logView.editable = NO;
    self.logView.hidden = ![AppSettings showLogEnabled];

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
    self.ea.connectionHandler = ^(BOOL connected) { [weakSelf applyConnected:connected]; };
    [self.ea begin];
}

- (void)applyConnected:(BOOL)connected {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (connected) {
            self.statusLabel.text = @"WH-1000XM6 已连接";
            self.statusLabel.textColor = [UIColor whiteColor];
        } else {
            self.statusLabel.text = @"未连接";
            self.statusLabel.textColor = [UIColor redColor];
            self.modeControl.selectedSegmentIndex = UISegmentedControlNoSegment;
        }
    });
}

- (void)appendLog:(NSString *)line {
    if (![AppSettings showLogEnabled]) return;
    [self.logBuffer appendFormat:@"%@\n", line];
    if (self.logBuffer.length > 8000) {
        [self.logBuffer deleteCharactersInRange:NSMakeRange(0, self.logBuffer.length - 6000)];
    }
    NSString *t = [self.logBuffer copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.logView.text = t;
        if (t.length) [self.logView scrollRangeToVisible:NSMakeRange(t.length, 0)];
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

- (void)settingsTapped {
    SettingsViewController *vc = [[SettingsViewController alloc] init];
    __weak typeof(self) weakSelf = self;
    vc.onClose = ^{ [weakSelf applyLogVisibility]; };
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)applyLogVisibility {
    BOOL show = [AppSettings showLogEnabled];
    self.logView.hidden = !show;
    if (show) self.logView.text = self.logBuffer;
}

- (void)reconnectTapped {
    [self appendLog:@"--- 重新连接 ---"];
    [self.ea openSession];
}

@end