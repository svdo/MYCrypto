//
//  MYKeychainItem.m
//  MYCrypto
//
//  Created by Jens Alfke on 3/26/09.
//  Copyright 2009 Jens Alfke. All rights reserved.
//

#import "MYKeychainItem.h"
#import "MYCrypto_Private.h"
#import "MYBERParser.h"
#import "MYErrorUtils.h"
#import "MYLogging.h"

#if MYCRYPTO_USE_IPHONE_API
// <MacErrors.h> is missing in iPhone SDK
enum {
    paramErr = -50,
    userCanceledErr = -128
};
#endif


NSString* const MYCSSMErrorDomain = @"CSSMErrorDomain";


@implementation MYKeychainItem


- (id) initWithKeychainItemRef: (MYKeychainItemRef)itemRef
{
    Assert(itemRef!=NULL);
    self = [super init];
    if (self != nil) {
        _itemRef = itemRef;
        CFRetain(_itemRef);
        LogTo(INIT,@"%@, _itemRef=%@", [self class], itemRef);
#if MYCRYPTO_USE_IPHONE_API
        _isPersistent = YES;
#endif
    }
    return self;
}


@synthesize keychainItemRef=_itemRef;

#if MYCRYPTO_USE_IPHONE_API
@synthesize isPersistent = _isPersistent;
#endif

- (void) dealloc
{
    if (_itemRef) CFRelease(_itemRef);
}


- (id) copyWithZone: (NSZone*)zone {
    // As keys are immutable, it's not necessary to make copies of them. This makes it more efficient
    // to use instances as NSDictionary keys or store them in NSSets.
    return self;
}

- (BOOL) isEqual: (id)obj {
    return (obj == self) ||
           ([obj isKindOfClass: [MYKeychainItem class]] && CFEqual(_itemRef, [obj keychainItemRef]));
}

- (NSUInteger) hash {
    return CFHash(_itemRef);
}

- (NSString*) description {
    return $sprintf(@"%@[%p]", [self class], _itemRef);     //FIX: Can we do anything better?
}


- (NSArray*) _itemList {
    return @[(__bridge id)_itemRef];
}


- (MYKeychain*) keychain {
#if MYCRYPTO_USE_IPHONE_API
    return _isPersistent ? [MYKeychain defaultKeychain] : nil;
#else
    MYKeychain *keychain = nil;
    SecKeychainRef keychainRef = NULL;
    if (check(SecKeychainItemCopyKeychain((SecKeychainItemRef)_itemRef, &keychainRef), @"SecKeychainItemCopyKeychain")) {
        if (keychainRef) {
            keychain = [[MYKeychain alloc] initWithKeychainRef: keychainRef];
            CFRelease(keychainRef);
        }
    }
    return keychain;
#endif
}

- (BOOL) removeFromKeychain {
    OSStatus err;
#if MYCRYPTO_USE_IPHONE_API
    err = SecItemDelete((__bridge CFDictionaryRef) $dict( {(__bridge id)kSecValueRef, (__bridge id)_itemRef} ));
    if (!err)
        _isPersistent = NO;
#else
    err = SecKeychainItemDelete((SecKeychainItemRef)_itemRef);
    if (err==errSecInvalidItemRef)
        return YES;     // result for an item that's not in a keychain
#endif
    return err==errSecItemNotFound || check(err, @"SecKeychainItemDelete");
}


/* (Not useful yet, as only password items have dates.)
- (NSDate*) dateValueOfAttribute: (MYKeychainAttrType)attr {
    NSString *dateStr = [self stringValueOfAttribute: attr];
    if (dateStr.length == 0)
        return nil;
    NSDate *date = [MYBERGeneralizedTimeFormatter() dateFromString: dateStr];
    if (!date)
        Warn(@"MYKeychainItem: unable to parse date '%@'", dateStr);
    return date;
}

- (void) setDateValue: (NSDate*)date ofAttribute: (MYKeychainAttrType)attr {
    NSString *timeStr = nil;
    if (date)
        timeStr = [MYBERGeneralizedTimeFormatter() stringFromDate: date];
    [self setValue: timeStr ofAttribute: attr];
}


- (NSDate*) creationDate {
    return [self dateValueOfAttribute: kSecCreationDateItemAttr];
}

- (void) setCreationDate: (NSDate*)date {
    [self setDateValue: date ofAttribute: kSecCreationDateItemAttr];
}

- (NSDate*) modificationDate {
    return [self dateValueOfAttribute: kSecModDateItemAttr];
}

- (void) setModificationDate: (NSDate*)date {
    [self setDateValue: date ofAttribute: kSecModDateItemAttr];
}
*/


#pragma mark -
#pragma mark DATA / METADATA ACCESSORS:


- (NSData*) _getContents: (OSStatus*)outError {
    NSData *contents = nil;
#if MYCRYPTO_USE_IPHONE_API
#else
	UInt32 length = 0;
    void *bytes = NULL;
    *outError = SecKeychainItemCopyAttributesAndData(_itemRef, NULL, NULL, NULL, &length, &bytes);
    if (!*outError && bytes) {
        contents = [NSData dataWithBytes: bytes length: length];
        SecKeychainItemFreeAttributesAndData(NULL, bytes);
    }
#endif
    return contents;
}

+ (NSData*) _getAttribute: (MYKeychainAttrType)attr ofItem: (MYKeychainItemRef)item {
    NSData *value = nil;
#if MYCRYPTO_USE_IPHONE_API
    NSDictionary *info = $dict( {(__bridge id)kSecValueRef, (__bridge id)item},
                                {(__bridge id)kSecReturnAttributes, $true} );
    CFDictionaryRef attrs;
    if (!check(SecItemCopyMatching((__bridge CFDictionaryRef)info, (CFTypeRef*)&attrs), @"SecItemCopyMatching"))
        return nil;
    CFTypeRef rawValue = CFDictionaryGetValue(attrs,attr);
    value = rawValue ? CFBridgingRelease(CFRetain(rawValue)) :nil;
    CFRelease(attrs);
    
#else
	UInt32 format = kSecFormatUnknown;
	SecKeychainAttributeInfo info = {.count=1, .tag=(UInt32*)&attr, .format=&format};
    SecKeychainAttributeList *list = NULL;
	
    OSStatus err = SecKeychainItemCopyAttributesAndData((SecKeychainItemRef)item, &info,
                                                        NULL, &list, NULL, NULL);
    if (err != errKCNotAvailable && check(err, @"SecKeychainItemCopyAttributesAndData")) {
        if (list) {
            if (list->count == 1)
                value = [NSData dataWithBytes: list->attr->data
                                       length: list->attr->length];
            else if (list->count > 1)
                Warn(@"Multiple values for keychain item attribute");
            SecKeychainItemFreeAttributesAndData(list, NULL);
        }
    }
#endif
    return value;
}

+ (NSString*) _getStringAttribute: (MYKeychainAttrType)attr ofItem: (MYKeychainItemRef)item {
    NSData *value = [self _getAttribute: attr ofItem: item];
    if (!value) return nil;
    const char *bytes = value.bytes;
    size_t length = value.length;
    if (length>0 && bytes[length-1] == 0)
        length--;           // Some values are null-terminated!?
    NSString *str = [[NSString alloc] initWithBytes: bytes length: length
                                           encoding: NSUTF8StringEncoding];
    if (!str)
        Warn(@"MYKeychainItem: Couldn't decode attr value as string");
    return str;
}

- (NSString*) stringValueOfAttribute: (MYKeychainAttrType)attr {
#if MYCRYPTO_USE_IPHONE_API
    if (!self.isPersistent)
        return nil;
#endif
    return [[self class] _getStringAttribute: attr ofItem: _itemRef];
}


+ (BOOL) _setAttribute: (MYKeychainAttrType)attr ofItem: (MYKeychainItemRef)item
           stringValue: (NSString*)stringValue
{
#if MYCRYPTO_USE_IPHONE_API
    id value = stringValue ?(id)stringValue :(id)[NSNull null];
    NSDictionary *query = $dict({(__bridge id)kSecValueRef, (__bridge id)item});
    NSDictionary *attrs = $dict({(__bridge id)attr, value});
    return check(SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attrs), @"SecItemUpdate");
    
#else
    NSData *data = [stringValue dataUsingEncoding: NSUTF8StringEncoding];
    SecKeychainAttribute attribute = {.tag=attr, .length=(UInt32)data.length, .data=(void*)data.bytes};
	SecKeychainAttributeList list = {.count=1, .attr=&attribute};
    return check(SecKeychainItemModifyAttributesAndData((SecKeychainItemRef)item, &list, 0, NULL),
                 @"SecKeychainItemModifyAttributesAndData");
#endif
}

- (BOOL) setValue: (NSString*)valueStr ofAttribute: (MYKeychainAttrType)attr {
    return [[self class] _setAttribute: attr ofItem: _itemRef stringValue: valueStr];
}


@end




BOOL check(OSStatus err, NSString *what) {
    if (err) {
#if !MYCRYPTO_USE_IPHONE_API
        if (err < -2000000000)
            return checkcssm(err,what);
#endif
        if (err == userCanceledErr) // don't warn about userCanceledErr
            return NO;
        Warn(@"MYCrypto error, %@: %@", what, MYErrorName(NSOSStatusErrorDomain,err));
        if (err==paramErr)
            [NSException raise: NSGenericException format: @"%@ failed with paramErr (-50)",what];
        return NO;
    } else
        return YES;
}

#if !MYCRYPTO_USE_IPHONE_API
BOOL checkcssm(CSSM_RETURN err, NSString *what) {
    if (err != CSSM_OK) {
        Warn(@"MYCrypto error, %@: %@", what, MYErrorName(MYCSSMErrorDomain,err));
        return NO;
    } else
        return YES;
}
#endif



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
