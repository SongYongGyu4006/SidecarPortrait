// Sidecar 세로 모드 실험 도구 (SidecarCore 비공개 API)
//   빌드: clang -fobjc-arc -framework Foundation sidecar-portrait.m -o sidecar-portrait
//   사용: ./sidecar-portrait list
//         ./sidecar-portrait connect <기기이름> [width height [scale]]   (기본: 1024x1366 @2x)
//         ./sidecar-portrait disconnect <기기이름>
#import <Foundation/Foundation.h>
#include <dlfcn.h>

@interface SidecarDevice : NSObject
@property (readonly) NSString *name;
@property (readonly) NSString *model;
@end

@interface SidecarDisplayConfig : NSObject
@property CGSize size;
@property double scale;
@end

@interface SidecarDisplayManager : NSObject
+ (instancetype)sharedManager;
@property (readonly) NSArray<SidecarDevice *> *devices;
@property (readonly) NSArray<SidecarDevice *> *connectedDevices;
- (SidecarDisplayConfig *)configForDevice:(SidecarDevice *)device;
- (void)connectToDevice:(SidecarDevice *)device withConfig:(SidecarDisplayConfig *)config completion:(void (^)(NSError *))completion;
- (void)disconnectFromDevice:(SidecarDevice *)device completion:(void (^)(NSError *))completion;
@end

static SidecarDevice *findDevice(SidecarDisplayManager *m, const char *name) {
    for (SidecarDevice *d in m.devices)
        if ([d.name isEqualToString:@(name)]) return d;
    fprintf(stderr, "기기를 찾지 못했어요: %s\n", name);
    exit(1);
}

static void waitFor(void (^start)(void (^done)(NSError *))) {
    __block BOOL finished = NO;
    start(^(NSError *err) {
        printf("%s\n", err ? err.description.UTF8String : "완료");
        finished = YES;
    });
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:30];
    while (!finished && [limit timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    if (!finished) printf("30초 안에 응답이 없어요\n");
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (!dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_NOW)) {
            fprintf(stderr, "dlopen: %s\n", dlerror());
            return 1;
        }
        SidecarDisplayManager *m = [NSClassFromString(@"SidecarDisplayManager") sharedManager];
        // 기기 목록이 비동기로 채워지므로 잠깐 기다림
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
        NSString *cmd = argc > 1 ? @(argv[1]) : @"list";

        if ([cmd isEqualToString:@"list"]) {
            for (SidecarDevice *d in m.devices) {
                SidecarDisplayConfig *c = [m configForDevice:d];
                printf("%s (%s)%s\n  config: size=%.0fx%.0f scale=%.2f\n  %s\n", d.name.UTF8String, d.model.UTF8String,
                       [m.connectedDevices containsObject:d] ? " [연결됨]" : "",
                       c.size.width, c.size.height, c.scale, c.description.UTF8String);
            }
            if (m.devices.count == 0) printf("Sidecar 기기가 없어요 (같은 Apple 계정, Wi‑Fi·Bluetooth 켜짐, iPad 잠금 해제 확인)\n");
        } else if ([cmd isEqualToString:@"connect"] && argc > 2) {
            SidecarDevice *d = findDevice(m, argv[2]);
            // configForDevice:는 저장된 설정이 없으면 nil이고, 새 config는 size 0(시스템이 결정)으로 시작함
            SidecarDisplayConfig *c = [m configForDevice:d] ?: [NSClassFromString(@"SidecarDisplayConfig") new];
            // 기본값은 iPad Pro 12.9인치 Sidecar 기본 해상도(1366x1024 @2x)를 세로로 뒤집은 것
            c.size = argc > 4 ? CGSizeMake(atof(argv[3]), atof(argv[4])) : CGSizeMake(1024, 1366);
            c.scale = argc > 5 ? atof(argv[5]) : 2.0;
            printf("연결 시도: size=%.0fx%.0f scale=%.2f\n", c.size.width, c.size.height, c.scale);
            waitFor(^(void (^done)(NSError *)) { [m connectToDevice:d withConfig:c completion:done]; });
        } else if ([cmd isEqualToString:@"disconnect"] && argc > 2) {
            SidecarDevice *d = findDevice(m, argv[2]);
            waitFor(^(void (^done)(NSError *)) { [m disconnectFromDevice:d completion:done]; });
        } else {
            fprintf(stderr, "사용법: list | connect <기기이름> [w h [scale]] | disconnect <기기이름>\n");
            return 1;
        }
    }
    return 0;
}
