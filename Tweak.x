#import <QuartzCore/QuartzCore.h>

%hook CADisplayLink

- (void)setPreferredFramesPerSecond:(NSInteger)fps {
    %orig(fps > 60 ? 60 : fps);
}

%end
