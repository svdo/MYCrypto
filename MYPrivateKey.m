//
//  MYPrivateKey.m
//  MYCrypto
//
//  Created by Jens Alfke on 4/7/09.
//  Copyright 2009 Jens Alfke. All rights reserved.
//

#import "MYPrivateKey.h"
#import "MYCrypto_Private.h"
#import "MYDigest.h"
#import "MYLogging.h"
#import <CommonCrypto/CommonDigest.h>

@implementation MYPrivateKey


- (id) initWithKeyRef: (SecKeyRef)privateKey
{
    self = [super initWithKeyRef: privateKey];
    if (self) {
        // No public key given, so look it up:
        MYSHA1Digest *digest = self._keyDigest;
        if (digest)
            _publicKey = [self.keychain publicKeyWithDigest: digest];
        if (!_publicKey) {
            // The matching public key won't turn up if it's embedded in a certificate;
            // I'd have to search for certs if I wanted to look that up. Skip it for now.
            Log(@"MYPrivateKey(%p): Couldn't find matching public key for private key! digest=%@",
                self, digest);
            return nil;
        }
    }
    return self;
}


- (id) _initWithKeyRef: (SecKeyRef)privateKey
             publicKey: (MYPublicKey*)publicKey 
{
    Assert(publicKey);
    self = [super initWithKeyRef: privateKey];
    if (self) {
        _publicKey = publicKey;
    }
    return self;
}

- (id) initWithKeyRef: (SecKeyRef)privateKey
         publicKeyRef: (SecKeyRef)publicKeyRef
{
    MYPublicKey *publicKey = [[MYPublicKey alloc] initWithKeyRef: publicKeyRef];
    self = [self _initWithKeyRef: privateKey publicKey: publicKey];
    return self;
}

- (id) _initWithKeyRef: (SecKeyRef)privateKey 
         publicKeyData: (NSData*)pubKeyData
           forKeychain: (SecKeychainRef)keychain 
{
    if (!privateKey) {
        return nil;
    }
    MYPublicKey *pubKey = [[MYPublicKey alloc] _initWithKeyData: pubKeyData forKeychain: keychain];
    if (!pubKey) {
        return nil;
    }
    self = [super initWithKeyRef: privateKey];
    if (self) {
        _publicKey = pubKey;
    } else {
        [pubKey removeFromKeychain];
    }
    return self;
}


#if !TARGET_OS_IPHONE

// The public API for this is in MYKeychain.
- (id) _initWithKeyData: (NSData*)privKeyData 
          publicKeyData: (NSData*)pubKeyData
            forKeychain: (SecKeychainRef)keychain 
             alertTitle: (NSString*)title
            alertPrompt: (NSString*)prompt
{
    // Try to import the private key first, since the user might cancel the passphrase alert.
    SecKeyImportExportParameters params = {
        .flags = kSecKeySecurePassphrase,
        .alertTitle = (__bridge CFStringRef) title,
        .alertPrompt = (__bridge CFStringRef) prompt
    };
    SecKeyRef privateKey = importKey(privKeyData,kSecItemTypePrivateKey,keychain,&params);
    return [self _initWithKeyRef: privateKey publicKeyData: pubKeyData forKeychain: keychain];
}

// This method is for testing, so unit-tests don't require user intervention.
// It's deliberately not made public, to discourage clients from trying to manage the passphrases
// themselves (this is less secure than letting the Security agent do it.)
- (id) _initWithKeyData: (NSData*)privKeyData 
          publicKeyData: (NSData*)pubKeyData
            forKeychain: (SecKeychainRef)keychain 
             passphrase: (NSString*)passphrase
{
    SecKeyImportExportParameters params = {
        .passphrase = (__bridge CFStringRef) passphrase,
    };
    SecKeyRef privateKey = importKey(privKeyData,kSecItemTypePrivateKey,keychain,&params);
    return [self _initWithKeyRef: privateKey publicKeyData: pubKeyData forKeychain: keychain];
}


#endif




+ (MYPrivateKey*) _generateRSAKeyPairOfSize: (unsigned)keySize
                                 inKeychain: (MYKeychain*)keychain 
{
    Assert( keySize == 512 || keySize == 1024 || keySize == 2048, @"Unsupported key size %u", keySize );
    SecKeyRef pubKey=NULL, privKey=NULL;
    OSStatus err;
    
#if MYCRYPTO_USE_IPHONE_API
    NSDictionary *pubKeyAttrs = $dict({(__bridge id)kSecAttrIsPermanent, $true});
    NSDictionary *privKeyAttrs = $dict({(__bridge id)kSecAttrIsPermanent, $true});
    NSDictionary *keyAttrs = $dict( {(__bridge id)kSecAttrKeyType, (__bridge id)kSecAttrKeyTypeRSA},
                                    {(__bridge id)kSecAttrKeySizeInBits, @(keySize)},
                                    {(__bridge id)kSecPublicKeyAttrs, pubKeyAttrs},
                                    {(__bridge id)kSecPrivateKeyAttrs, privKeyAttrs} );
    err = SecKeyGeneratePair((__bridge CFDictionaryRef)keyAttrs,&pubKey,&privKey);
#else
    err = SecKeyCreatePair(keychain.keychainRefOrDefault,
                           CSSM_ALGID_RSA, 
                           keySize,
                           0LL,
                           CSSM_KEYUSE_ENCRYPT | CSSM_KEYUSE_VERIFY | CSSM_KEYUSE_WRAP,        // public key
                           CSSM_KEYATTR_EXTRACTABLE | CSSM_KEYATTR_PERMANENT,
                           CSSM_KEYUSE_ANY,                                 // private key
                           CSSM_KEYATTR_EXTRACTABLE | CSSM_KEYATTR_PERMANENT | CSSM_KEYATTR_SENSITIVE,
                           NULL,                                            // SecAccessRef
                           &pubKey, &privKey);
#endif
    if (!check(err, @"SecKeyCreatePair")) {
        return nil;
    } else
        return [[self alloc] initWithKeyRef: privKey publicKeyRef: pubKey];
}


#pragma mark -
#pragma mark ACCESSORS:


- (NSString*) description {
    return $sprintf(@"%@[%@ %@ /%p]", [self class], 
                    self.publicKeyDigest.abbreviatedHexString,
                    (self.name ?:@""),
                    self.keychainItemRef);
}

@synthesize publicKey=_publicKey;

- (MYSHA1Digest*) _keyDigest {
    if (_publicKey)
        return _publicKey.publicKeyDigest;
    else {
        NSData *digestData;
#if MYCRYPTO_USE_IPHONE_API
        digestData = [self _attribute: kSecAttrApplicationLabel];
#else
        digestData = [[self class] _getAttribute: kSecKeyLabel 
                                          ofItem: (SecKeychainItemRef)self.keyRef]; 
#endif
        return [MYSHA1Digest digestFromDigestData: digestData];
    }
}

- (MYSHA1Digest*) publicKeyDigest {
    return self._keyDigest;
}

- (SecExternalItemType) keyClass {
#if MYCRYPTO_USE_IPHONE_API
    return kSecAttrKeyClassPublic;
#else
    return kSecItemTypePrivateKey;
#endif
}

#if MYCRYPTO_USE_IPHONE_API
- (SecExternalItemType) keyType {
    return kSecAttrKeyTypeRSA;
}
#endif

- (NSData *) keyData {
    [NSException raise: NSGenericException format: @"Can't access keyData of a PrivateKey"];
    return nil;
}

- (BOOL) setValue: (NSString*)valueStr ofAttribute: (MYKeychainAttrType)attr {
    return [super setValue: valueStr ofAttribute: attr]
        && [_publicKey setValue: valueStr ofAttribute: attr];
}


#pragma mark -
#pragma mark OPERATIONS:


- (BOOL) removeFromKeychain {
    return [super removeFromKeychain]
        && [_publicKey removeFromKeychain];
}


- (NSData*) rawDecryptData: (NSData*)data {
    return [self _crypt: data operation: NO];
}


- (NSData*) signData: (NSData*)data {
    Assert(data);
#if MYCRYPTO_USE_IPHONE_API
    uint8_t digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes,data.length, digest);

    size_t sigLen = 1024;
    uint8_t sigBuf[sigLen];
    OSStatus err = SecKeyRawSign(self.keyRef, kSecPaddingPKCS1SHA1,
                                 digest,sizeof(digest), //data.bytes, data.length,
                                 sigBuf, &sigLen);
    if(err) {
        Warn(@"SecKeyRawSign failed: %ld", (long)err);
        return nil;
    } else
        return [NSData dataWithBytes: sigBuf length: sigLen];
#else
    NSData *signature = nil;
    CSSM_CC_HANDLE ccHandle = [self _createSignatureContext: CSSM_ALGID_SHA1WithRSA];
    if (!ccHandle) return nil;
    CSSM_DATA original = {data.length, (void*)data.bytes};
    CSSM_DATA result = {0,NULL};
    if (checkcssm(CSSM_SignData(ccHandle, &original, 1, CSSM_ALGID_NONE, &result), @"CSSM_SignData"))
        signature = [NSData dataWithBytesNoCopy: result.Data length: result.Length
                                   freeWhenDone: YES];
    CSSM_DeleteContext(ccHandle);
    return signature;
#endif
}


#if !TARGET_OS_IPHONE

- (NSData*) exportKeyInFormat: (SecExternalFormat)format 
                      withPEM: (BOOL)withPEM
                   alertTitle: (NSString*)title
                  alertPrompt: (NSString*)prompt
{
    SecKeyImportExportParameters params = {
        .version = SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION,
        .flags = kSecKeySecurePassphrase,
        .alertTitle = (__bridge CFStringRef)title,
        .alertPrompt = (__bridge CFStringRef)prompt
    };
    CFDataRef data = NULL;
    if (check(SecKeychainItemExport(self.keyRef,
                                    format, (withPEM ?kSecItemPemArmour :0), 
                                    &params, &data),
              @"SecKeychainItemExport"))
        return (NSData*)CFBridgingRelease(data);
    else
        return nil;
}

- (NSData*) exportKey {
    return [self exportKeyInFormat: kSecFormatWrappedOpenSSL withPEM: YES
                        alertTitle: @"Export Private Key"
                       alertPrompt: @"Enter a passphrase to protect the private-key file.\n"
            "You will need to re-enter the passphrase later when importing the key from this file, "
            "so keep it in a safe place."];
    //FIX: Should make these messages localizable.
}


- (NSData*) _exportKeyInFormat: (SecExternalFormat)format
                       withPEM: (BOOL)withPEM
                    passphrase: (NSString*)passphrase
{
    SecKeyImportExportParameters params = {
        .version = SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION,
        .passphrase = (__bridge CFStringRef)passphrase
    };
    CFDataRef data = NULL;
    if (check(SecKeychainItemExport(self.keyRef,
                                    format, (withPEM ?kSecItemPemArmour :0), 
                                    &params, &data),
              @"SecKeychainItemExport"))
        return (NSData*)CFBridgingRelease(data);
    else
        return nil;
}


- (MYSymmetricKey*) unwrapSessionKey: (NSData*)wrappedData
                       withAlgorithm: (CCAlgorithm)algorithm
                          sizeInBits: (unsigned)sizeInBits
{
    // First create a wrapped-key structure from the data:
    CSSM_WRAP_KEY wrappedKey = {
        .KeyHeader = {
            .BlobType = CSSM_KEYBLOB_WRAPPED,
            .Format = CSSM_KEYBLOB_RAW_FORMAT_PKCS3,
            .AlgorithmId = CSSMFromCCAlgorithm(algorithm),
            .KeyClass = CSSM_KEYCLASS_SESSION_KEY,
            .LogicalKeySizeInBits = sizeInBits,
            .KeyAttr = CSSM_KEYATTR_EXTRACTABLE,
            .KeyUsage = CSSM_KEYUSE_ANY,
            .WrapAlgorithmId = self.cssmAlgorithm,
        },
        .KeyData = {
            .Data = (void*)wrappedData.bytes,
            .Length = wrappedData.length
        }
    };
        
    const CSSM_ACCESS_CREDENTIALS* credentials;
    credentials = [self cssmCredentialsForOperation: CSSM_ACL_AUTHORIZATION_IMPORT_WRAPPED
                                               type: kSecCredentialTypeDefault error: nil];
    CSSM_CSP_HANDLE cspHandle = self.cssmCSPHandle;
    CSSM_CC_HANDLE ctx;
    if (!checkcssm(CSSM_CSP_CreateAsymmetricContext(cspHandle,
                                                    self.cssmAlgorithm,
                                                    credentials, 
                                                    self.cssmKey,
                                                    CSSM_PADDING_PKCS1,
                                                    &ctx), 
                   @"CSSM_CSP_CreateAsymmetricContext"))
        return nil;
    
    // Now unwrap the key:
    MYSymmetricKey *result = nil;
    CSSM_KEY *unwrappedKey = calloc(1,sizeof(CSSM_KEY));
    CSSM_DATA label = {.Data=(void*)"Imported key", .Length=strlen("Imported key")};
    CSSM_DATA descriptiveData = {};
    if (checkcssm(CSSM_UnwrapKey(ctx, 
                                 self.cssmKey,
                                 &wrappedKey,
                                 wrappedKey.KeyHeader.KeyUsage,
                                 wrappedKey.KeyHeader.KeyAttr,
                                 &label,
                                 NULL,
                                 unwrappedKey,
                                 &descriptiveData),
                  @"CSSM_UnwrapKey")) {
        result = [[MYSymmetricKey alloc] _initWithCSSMKey: unwrappedKey];
    }
    // Finally, delete the context
    if (!result)
        free(unwrappedKey);
    CSSM_DeleteContext(ctx);
    return result;
}


#endif //!TARGET_OS_IPHONE

@end



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
