#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// CGVirtualDisplay로 만든 가상 디스플레이. 이 객체가 살아 있는 동안만 디스플레이가 유지된다.
@interface SPVirtualDisplay : NSObject
/// width·height는 포인트 단위. hiDPI면 실제 픽셀은 2배.
- (nullable instancetype)initWithName:(NSString *)name width:(unsigned)width height:(unsigned)height hiDPI:(BOOL)hiDPI;
@property (readonly) CGDirectDisplayID displayID;
@end

/// SidecarCore의 SidecarDisplayManager 래퍼
@interface SPSidecar : NSObject
+ (NSArray<NSString *> *)deviceNames;
+ (NSArray<NSString *> *)connectedDeviceNames;
/// size는 포인트 단위. 0x0이면 시스템 기본값.
+ (void)connectDevice:(NSString *)name size:(CGSize)size scale:(double)scale completion:(void (^)(NSError *_Nullable error))completion;
+ (void)disconnectDevice:(NSString *)name completion:(void (^)(NSError *_Nullable error))completion;
/// 현재 연결된 Sidecar 디스플레이 ID (MonitorPanel의 isSidecarDisplay). 없으면 kCGNullDirectDisplay.
+ (CGDirectDisplayID)displayID;
@end

NS_ASSUME_NONNULL_END
