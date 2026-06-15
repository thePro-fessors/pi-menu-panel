#import <AppKit/AppKit.h>

@interface SafeNSEvent : NSObject
+ (NSInteger)safeStageForEvent:(NSEvent *)event;
@end
