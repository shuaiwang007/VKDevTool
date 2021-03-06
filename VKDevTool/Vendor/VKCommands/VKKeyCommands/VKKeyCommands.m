//
//  JPKeyCommands.m
//
//  Created by Awhisper on 16/8/7.
//  Copyright © 2016年 baidu. All rights reserved.
//


#import "VKKeyCommands.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL VKIsIOS8OrEarlier()
{
    return [UIDevice currentDevice].systemVersion.floatValue < 9;
}


void VKSwapInstanceMethods(Class cls, SEL original, SEL replacement)
{
    Method originalMethod = class_getInstanceMethod(cls, original);
    IMP originalImplementation = method_getImplementation(originalMethod);
    const char *originalArgTypes = method_getTypeEncoding(originalMethod);
    
    Method replacementMethod = class_getInstanceMethod(cls, replacement);
    IMP replacementImplementation = method_getImplementation(replacementMethod);
    const char *replacementArgTypes = method_getTypeEncoding(replacementMethod);
    
    if (class_addMethod(cls, original, replacementImplementation, replacementArgTypes)) {
        class_replaceMethod(cls, replacement, originalImplementation, originalArgTypes);
    } else {
        method_exchangeImplementations(originalMethod, replacementMethod);
    }
}


#if TARGET_IPHONE_SIMULATOR

@interface VKKeyCommand : NSObject <NSCopying>

@property (nonatomic, strong) UIKeyCommand *keyCommand;
@property (nonatomic, copy) void (^block)(UIKeyCommand *);

@end

@implementation VKKeyCommand

- (instancetype)initWithKeyCommand:(UIKeyCommand *)keyCommand
                             block:(void (^)(UIKeyCommand *))block
{
    if ((self = [super init])) {
        _keyCommand = keyCommand;
        _block = block;
    }
    return self;
}


- (id)copyWithZone:(__unused NSZone *)zone
{
    return self;
}

- (NSUInteger)hash
{
    return _keyCommand.input.hash ^ _keyCommand.modifierFlags;
}

- (BOOL)isEqual:(VKKeyCommand *)object
{
    if (![object isKindOfClass:[VKKeyCommand class]]) {
        return NO;
    }
    return [self matchesInput:object.keyCommand.input
                        flags:object.keyCommand.modifierFlags];
}

- (BOOL)matchesInput:(NSString *)input flags:(UIKeyModifierFlags)flags
{
    return [_keyCommand.input isEqual:input] && _keyCommand.modifierFlags == flags;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@:%p input=\"%@\" flags=%zd hasBlock=%@>",
            [self class], self, _keyCommand.input, _keyCommand.modifierFlags,
            _block ? @"YES" : @"NO"];
}

@end

@interface VKKeyCommands ()

@property (nonatomic, strong) NSMutableSet<VKKeyCommand *> *commands;

@end

@implementation UIResponder (RCTKeyCommands)

- (NSArray<UIKeyCommand *> *)JP_keyCommands
{
    NSSet<VKKeyCommand *> *commands = [VKKeyCommands sharedInstance].commands;
    return [[commands valueForKeyPath:@"keyCommand"] allObjects];
}


- (void)JP_handleKeyCommand:(UIKeyCommand *)key
{
    // NOTE: throttle the key handler because on iOS 9 the handleKeyCommand:
    // method gets called repeatedly if the command key is held down.
    
    static NSTimeInterval lastCommand = 0;
    if (VKIsIOS8OrEarlier() || CACurrentMediaTime() - lastCommand > 0.5) {
        for (VKKeyCommand *command in [VKKeyCommands sharedInstance].commands) {
            if ([command.keyCommand.input isEqualToString:key.input] &&
                command.keyCommand.modifierFlags == key.modifierFlags) {
                if (command.block) {
                    command.block(key);
                    lastCommand = CACurrentMediaTime();
                }
            }
        }
    }
}

@end

@implementation UIApplication (VKKeyCommands)

// Required for iOS 8.x
- (BOOL)JP_sendAction:(SEL)action to:(id)target from:(id)sender forEvent:(UIEvent *)event
{
    if (action == @selector(JP_handleKeyCommand:)) {
        [self JP_handleKeyCommand:sender];
        return YES;
    }
    return [self JP_sendAction:action to:target from:sender forEvent:event];
}

@end

@implementation VKKeyCommands

+ (void)initialize
{
    if (VKIsIOS8OrEarlier()) {
        
        //swizzle UIApplication
        VKSwapInstanceMethods([UIApplication class],
                              @selector(keyCommands),
                              @selector(JP_keyCommands));
        
        VKSwapInstanceMethods([UIApplication class],
                              @selector(sendAction:to:from:forEvent:),
                              @selector(JP_sendAction:to:from:forEvent:));
    } else {
        
        //swizzle UIResponder
        VKSwapInstanceMethods([UIResponder class],
                              @selector(keyCommands),
                              @selector(JP_keyCommands));
    }
}

+ (instancetype)sharedInstance
{
    static VKKeyCommands *sharedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [self new];
    });
    
    return sharedInstance;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _commands = [NSMutableSet new];
    }
    return self;
}

- (void)registerKeyCommandWithInput:(NSString *)input
                      modifierFlags:(UIKeyModifierFlags)flags
                             action:(void (^)(UIKeyCommand *))block
{
    
    if (input.length && flags && VKIsIOS8OrEarlier()) {
        
        // Workaround around the first cmd not working: http://openradar.appspot.com/19613391
        // You can register just the cmd key and do nothing. This ensures that
        // command-key modified commands will work first time. Fixed in iOS 9.
        
        [self registerKeyCommandWithInput:@""
                            modifierFlags:flags
                                   action:nil];
    }
    
    UIKeyCommand *command = [UIKeyCommand keyCommandWithInput:input
                                                modifierFlags:flags
                                                       action:@selector(JP_handleKeyCommand:)];
    
    VKKeyCommand *keyCommand = [[VKKeyCommand alloc] initWithKeyCommand:command block:block];
    [_commands removeObject:keyCommand];
    [_commands addObject:keyCommand];
}

- (void)unregisterKeyCommandWithInput:(NSString *)input
                        modifierFlags:(UIKeyModifierFlags)flags
{
    
    for (VKKeyCommand *command in _commands.allObjects) {
        if ([command matchesInput:input flags:flags]) {
            [_commands removeObject:command];
            break;
        }
    }
}

- (BOOL)isKeyCommandRegisteredForInput:(NSString *)input
                         modifierFlags:(UIKeyModifierFlags)flags
{
    
    for (VKKeyCommand *command in _commands) {
        if ([command matchesInput:input flags:flags]) {
            return YES;
        }
    }
    return NO;
}

@end

#else

@implementation VKKeyCommands

+ (instancetype)sharedInstance
{
    return nil;
}

- (void)registerKeyCommandWithInput:(NSString *)input
                      modifierFlags:(UIKeyModifierFlags)flags
                             action:(void (^)(UIKeyCommand *))block {

};

- (void)unregisterKeyCommandWithInput:(NSString *)input
                        modifierFlags:(UIKeyModifierFlags)flags {

};

- (BOOL)isKeyCommandRegisteredForInput:(NSString *)input
                         modifierFlags:(UIKeyModifierFlags)flags
{
    return NO;
}

@end

#endif

