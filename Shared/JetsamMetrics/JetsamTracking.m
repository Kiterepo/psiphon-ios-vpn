/*
 * Copyright (c) 2020, Psiphon Inc.
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#import "JetsamTracking.h"
#import "ExtensionContainerFile.h"
#import "NSError+Convenience.h"

#if TARGET_IS_CONTAINER || TARGET_IS_TEST

NSErrorDomain _Nonnull const ContainerJetsamTrackingErrorDomain = @"ContainerJetsamTrackingErrorDomain";

@implementation ContainerJetsamTracking

+ (JetsamMetrics*)getMetricsFromFilePath:(NSString*)filepath
                     withRotatedFilepath:(NSString*)rotatedFilepath
                        registryFilepath:(NSString*)registryFilepath
                           readChunkSize:(NSUInteger)readChunkSize
                               binRanges:(NSArray<BinRange*>*_Nullable)binRanges
                                   error:(NSError * _Nullable *)outError {

    *outError = nil;

    NSError *err;
    ContainerReaderRotatedFile *cont =
      [[ContainerReaderRotatedFile alloc] initWithFilepath:filepath
                                             olderFilepath:rotatedFilepath
                                          registryFilepath:registryFilepath
                                             readChunkSize:readChunkSize
                                                     error:&err];
    if (err != nil) {
        *outError = [NSError errorWithDomain:ContainerJetsamTrackingErrorDomain
                                        code:ContainerJetsamTrackingErrorInitFileReaderFailed
                         withUnderlyingError:err];
        return nil;
    }

    JetsamMetrics *metrics = [[JetsamMetrics alloc] initWithBinRanges:binRanges];
    JetsamEvent *prevEvent = nil;

    while (true) {
        NSString *line = [cont readLineWithError:&err];
        if (err != nil) {
            *outError = [NSError errorWithDomain:ContainerJetsamTrackingErrorDomain
                                            code:ContainerJetsamTrackingErrorReadingDataFailed
                             withUnderlyingError:err];
            return nil;
        }
        if (line == nil) {
            // Done reading. Persist the registry.
            [cont persistRegistry:&err];
            if (err != nil) {
                *outError = [NSError errorWithDomain:ContainerJetsamTrackingErrorDomain
                                                code:ContainerJetsamTrackingErrorPersistingRegistryFailed
                                 withUnderlyingError:err];
                return nil;
            }
            return metrics;
        }

        NSData *data = [[NSData alloc] initWithBase64EncodedData:[line dataUsingEncoding:NSUTF8StringEncoding]
                                                         options:kNilOptions];
        if (data == nil) {
            *outError = [NSError errorWithDomain:ContainerJetsamTrackingErrorDomain
                                            code:ContainerJetsamTrackingErrorDecodingDataFailed
                         andLocalizedDescription:@"data is nil"];
            return nil;
        }

        JetsamEvent *event = [JSONCodable jsonCodableDecodeObjectofClass:[JetsamEvent class]
                                                                    data:data
                                                                   error:&err];
        if (err != nil) {
            *outError = [NSError errorWithDomain:ContainerJetsamTrackingErrorDomain
                                            code:ContainerJetsamTrackingErrorUnarchivingDataFailed
                             withUnderlyingError:err];
            return nil;
        }

        // Count time since last jetsam if the last jetsam was of the same app version.
        if (prevEvent && [prevEvent.appVersion isEqualToString:event.appVersion]) {
            // This calculation is possible because jetsams are read back in
            // the order that they occured.
            // Note: rounded to the nearest second.
            NSTimeInterval timeSinceLastJetsam = round(event.jetsamDate - prevEvent.jetsamDate);
            if (timeSinceLastJetsam >= 0) {
                [metrics addJetsamForAppVersion:event.appVersion
                                    runningTime:event.runningTime
                            timeSinceLastJetsam:timeSinceLastJetsam];
            } else {
                // TODO: capture error for feedback
                [metrics addJetsamForAppVersion:event.appVersion
                                    runningTime:event.runningTime];
            }
        } else {
            [metrics addJetsamForAppVersion:event.appVersion
                                runningTime:event.runningTime];
        }

        prevEvent = event;
    }

}


@end

#endif

#if TARGET_IS_EXTENSION || TARGET_IS_TEST

NSErrorDomain _Nonnull const ExtensionJetsamTrackingErrorDomain = @"ExtensionJetsamTrackingErrorDomain";

@implementation ExtensionJetsamTracking

+ (void)logJetsamEvent:(JetsamEvent*)jetsamEvent
            toFilepath:(NSString*)filepath
   withRotatedFilepath:(NSString*)rotatedFilepath
      maxFilesizeBytes:(NSUInteger)maxFilesizeBytes
                 error:(NSError * _Nullable *)outError {

    *outError = nil;

    NSError *err;
    ExtensionWriterRotatedFile *ext =
      [[ExtensionWriterRotatedFile alloc] initWithFilepath:filepath
                                             olderFilepath:rotatedFilepath
                                          maxFilesizeBytes:maxFilesizeBytes
                                                     error:&err];
    if (err != nil) {
        *outError = [NSError errorWithDomain:ExtensionJetsamTrackingErrorDomain
                                        code:ExtensionJetsamTrackingErrorInitWriterFailed
                         withUnderlyingError:err];
        return;
    }

    NSData *encodedData = [JSONCodable jsonCodableEncodeObject:jetsamEvent error:&err];
    if (err != nil) {
        *outError = [NSError errorWithDomain:ExtensionJetsamTrackingErrorDomain
                                        code:ExtensionJetsamTrackingErrorArchiveDataFailed
                         withUnderlyingError:err];
        return;
    }
    NSString *b64EncodedString = [encodedData base64EncodedStringWithOptions:kNilOptions];
    NSMutableData *data = [NSMutableData dataWithData:[b64EncodedString dataUsingEncoding:NSASCIIStringEncoding]];
    [data appendData:[@"\n" dataUsingEncoding:NSASCIIStringEncoding]];

    [ext writeData:data error:&err];
    if (err != nil) {
        *outError = [NSError errorWithDomain:ExtensionJetsamTrackingErrorDomain
                                        code:ExtensionJetsamTrackingErrorWriteDataFailed
                     andLocalizedDescription:@"data is nil"];
        return;
    }

    return;
}

@end

#endif
