#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#import <mach/mach.h>

#define GB_BLUE   [UIColor colorWithRed:0.20 green:0.60 blue:1.00 alpha:1.0]
#define GB_RED    [UIColor colorWithRed:1.00 green:0.35 blue:0.35 alpha:1.0]
#define GB_BLACK  [UIColor colorWithWhite:0.04 alpha:0.82]

static BOOL      gShowHUD = YES;
static NSInteger gCap = 60;
static CGFloat   gScale = 1.0;
static BOOL      gAutoThermal = YES;
static NSInteger gEffectiveCap = 60;
static NSInteger gPing = -1;
static NSHashTable *gLinks;
static UIView   *gBox;
static UIView   *gPill;
static UILabel  *gHUD;
static UIButton *gBtn;
static CADisplayLink *gMeter;
static CFTimeInterval gLastT;
static volatile int32_t gMetalFrames = 0;
static NSInteger gTicks = 0;
static char kReq;

static void GBLoad(void) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if ([d objectForKey:@"gb_hud"])   gShowHUD = [d boolForKey:@"gb_hud"];
    if ([d objectForKey:@"gb_cap"])   gCap = [d integerForKey:@"gb_cap"];
    if ([d objectForKey:@"gb_scale"]) gScale = [d floatForKey:@"gb_scale"];
    if ([d objectForKey:@"gb_auto"])  gAutoThermal = [d boolForKey:@"gb_auto"];
}

static void GBSave(void) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setBool:gShowHUD forKey:@"gb_hud"];
    [d setInteger:gCap forKey:@"gb_cap"];
    [d setFloat:gScale forKey:@"gb_scale"];
    [d setBool:gAutoThermal forKey:@"gb_auto"];
}

static NSString *GBThermalName(NSProcessInfoThermalState s) {
    switch (s) {
        case NSProcessInfoThermalStateNominal:  return @"COOL";
        case NSProcessInfoThermalStateFair:     return @"WARM";
        case NSProcessInfoThermalStateSerious:  return @"HOT";
        case NSProcessInfoThermalStateCritical: return @"CRITICAL";
    }
    return @"?";
}

static double GBMemoryMB(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return 0;
    return info.phys_footprint / 1048576.0;
}

static UIWindow *GBWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:UIWindowScene.class]) {
                for (UIWindow *w in ((UIWindowScene *)s).windows) if (w.isKeyWindow) return w;
            }
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

static void GBApplyCap(void) {
    NSInteger cap = gCap;
    if (gAutoThermal) {
        NSProcessInfoThermalState t = NSProcessInfo.processInfo.thermalState;
        if (t >= NSProcessInfoThermalStateSerious && cap > 30) cap = 30;
    }
    gEffectiveCap = cap;
    for (CADisplayLink *l in gLinks.allObjects) {
        NSNumber *req = objc_getAssociatedObject(l, &kReq);
        if (req) [l setPreferredFramesPerSecond:req.integerValue];
    }
}

@interface GBHelper : NSObject
+ (instancetype)shared;
- (void)tick:(CADisplayLink *)link;
- (void)openMenu;
- (void)pan:(UIPanGestureRecognizer *)g;
- (void)thermalChanged;
- (void)pingNow;
@end

@implementation GBHelper
+ (instancetype)shared {
    static GBHelper *h; static dispatch_once_t o;
    dispatch_once(&o, ^{ h = [GBHelper new]; });
    return h;
}

- (void)tick:(CADisplayLink *)link {
    gTicks++;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - gLastT < 1.0) return;
    double dt = now - gLastT;
    int32_t metal = __atomic_exchange_n(&gMetalFrames, 0, __ATOMIC_RELAXED);
    NSInteger fps = metal > 0 ? (NSInteger)round(metal / dt) : (NSInteger)round(gTicks / dt);
    gTicks = 0; gLastT = now;

    NSProcessInfoThermalState t = NSProcessInfo.processInfo.thermalState;
    NSString *pingStr = gPing >= 0 ? [NSString stringWithFormat:@"%ldms", (long)gPing] : @"--";
    gHUD.text = [NSString stringWithFormat:@"%ld/%ld FPS · %@\n%.0fMB · %@ · %.0f%%",
        (long)fps, (long)gEffectiveCap, GBThermalName(t),
        GBMemoryMB(), pingStr, gScale * 100];
    gHUD.textColor = (t >= NSProcessInfoThermalStateSerious) ? GB_RED : GB_BLUE;
    gPill.hidden = !gShowHUD;
}

- (void)thermalChanged { GBApplyCap(); }

- (void)pingNow {
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://www.cloudflare.com"]];
    r.HTTPMethod = @"HEAD";
    r.timeoutInterval = 4;
    r.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    CFTimeInterval s = CACurrentMediaTime();
    [[NSURLSession.sharedSession dataTaskWithRequest:r completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
        gPing = e ? -1 : (NSInteger)((CACurrentMediaTime() - s) * 1000);
    }] resume];
}

- (void)pan:(UIPanGestureRecognizer *)g {
    UIView *v = g.view;
    CGPoint p = [g translationInView:v.superview];
    v.center = CGPointMake(v.center.x + p.x, v.center.y + p.y);
    [g setTranslation:CGPointZero inView:v.superview];
}

- (void)openMenu {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"GAME BOOST"
        message:@"Premium Blue Edition" preferredStyle:UIAlertControllerStyleAlert];
    a.view.tintColor = GB_BLUE;

    [a addAction:[UIAlertAction actionWithTitle:gShowHUD ? @"FPS HUD: ON" : @"FPS HUD: OFF"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            gShowHUD = !gShowHUD; GBSave(); gPill.hidden = !gShowHUD;
        }]];

    [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Frame cap: %ld (tap to toggle 30/60)", (long)gCap]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { gCap = (gCap == 60) ? 30 : 60; GBSave(); GBApplyCap(); }]];

    [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Resolution: %.0f%% (tap to cycle)", gScale * 100]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            gScale = (gScale > 0.95) ? 0.85 : (gScale > 0.80 ? 0.70 : 1.0); GBSave();
        }]];

    [a addAction:[UIAlertAction actionWithTitle:gAutoThermal ? @"Auto cooling: ON" : @"Auto cooling: OFF"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { gAutoThermal = !gAutoThermal; GBSave(); GBApplyCap(); }]];

    [a addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];

    UIViewController *top = GBWindow().rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:a animated:YES completion:nil];
}
@end

static void GBSetupUI(void) {
    UIWindow *w = GBWindow();
    if (!w) return;
    if (gBox.superview == w) return;

    if (!gBox) {
        CGFloat top = MAX(w.safeAreaInsets.top, 20.0) + 4.0;
        CGFloat left = w.safeAreaInsets.left + 8.0;
        gBox = [[UIView alloc] initWithFrame:CGRectMake(left, top, 152, 40)];

        gPill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 118, 40)];
        gPill.backgroundColor = GB_BLACK;
        gPill.layer.cornerRadius = 8;
        gPill.layer.borderWidth = 1;
        gPill.layer.borderColor = GB_BLUE.CGColor;
        gPill.layer.masksToBounds = YES;

        gHUD = [[UILabel alloc] initWithFrame:CGRectMake(6, 3, 106, 34)];
        gHUD.numberOfLines = 2;
        gHUD.font = [UIFont fontWithName:@"Menlo-Bold" size:10];
        gHUD.adjustsFontSizeToFitWidth = YES;
        gHUD.minimumScaleFactor = 0.7;
        gHUD.textColor = GB_BLUE;
        gHUD.text = @"GAME BOOST";
        [gPill addSubview:gHUD];

        gBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        gBtn.frame = CGRectMake(122, 5, 30, 30);
        gBtn.backgroundColor = GB_BLACK;
        gBtn.layer.cornerRadius = 8;
        gBtn.layer.borderWidth = 1;
        gBtn.layer.borderColor = GB_BLUE.CGColor;
        [gBtn setTitle:@"⚡" forState:UIControlStateNormal];
        [gBtn addTarget:GBHelper.shared action:@selector(openMenu) forControlEvents:UIControlEventTouchUpInside];

        [gBox addSubview:gPill];
        [gBox addSubview:gBtn];
        [gBox addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:GBHelper.shared action:@selector(pan:)]];
    }
    [w addSubview:gBox];
    gPill.hidden = !gShowHUD;
}

%hook CADisplayLink
- (void)setPreferredFramesPerSecond:(NSInteger)fps {
    objc_setAssociatedObject(self, &kReq, @(fps), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!gLinks) gLinks = [NSHashTable weakObjectsHashTable];
    [gLinks addObject:self];
    NSInteger f = (fps == 0) ? 60 : fps;
    if (f > gEffectiveCap) f = gEffectiveCap;
    %orig(f);
}
%end

%hook CAMetalLayer
- (id<CAMetalDrawable>)nextDrawable {
    __atomic_fetch_add(&gMetalFrames, 1, __ATOMIC_RELAXED);
    return %orig;
}
- (void)setDrawableSize:(CGSize)size {
    if (gScale < 0.99 && size.width > 400) {
        size = CGSizeMake(floor(size.width * gScale), floor(size.height * gScale));
    }
    %orig(size);
}
%end

%ctor {
    @autoreleasepool {
        GBLoad();
        gEffectiveCap = gCap;
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
                GBSetupUI();
                if (!gMeter) {
                    gLastT = CACurrentMediaTime();
                    gMeter = [CADisplayLink displayLinkWithTarget:GBHelper.shared selector:@selector(tick:)];
                    [gMeter addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
                    [NSTimer scheduledTimerWithTimeInterval:5 target:GBHelper.shared
                        selector:@selector(pingNow) userInfo:nil repeats:YES];
                }
                GBApplyCap();
            }];
        [[NSNotificationCenter defaultCenter] addObserver:GBHelper.shared
            selector:@selector(thermalChanged)
            name:NSProcessInfoThermalStateDidChangeNotification object:nil];
    }
}
