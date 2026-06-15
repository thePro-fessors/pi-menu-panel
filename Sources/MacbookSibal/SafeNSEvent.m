#import "SafeNSEvent.h"

@implementation SafeNSEvent
+ (NSInteger)safeStageForEvent:(NSEvent *)event {
    @try {
        if ([event respondsToSelector:@selector(stage)]) {
            return [event stage];
        }
    } @catch (NSException *exception) {
        return 0;
    }
    return 0;
}
@end
