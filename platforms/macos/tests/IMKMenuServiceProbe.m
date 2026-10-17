#import "IMKMenuServiceProbe.h"
#import <objc/runtime.h>

@interface LampyrisMenuProbeClient : NSObject
@end

@implementation LampyrisMenuProbeClient
- (BOOL)usesXPC { return NO; }
- (id)_clientDOProxy { return self; }
@end

BOOL LampyrisProbeDispatchMenuCommand(IMKServer *server, IMKInputController *controller,
                                    NSMenuItem *item, NSInteger command) {
    // Use a private service boundary only in the unregistered test app. The public
    // controller API alone bypasses the server's accepted-action validation.
    Class cls = object_getClass(server);
    SEL menuSelector = NSSelectorFromString(@"menusDictionary_CommonWithController:");
    SEL dispatchSelector = NSSelectorFromString(
        @"doCommandBySelector_Common:commandDictionary:clientWrapper:controller:");
    Method menuMethod = class_getInstanceMethod(cls, menuSelector);
    Method dispatchMethod = class_getInstanceMethod(cls, dispatchSelector);
    if (!menuMethod || !dispatchMethod || !item.action) return NO;
    id (*menu)(id, SEL, id) = (void *)method_getImplementation(menuMethod);
    void (*dispatch)(id, SEL, SEL, id, id, id) = (void *)method_getImplementation(dispatchMethod);
    if (!menu(server, menuSelector, controller)) return NO;
    // Service input carries the numeric command plus a title. IMK resolves the
    // original item before forwarding the public command dictionary to the host.
    NSDictionary *info = @{kIMKCommandMenuItemName: @(command), @"IMKMenuTitle": item.title};
    dispatch(server, dispatchSelector, item.action, info, [LampyrisMenuProbeClient new], controller);
    return YES;
}
