#import "SettingsViewController.h"
#import "AppSettings.h"

@interface SettingsViewController ()
@property (nonatomic, strong) UISwitch *fileSwitch;
@property (nonatomic, strong) UISwitch *showSwitch;
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"设置";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:20];
    title.textAlignment = NSTextAlignmentCenter;

    UILabel *fileLabel = [self labelWithText:@"文件输出日志" detail:@"写入 Documents/xm6.log，上限 1MB"];
    self.fileSwitch = [[UISwitch alloc] init];
    self.fileSwitch.on = [AppSettings fileLogEnabled];
    [self.fileSwitch addTarget:self action:@selector(fileToggled) forControlEvents:UIControlEventValueChanged];

    UILabel *showLabel = [self labelWithText:@"显示日志" detail:@"在界面下方显示收发记录"];
    self.showSwitch = [[UISwitch alloc] init];
    self.showSwitch.on = [AppSettings showLogEnabled];
    [self.showSwitch addTarget:self action:@selector(showToggled) forControlEvents:UIControlEventValueChanged];

    UIStackView *fileRow = [self rowWith:fileLabel control:self.fileSwitch];
    UIStackView *showRow = [self rowWith:showLabel control:self.showSwitch];

    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:@"完成" forState:UIControlStateNormal];
    [done.titleLabel setFont:[UIFont boldSystemFontOfSize:17]];
    [done setTitleColor:[UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0] forState:UIControlStateNormal];
    [done addTarget:self action:@selector(doneTapped) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, fileRow, showRow, done]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 26;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:g.topAnchor constant:48],
        [stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:28],
        [stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-28],
        [done.heightAnchor constraintEqualToConstant:44],
    ]];
}

- (UILabel *)labelWithText:(NSString *)text detail:(NSString *)detail {
    UILabel *l = [[UILabel alloc] init];
    l.numberOfLines = 2;
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n%@", text, detail]];
    [s addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:16] range:NSMakeRange(0, text.length)];
    [s addAttribute:NSForegroundColorAttributeName value:[UIColor whiteColor] range:NSMakeRange(0, text.length)];
    [s addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:11] range:NSMakeRange(text.length, s.length - text.length)];
    [s addAttribute:NSForegroundColorAttributeName value:[UIColor colorWithWhite:0.55 alpha:1.0] range:NSMakeRange(text.length, s.length - text.length)];
    l.attributedText = s;
    return l;
}

- (UIStackView *)rowWith:(UILabel *)label control:(UIView *)control {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[label, control]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    [label setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [control setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    return row;
}

- (void)fileToggled {
    [AppSettings setFileLogEnabled:self.fileSwitch.on];
}

- (void)showToggled {
    [AppSettings setShowLogEnabled:self.showSwitch.on];
}

- (void)doneTapped {
    if (self.onClose) self.onClose();
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
