//
//  MYDigest.m
//  MYCrypto
//
//  Created by Jens Alfke on 1/4/08.
//  Copyright 2008 Jens Alfke. All rights reserved.
//

#import "MYDigest.h"
#import "Test.h"
#import "MYLogging.h"

#import <CommonCrypto/CommonDigest.h>

#if TARGET_OS_IPHONE
#import <CommonCrypto/CommonHMAC.h>
#endif


@implementation MYDigest

+ (uint32_t) algorithm {
    AssertAbstractMethod();
}

+ (size_t) length {
    AssertAbstractMethod();
}

+ (void) computeDigest: (void*)dstDigest ofBytes: (const void*)bytes length: (size_t)length {
    AssertAbstractMethod();
}


- (id) initWithRawDigest: (const void*)rawDigest length: (size_t)length {
    Assert([self class] != [MYDigest class], @"MYDigest is an abstract class");
    Assert(rawDigest!=NULL);
    AssertEq(length,[[self class] length]);
    self = [super init];
    if (self) {
        _rawDigest = malloc(length);
        Assert(_rawDigest);
        memcpy(_rawDigest,rawDigest,length);
    }
    return self;
}

- (void) dealloc
{
    if(_rawDigest) free(_rawDigest);
}



- (id) copyWithZone: (NSZone*)zone
{
    return self;
}

- (id)initWithCoder:(NSCoder *)decoder
{
    NSUInteger length;
    const void *bytes = [decoder decodeBytesForKey: @"digest" returnedLength: &length];
    return [self initWithRawDigest: bytes length: length];
}


- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeBytes: self.bytes length: self.length forKey: @"digest"];
}


+ (id) digestFromDigestData: (NSData*)digestData {
    return [[self alloc] initWithRawDigest: digestData.bytes length: digestData.length];
}

+ (id) digestFromHexString: (NSString*)hexString
{
    const char *cStr = [hexString UTF8String];
    const size_t length = [self length];
    if( !cStr || strlen(cStr)!=2*length )
        return nil;
    uint8_t digest[length];
    for( size_t i=0; i<length; i++ ) {
        if( sscanf(cStr, "%2hhx", &digest[i]) != 1 )
            return nil;
        cStr += 2;
    }
    return [[self alloc] initWithRawDigest: &digest length: length];
}

+ (id) digestOfData: (NSData*)data {
    return [self digestOfBytes: data.bytes length: data.length];
}

+ (id) digestOfBytes: (const void*)bytes length: (size_t)length {
    const size_t digestLength = [self length];
    uint8_t digest[digestLength];
    [self computeDigest: digest ofBytes: bytes length: length];
    return [[self alloc] initWithRawDigest: &digest length: digestLength];
}

- (uint32_t) algorithm {
    return [[self class] algorithm];
}

- (size_t) length {
    return [[self class] length];
}

- (const void*) bytes {
    return _rawDigest;
}


- (BOOL) isEqual: (id)digest
{
    return [digest class] == [self class]
        && memcmp(self.bytes, [digest bytes], self.length)==0;
}

- (NSUInteger) hash
{
    return *(NSUInteger*)self.bytes;
    //? This makes the hashcode endian-dependent. Does that matter?
}

- (NSComparisonResult) compare: (MYDigest*)other
{
    size_t size=self.length, otherSize=other.length;
    NSComparisonResult cmp = memcmp(self.bytes, other.bytes, MIN(size,otherSize));
    return cmp ? cmp : ((int)size - (int)otherSize);
}


- (NSData*) asData
{
    return [NSData dataWithBytes: self.bytes length: self.length];
}

- (NSString*) description
{
    return [NSString stringWithFormat: @"%@[%@]", [self class], [self abbreviatedHexString]];
}

- (NSString*) hexString
{
    const uint8_t *bytes = self.bytes;
    size_t length = self.length;
    char out[2*length+1];
    char *dst = &out[0];
    for( size_t i=0; i<length; i+=1 )
        dst += sprintf(dst,"%02X", bytes[i]);
    return [[NSString alloc] initWithBytes: out length: 2*length encoding: NSASCIIStringEncoding];
}

- (NSString*) abbreviatedHexString
{
    const uint8_t *bytes = self.bytes;
    return [NSString stringWithFormat: @"%02hhX%02hhX%02hhX%02hhX...",
            bytes[0],bytes[1],bytes[2],bytes[3]];
}


@end



@implementation MYSHA1Digest

+ (void) computeDigest: (void*)dstDigest ofBytes: (const void*)bytes length: (size_t)length {
    NSParameterAssert(bytes != NULL || length == 0);
    CC_SHA1(bytes,(CC_LONG)length, dstDigest);
}

#if TARGET_OS_IPHONE
+ (uint32_t) algorithm          {return kCCHmacAlgSHA1;}
#else
+ (uint32_t) algorithm          {return CSSM_ALGID_SHA1;}
#endif
+ (size_t) length               {return sizeof(RawSHA1Digest);}

- (MYSHA1Digest*) initWithRawSHA1Digest: (const RawSHA1Digest*)rawDigest {
    return [super initWithRawDigest: rawDigest length: sizeof(*rawDigest)];
}

+ (MYSHA1Digest*) digestFromRawSHA1Digest: (const RawSHA1Digest*)rawDigest {
    return [[self alloc] initWithRawSHA1Digest: rawDigest];
}

- (const RawSHA1Digest*) rawSHA1Digest {
    return self.bytes;
}


@end



@implementation MYSHA256Digest

+ (void) computeDigest: (void*)dstDigest ofBytes: (const void*)bytes length: (size_t)length {
    NSParameterAssert(bytes!=NULL);
    NSParameterAssert(length>0);
    CC_SHA256(bytes,(CC_LONG)length, dstDigest);
}

#if TARGET_OS_IPHONE
+ (uint32_t) algorithm          {return kCCHmacAlgSHA256;}
#else
+ (uint32_t) algorithm          {return CSSM_ALGID_SHA256;}
#endif
+ (size_t) length               {return sizeof(RawSHA256Digest);}

- (MYSHA256Digest*) initWithRawSHA256Digest: (const RawSHA256Digest*)rawDigest {
    return [super initWithRawDigest: rawDigest length: sizeof(*rawDigest)];
}

+ (MYSHA256Digest*) digestFromRawSHA256Digest: (const RawSHA256Digest*)rawDigest {
    return [[self alloc] initWithRawSHA256Digest: rawDigest];
}

- (const RawSHA256Digest*) rawSHA256Digest {
    return self.bytes;
}


@end



@implementation NSData (MYDigest)

- (MYSHA1Digest*) my_SHA1Digest
{
    return (MYSHA1Digest*) [MYSHA1Digest digestOfData: self];
}

- (MYSHA256Digest*) my_SHA256Digest
{
    return (MYSHA256Digest*) [MYSHA256Digest digestOfData: self];
}

@end



#import "Test.h"


static void testDigestOf( NSData *src, NSString *expectedSHA1Hex, NSString *expectedSHA256Hex )
{
    CAssert(src, @"Couldn't load test file");
    MYSHA1Digest *d1 = [src my_SHA1Digest];
    NSString *hex = d1.hexString;
    Log(@"Digesting %lu bytes to %@",(unsigned long)src.length,hex);
    if( expectedSHA1Hex )
        CAssertEqual(hex,expectedSHA1Hex);
    MYSHA1Digest *d2 = (MYSHA1Digest*) [MYSHA1Digest digestFromHexString: hex];
    CAssertEqual(d1,d2);
    CAssertEqual(d2.hexString,hex);

    MYSHA256Digest *d256 = [src my_SHA256Digest];
    hex = d256.hexString;
    Log(@"Digesting %lu bytes to %@",(unsigned long)src.length,hex);
    if( expectedSHA256Hex )
        CAssertEqual(hex,expectedSHA256Hex);
    MYSHA256Digest *d256_2 = (MYSHA256Digest*) [MYSHA256Digest digestFromHexString: hex];
    CAssertEqual(d256,d256_2);
    CAssertEqual(d256_2.hexString,hex);
}


TestCase(MYDigest) {
    testDigestOf([@"Pack my box with five dozen liquor jugs, you ugly potatoe pie!" 
                          dataUsingEncoding: NSUTF8StringEncoding],
                 @"4F254781ED6C0103BE056DD8418EFBAC0C2EBE3C",
                 @"08AA4BCDDF7654D7AB5CDD25395A4DD8F3BEB5C79FE567D10C1A21B9134F48FD");
    testDigestOf([NSData dataWithContentsOfFile: @"/Library/Desktop Pictures/Aqua Blue.jpg"],
                 @"FAE309828A6CA67212D7A956C6F673B164BD99CA",
                 @"E850A3E8AAD5477054C7F38D64755C1DFEF14D2FC1F9620A2E6BDF44B8783B4A");
}



/*
 Copyright (c) 2009, Jens Alfke <jens@mooseyard.com>. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are permitted
 provided that the following conditions are met:
 
 * Redistributions of source code must retain the above copyright notice, this list of conditions
 and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of conditions
 and the following disclaimer in the documentation and/or other materials provided with the
 distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND 
 FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRI-
 BUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR 
  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF 
 THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
