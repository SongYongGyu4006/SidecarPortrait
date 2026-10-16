#import "PrivateAPI.h"
#include <dlfcn.h>

// 비공개 클래스는 링크하지 않고 NSClassFromString으로 찾는다.
// 아래 프로토콜은 런타임 덤프(objc_copyClassNamesForImage)로 확인한 메서드 시그니처.

@protocol CGVirtualDisplayModeP
- (id)initWithWidth:(unsigned)width height:(unsigned)height refreshRate:(double)refreshRate;
@end

@protocol CGVirtualDisplayDescriptorP
@property (retain) dispatch_queue_t queue;
@property (retain) NSString *name;
@property unsigned maxPixelsWide;
@property unsigned maxPixelsHigh;
@property CGSize sizeInMillimeters;
@property unsigned vendorID;
@property unsigned productID;
@property unsigned serialNum;
@property (copy) void (^terminationHandler)(id, id);
@end

@protocol CGVirtualDisplaySettingsP
@property (retain) NSArray *modes;
@property unsigned hiDPI;
@end

@protocol CGVirtualDisplayP
- (id)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
@property (readonly) unsigned displayID;
@end

@protocol SidecarDeviceP
@property (readonly) NSString *name;
@end

@protocol SidecarDisplayConfigP
@property CGSize size;
@property double scale;
@end

@protocol SidecarDisplayManagerP
@property (readonly) NSArray *devices;
@property (readonly) NSArray *connectedDevices;
- (id)configForDevice:(id)device;
- (void)connectToDevice:(id)device withConfig:(id)config completion:(void (^)(NSError *))completion;
- (void)disconnectFromDevice:(id)device completion:(void (^)(NSError *))completion;
@end

@implementation SPVirtualDisplay {
    id<CGVirtualDisplayP> _display;
}

- (instancetype)initWithName:(NSString *)name width:(unsigned)width height:(unsigned)height hiDPI:(BOOL)hiDPI {
    if (!(self = [super init])) return nil;
    unsigned factor = hiDPI ? 2 : 1;

    id<CGVirtualDisplayDescriptorP> desc = [NSClassFromString(@"CGVirtualDisplayDescriptor") new];
    desc.queue = dispatch_get_main_queue();
    desc.name = name;
    desc.maxPixelsWide = width * factor;
    desc.maxPixelsHigh = height * factor;
    // iPad Pro 12.9인치 화면 크기(세로)
    desc.sizeInMillimeters = CGSizeMake(197, 262);
    desc.vendorID = 0xEEEE;
    desc.productID = 0x5350;
    desc.serialNum = 1;
    desc.terminationHandler = ^(id a, id b) { NSLog(@"가상 디스플레이가 종료됐어요"); };

    _display = [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:desc];
    if (!_display) return nil;

    id<CGVirtualDisplaySettingsP> settings = [NSClassFromString(@"CGVirtualDisplaySettings") new];
    settings.hiDPI = hiDPI ? 1 : 0;
    settings.modes = @[[[NSClassFromString(@"CGVirtualDisplayMode") alloc] initWithWidth:width height:height refreshRate:60]];
    if (![_display applySettings:settings]) return nil;
    return self;
}

- (CGDirectDisplayID)displayID {
    return _display.displayID;
}

@end

@implementation SPSidecar

+ (id<SidecarDisplayManagerP>)manager {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_NOW);
    });
    return [NSClassFromString(@"SidecarDisplayManager") performSelector:@selector(sharedManager)];
}

+ (NSArray<NSString *> *)namesOf:(NSArray *)devices {
    NSMutableArray *names = [NSMutableArray array];
    for (id<SidecarDeviceP> d in devices) [names addObject:d.name];
    return names;
}

+ (NSArray<NSString *> *)deviceNames {
    return [self namesOf:[self manager].devices];
}

+ (NSArray<NSString *> *)connectedDeviceNames {
    return [self namesOf:[self manager].connectedDevices];
}

+ (nullable id)deviceNamed:(NSString *)name {
    for (id<SidecarDeviceP> d in [self manager].devices)
        if ([d.name isEqualToString:name]) return d;
    return nil;
}

+ (NSError *)notFound:(NSString *)name {
    return [NSError errorWithDomain:@"SidecarPortrait" code:1
                           userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"기기를 찾지 못했어요: %@", name]}];
}

+ (void)connectDevice:(NSString *)name size:(CGSize)size scale:(double)scale completion:(void (^)(NSError *))completion {
    id<SidecarDisplayManagerP> m = [self manager];
    id device = [self deviceNamed:name];
    if (!device) return completion([self notFound:name]);
    // configForDevice:는 저장된 설정이 없으면 nil
    id<SidecarDisplayConfigP> config = [m configForDevice:device] ?: [NSClassFromString(@"SidecarDisplayConfig") new];
    config.size = size;
    config.scale = scale;
    [m connectToDevice:device withConfig:config completion:completion];
}

+ (void)disconnectDevice:(NSString *)name completion:(void (^)(NSError *))completion {
    id device = [self deviceNamed:name];
    if (!device) return completion([self notFound:name]);
    [[self manager] disconnectFromDevice:device completion:completion];
}

+ (CGDirectDisplayID)displayID {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel", RTLD_NOW);
    });
    // MPDisplayMgr는 만들 때의 디스플레이 목록을 쓰므로 매번 새로 만든다
    id mgr = [NSClassFromString(@"MPDisplayMgr") new];
    for (id d in [mgr valueForKey:@"displays"])
        if ([[d valueForKey:@"isSidecarDisplay"] boolValue]) return [[d valueForKey:@"displayID"] unsignedIntValue];
    return kCGNullDirectDisplay;
}

@end
