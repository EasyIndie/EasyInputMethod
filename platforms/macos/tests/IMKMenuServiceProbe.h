#import <InputMethodKit/InputMethodKit.h>

// Diagnostic-only adapter; never link this object into the input method host.
BOOL LampyrisProbeDispatchMenuCommand(IMKServer *server, IMKInputController *controller,
                                    NSMenuItem *item, NSInteger command);
