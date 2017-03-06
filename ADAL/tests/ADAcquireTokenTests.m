// Copyright (c) Microsoft Corporation.
// All rights reserved.
//
// This code is licensed under the MIT License.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files(the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and / or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions :
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import <XCTest/XCTest.h>
#import "ADAL_Internal.h"
#import "ADAuthenticationContext+Internal.h"
#import "XCTestCase+TestHelperMethods.h"
#import <libkern/OSAtomic.h>
#import "ADWebRequest.h"
#import "ADTestURLConnection.h"
#import "ADOAuth2Constants.h"
#import "ADAuthenticationSettings.h"
#import "ADKeychainTokenCache+Internal.h"
#import "ADTestURLConnection.h"
#import "ADTokenCache+Internal.h"
#import "ADTokenCacheItem+Internal.h"
#import "ADTokenCacheKey.h"
#import "ADTokenCacheDataSource.h"
#import "ADTelemetryTestDispatcher.h"

const int sAsyncContextTimeout = 10;

@interface ADAcquireTokenTests : XCTestCase
{
@private
    dispatch_semaphore_t _dsem;
}
@end


@implementation ADAcquireTokenTests

- (void)setUp
{
    [super setUp];
    [self adTestBegin:ADAL_LOG_LEVEL_INFO];
    _dsem = dispatch_semaphore_create(0);
}

- (void)tearDown
{
#if !__has_feature(objc_arc)
    dispatch_release(_dsem);
#endif
    _dsem = nil;
    
    XCTAssertTrue([ADTestURLConnection noResponsesLeft]);
    [ADTestURLConnection clearResponses];
    [self adTestEnd];
    [super tearDown];
}

- (ADAuthenticationContext *)getTestAuthenticationContext
{
    ADAuthenticationContext* context =
        [[ADAuthenticationContext alloc] initWithAuthority:TEST_AUTHORITY
                                         validateAuthority:NO
                                                     error:nil];
    
    NSAssert(context, @"If this is failing for whatever reason you should probably fix it before trying to run tests.");
    ADTokenCache *tokenCache = [ADTokenCache new];
    SAFE_ARC_AUTORELEASE(tokenCache);
    [context setTokenCacheStore:tokenCache];
    [context setCorrelationId:TEST_CORRELATION_ID];
    
    SAFE_ARC_AUTORELEASE(context);
    
    return context;
}

- (void)testBadCompletionBlock
{
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    ADAssertThrowsArgument([context acquireTokenWithResource:TEST_RESOURCE clientId:TEST_CLIENT_ID redirectUri:TEST_REDIRECT_URL completionBlock:nil]);
}

- (void)testBadResource
{
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    [context acquireTokenWithResource:nil
                             clientId:TEST_CLIENT_ID
                          redirectUri:TEST_REDIRECT_URL
                      completionBlock:^(ADAuthenticationResult *result)
    {
        XCTAssertNotNil(result);
        XCTAssertEqual(result.status, AD_FAILED);
        XCTAssertNotNil(result.error);
        XCTAssertEqual(result.error.code, AD_ERROR_DEVELOPER_INVALID_ARGUMENT);
        ADTAssertContains(result.error.errorDetails, @"resource");
        
        TEST_SIGNAL;
    }];
    
    TEST_WAIT;
    
    [context acquireTokenWithResource:@"   "
                             clientId:TEST_CLIENT_ID
                          redirectUri:TEST_REDIRECT_URL
                      completionBlock:^(ADAuthenticationResult *result)
     {
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_FAILED);
         XCTAssertNotNil(result.error);
         XCTAssertEqual(result.error.code, AD_ERROR_DEVELOPER_INVALID_ARGUMENT);
         ADTAssertContains(result.error.errorDetails, @"resource");
         
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
}

- (void)testBadClientId
{
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    [context acquireTokenWithResource:TEST_RESOURCE
                             clientId:nil
                          redirectUri:TEST_REDIRECT_URL
                      completionBlock:^(ADAuthenticationResult *result)
     {
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_FAILED);
         XCTAssertNotNil(result.error);
         XCTAssertEqual(result.error.code, AD_ERROR_DEVELOPER_INVALID_ARGUMENT);
         ADTAssertContains(result.error.errorDetails, @"clientId");
         
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
    
    [context acquireTokenWithResource:TEST_RESOURCE
                             clientId:@"    "
                          redirectUri:TEST_REDIRECT_URL
                      completionBlock:^(ADAuthenticationResult *result)
     {
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_FAILED);
         XCTAssertNotNil(result.error);
         XCTAssertEqual(result.error.code, AD_ERROR_DEVELOPER_INVALID_ARGUMENT);
         ADTAssertContains(result.error.errorDetails, @"clientId");
         
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
}

- (void)testInvalidBrokerRedirectURI
{
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    [context setCredentialsType:AD_CREDENTIALS_AUTO];
    [context acquireTokenWithResource:TEST_RESOURCE
                             clientId:TEST_CLIENT_ID
                          redirectUri:[NSURL URLWithString:@"invalid://redirect_uri"]
                      completionBlock:^(ADAuthenticationResult *result)
     {
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_FAILED);
         XCTAssertNotNil(result.error);
         XCTAssertEqual(result.error.code, AD_ERROR_TOKENBROKER_INVALID_REDIRECT_URI);
         
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
}

- (void)testBadExtraQueryParameters
{
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    [context acquireTokenWithResource:TEST_RESOURCE
                             clientId:TEST_CLIENT_ID
                          redirectUri:TEST_REDIRECT_URL
                               userId:TEST_USER_ID
                 extraQueryParameters:@"login_hint=test1@馬克英家.com"
                      completionBlock:^(ADAuthenticationResult *result)
     {
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_FAILED);
         XCTAssertNotNil(result.error);
         XCTAssertEqual(result.error.code, AD_ERROR_DEVELOPER_INVALID_ARGUMENT);
         ADTAssertContains(result.error.errorDetails, @"extraQueryParameters");
         
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
}

- (void)testAssertionBadAssertion
{
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    [context acquireTokenForAssertion:nil
                        assertionType:AD_SAML1_1
                             resource:TEST_RESOURCE
                             clientId:TEST_CLIENT_ID
                               userId:TEST_USER_ID
                      completionBlock:^(ADAuthenticationResult *result)
     {
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_FAILED);
         XCTAssertNotNil(result.error);
         XCTAssertEqual(result.error.code, AD_ERROR_DEVELOPER_INVALID_ARGUMENT);
         ADTAssertContains(result.error.errorDetails, @"assertion");
         
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
}

- (void)testAssertionCached
{
    ADAuthenticationError* error = nil;
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    // Add a token item to return in the cache
    ADTokenCacheItem* item = [self adCreateCacheItem];
    [context.tokenCacheStore.dataSource addOrUpdateItem:item correlationId:nil error:&error];
    XCTAssertNil(error);
    
    [context acquireTokenForAssertion:@"some assertion"
                        assertionType:AD_SAML1_1
                             resource:TEST_RESOURCE
                             clientId:TEST_CLIENT_ID
                               userId:TEST_USER_ID
                      completionBlock:^(ADAuthenticationResult *result)
    {
        XCTAssertNotNil(result);
        XCTAssertEqual(result.status, AD_SUCCEEDED);
        XCTAssertNotNil(result.tokenCacheItem);
        XCTAssertEqualObjects(result.tokenCacheItem, item);
        
        TEST_SIGNAL;
    }];
    
    TEST_WAIT;
}

- (void)testAssertionNetwork
{
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    NSUUID* correlationId = TEST_CORRELATION_ID;
    
    NSString* broadRefreshToken = @"broad refresh token testAcquireTokenWithNoPrompt";
    NSString* anotherAccessToken = @"another access token testAcquireTokenWithNoPrompt";
    NSString* assertion = @"some assertion";
    NSString* base64Assertion = [[assertion dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    
    ADTestURLResponse* response = [ADTestURLResponse requestURLString:@"https://login.windows.net/contoso.com/oauth2/token?x-client-Ver=" ADAL_VERSION_STRING
                                                       requestHeaders:@{ OAUTH2_CORRELATION_ID_REQUEST_VALUE : [correlationId UUIDString] }
                                                    requestParamsBody:@{ OAUTH2_GRANT_TYPE : OAUTH2_SAML11_BEARER_VALUE,
                                                                         OAUTH2_SCOPE : OAUTH2_SCOPE_OPENID_VALUE,
                                                                         OAUTH2_RESOURCE : TEST_RESOURCE,
                                                                         OAUTH2_CLIENT_ID : TEST_CLIENT_ID,
                                                                         OAUTH2_ASSERTION : base64Assertion }
                                                    responseURLString:@"https://contoso.com"
                                                         responseCode:400
                                                     httpHeaderFields:@{ OAUTH2_CORRELATION_ID_REQUEST_VALUE : [correlationId UUIDString] }
                                                     dictionaryAsJSON:@{ OAUTH2_ACCESS_TOKEN : anotherAccessToken,
                                                                         OAUTH2_REFRESH_TOKEN : broadRefreshToken,
                                                                         OAUTH2_TOKEN_TYPE : TEST_ACCESS_TOKEN_TYPE,
                                                                         OAUTH2_RESOURCE : TEST_RESOURCE,
                                                                         OAUTH2_GRANT_TYPE : OAUTH2_SAML11_BEARER_VALUE,
                                                                         OAUTH2_SCOPE : OAUTH2_SCOPE_OPENID_VALUE
                                                                         }];
    [ADTestURLConnection addResponse:response];
    
    [context acquireTokenForAssertion:assertion
                        assertionType:AD_SAML1_1
                             resource:TEST_RESOURCE
                             clientId:TEST_CLIENT_ID
                               userId:TEST_USER_ID
                      completionBlock:^(ADAuthenticationResult *result)
     {
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_SUCCEEDED);
         XCTAssertNil(result.error);
         XCTAssertNotNil(result.tokenCacheItem);
         XCTAssertEqualObjects(result.tokenCacheItem.refreshToken, broadRefreshToken);
         XCTAssertEqualObjects(result.accessToken, anotherAccessToken);
         XCTAssertEqualObjects(result.correlationId, correlationId);
         
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
    
    XCTAssertTrue([ADTestURLConnection noResponsesLeft]);
}


- (void)testCachedWithNilUserId
{
    ADAuthenticationError* error = nil;
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    // Add a token item to return in the cache
    ADTokenCacheItem* item = [self adCreateCacheItem:@"eric@contoso.com"];
    [context.tokenCacheStore.dataSource addOrUpdateItem:item correlationId:nil error:&error];
    
    // Because there's only one user in the cache calling acquire token with nil userId should
    // return this one item.
    [context acquireTokenWithResource:TEST_RESOURCE
                             clientId:TEST_CLIENT_ID
                          redirectUri:TEST_REDIRECT_URL
                      completionBlock:^(ADAuthenticationResult *result)
    {
        XCTAssertNotNil(result);
        XCTAssertEqual(result.status, AD_SUCCEEDED);
        XCTAssertNil(result.error);
        XCTAssertNotNil(result.tokenCacheItem);
        XCTAssertEqualObjects(result.tokenCacheItem, item);
        
        TEST_SIGNAL;
    }];
    
    TEST_WAIT;
}

- (void)testFailsWithNilUserIdAndMultipleCachedUsers
{
    // prepare and register telemetry dispatcher
    ADTelemetryTestDispatcher* dispatcher = [ADTelemetryTestDispatcher new];
    NSMutableArray* receivedEvents = [NSMutableArray new];
    [dispatcher setTestCallback:^(NSArray* event)
     {
         [receivedEvents addObject:event];
     }];
    [[ADTelemetry sharedInstance] registerDispatcher:dispatcher aggregationRequired:YES];
    
    ADAuthenticationError* error = nil;
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    // Add a token item to return in the cache
    [context.tokenCacheStore.dataSource addOrUpdateItem:[self adCreateCacheItem:@"eric@contoso.com"] correlationId:nil error:&error];
    [context.tokenCacheStore.dataSource addOrUpdateItem:[self adCreateCacheItem:@"stan@contoso.com"] correlationId:nil error:&error];
    
    // Because there's only one user in the cache calling acquire token with nil userId should
    // return this one item.
    [context acquireTokenWithResource:TEST_RESOURCE
                             clientId:TEST_CLIENT_ID
                          redirectUri:TEST_REDIRECT_URL
                               userId:nil
                      completionBlock:^(ADAuthenticationResult *result)
     {
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_FAILED);
         XCTAssertNotNil(result.error);
         XCTAssertNil(result.tokenCacheItem);
         XCTAssertEqual(result.error.code, AD_ERROR_CACHE_MULTIPLE_USERS);
         
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
    
    // verify telemetry output
    // there should be 1 telemetry events recorded as aggregation flag is ON
    XCTAssertEqual([receivedEvents count], 1);
    
    // the following properties are expected in an aggregrated event
    NSArray* event = [receivedEvents firstObject];
    XCTAssertEqual([self adGetPropertyCount:event
                             propertyName:@"api_id"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                             propertyName:@"request_id"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                             propertyName:@"correlation_id"], 1);
#if TARGET_OS_IPHONE
    // application_version is only available in unit test framework with host app
    XCTAssertEqual([self adGetPropertyCount:event
                             propertyName:@"application_version"], 1);
#endif
    XCTAssertEqual([self adGetPropertyCount:event
                             propertyName:@"application_name"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                             propertyName:@"x-client-Ver"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                             propertyName:@"x-client-SKU"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                             propertyName:@"client_id"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                             propertyName:@"device_id"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                             propertyName:@"authority_type"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                             propertyName:@"extended_expires_on_setting"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                             propertyName:@"prompt_behavior"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                             propertyName:@"status"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                             propertyName:@"response_time"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                             propertyName:@"cache_event_count"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                             propertyName:@"error_code"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                             propertyName:@"error_domain"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                             propertyName:@"error_description"], 1);
    
    //unregister the dispatcher
    [[ADTelemetry sharedInstance] registerDispatcher:nil aggregationRequired:YES];
}

- (void)testCachedWithNoIdtoken
{
    ADAuthenticationError* error = nil;
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    // Add a token item to return in the cache
    ADTokenCacheItem* item = [self adCreateCacheItem:nil];
    [context.tokenCacheStore.dataSource addOrUpdateItem:item correlationId:nil error:&error];
    
    // Because there's only one user in the cache calling acquire token should return that
    // item, even though there is no userId info in the item and we specified a user id.
    // This is done for ADFS users where a login hint might have been specified but we
    // can't verify it.
    [context acquireTokenWithResource:TEST_RESOURCE
                             clientId:TEST_CLIENT_ID
                          redirectUri:TEST_REDIRECT_URL
                               userId:@"eric@contoso.com"
                      completionBlock:^(ADAuthenticationResult *result)
     {
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_SUCCEEDED);
         XCTAssertNil(result.error);
         XCTAssertNotNil(result.tokenCacheItem);
         XCTAssertEqualObjects(result.tokenCacheItem, item);
         
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
}

- (void)testSilentNothingCached
{
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    // With nothing cached the operation should fail telling the developer that
    // user input is required.
    [context acquireTokenSilentWithResource:TEST_RESOURCE
                                   clientId:TEST_CLIENT_ID
                                redirectUri:TEST_REDIRECT_URL
                                     userId:TEST_USER_ID
                            completionBlock:^(ADAuthenticationResult *result)
     {
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_FAILED);
         XCTAssertNotNil(result.error);
         XCTAssertEqual(result.error.code, AD_ERROR_SERVER_USER_INPUT_NEEDED);
         
         TEST_SIGNAL;
    }];
    
    TEST_WAIT;
}

- (void)testSilentItemCached
{
    ADAuthenticationError* error = nil;
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    // Add a token item to return in the cache
    ADTokenCacheItem* item = [self adCreateCacheItem];
    [context.tokenCacheStore.dataSource addOrUpdateItem:item correlationId:nil error:&error];
    
    [context acquireTokenSilentWithResource:TEST_RESOURCE
                                   clientId:TEST_CLIENT_ID
                                redirectUri:TEST_REDIRECT_URL
                                     userId:TEST_USER_ID
                            completionBlock:^(ADAuthenticationResult *result)
     {
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_SUCCEEDED);
         XCTAssertNotNil(result.tokenCacheItem);
         XCTAssertEqualObjects(result.tokenCacheItem, item);
         
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
}

- (void)testSilentExpiredItemCached
{
    ADAuthenticationError* error = nil;
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    // Add a expired access token with no refresh token to the cache
    ADTokenCacheItem* item = [self adCreateCacheItem];
    item.expiresOn = [NSDate date];
    item.refreshToken = nil;
    [context.tokenCacheStore.dataSource addOrUpdateItem:item correlationId:nil error:&error];
    XCTAssertNil(error);
    
    [context acquireTokenSilentWithResource:TEST_RESOURCE
                                   clientId:TEST_CLIENT_ID
                                redirectUri:TEST_REDIRECT_URL
                                     userId:TEST_USER_ID
                            completionBlock:^(ADAuthenticationResult *result)
     {
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_FAILED);
         XCTAssertNotNil(result.error);
         XCTAssertEqual(result.error.code, AD_ERROR_SERVER_USER_INPUT_NEEDED);
         
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
    
    // Also verify the expired item has been removed from the cache
    NSArray* allItems = [context.tokenCacheStore.dataSource allItems:&error];
    XCTAssertNil(error);
    XCTAssertEqual(allItems.count, 0);
}

- (void)testSilentBadRefreshToken
{
    ADAuthenticationError* error = nil;
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    // Add a expired access token with refresh token to the cache
    ADTokenCacheItem* item = [self adCreateCacheItem];
    item.expiresOn = [NSDate date];
    [context.tokenCacheStore.dataSource addOrUpdateItem:item correlationId:nil error:&error];
    XCTAssertNil(error);
    
    // Set the response to reject the refresh token
    [ADTestURLConnection addResponse:[self adDefaultBadRefreshTokenResponse]];
    
    [context acquireTokenSilentWithResource:TEST_RESOURCE
                                   clientId:TEST_CLIENT_ID
                                redirectUri:TEST_REDIRECT_URL
                                     userId:TEST_USER_ID
                            completionBlock:^(ADAuthenticationResult *result)
     {
         // Request should fail because it's silent and getting a new RT requires showing UI
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_FAILED);
         XCTAssertNotNil(result.error);
         XCTAssertEqual(result.error.code, AD_ERROR_SERVER_USER_INPUT_NEEDED);
         
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
    
    XCTAssertTrue([ADTestURLConnection noResponsesLeft]);
    
    // Also verify the expired item has been removed from the cache
    NSArray* allItems = [context.tokenCacheStore.dataSource allItems:&error];
    XCTAssertNil(error);
    XCTAssertEqual(allItems.count, 0);
}

- (void)testSilentExpiredATBadMRRT
{
    // prepare and register telemetry dispatcher
    ADTelemetryTestDispatcher* dispatcher = [ADTelemetryTestDispatcher new];
    NSMutableArray* receivedEvents = [NSMutableArray new];
    [dispatcher setTestCallback:^(NSArray* event)
     {
         [receivedEvents addObject:event];
     }];
    [[ADTelemetry sharedInstance] registerDispatcher:dispatcher aggregationRequired:YES];
    
    ADAuthenticationError* error = nil;
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    // Add a expired access token with refresh token to the cache
    ADTokenCacheItem* item = [self adCreateATCacheItem];
    item.expiresOn = [NSDate date];
    [context.tokenCacheStore.dataSource addOrUpdateItem:item correlationId:nil error:&error];
    XCTAssertNil(error);
    
    // Add an MRRT to the cache as well
    [context.tokenCacheStore.dataSource addOrUpdateItem:[self adCreateMRRTCacheItem] correlationId:nil error:&error];
    XCTAssertNil(error);
    
    // Set the response to reject the refresh token
    [ADTestURLConnection addResponse:[self adDefaultBadRefreshTokenResponse]];
    
    [context acquireTokenSilentWithResource:TEST_RESOURCE
                                   clientId:TEST_CLIENT_ID
                                redirectUri:TEST_REDIRECT_URL
                                     userId:TEST_USER_ID
                            completionBlock:^(ADAuthenticationResult *result)
     {
         // Request should fail because it's silent and getting a new RT requires showing UI
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_FAILED);
         XCTAssertNotNil(result.error);
         XCTAssertEqual(result.error.code, AD_ERROR_SERVER_USER_INPUT_NEEDED);
         
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
    
    NSArray* tombstones = [context.tokenCacheStore.dataSource allTombstones:&error];
    XCTAssertEqual(tombstones.count, 1);
    
    // Verify that both the expired AT and the rejected MRRT are removed from the cache
    NSArray* allItems = [context.tokenCacheStore.dataSource allItems:&error];
    XCTAssertNil(error);
    
    XCTAssertTrue([ADTestURLConnection noResponsesLeft]);
    XCTAssertEqual(allItems.count, 0);
    
    // The next acquire token call should fail immediately without hitting network
    [context acquireTokenSilentWithResource:TEST_RESOURCE
                                   clientId:TEST_CLIENT_ID
                                redirectUri:TEST_REDIRECT_URL
                                     userId:TEST_USER_ID
                            completionBlock:^(ADAuthenticationResult *result)
     {
         // Request should fail because it's silent and getting a new RT requires showing UI
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_FAILED);
         XCTAssertNotNil(result.error);
         XCTAssertEqual(result.error.code, AD_ERROR_SERVER_USER_INPUT_NEEDED);
         
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
    
    // verify telemetry output
    // there should be 2 telemetry events recorded as there are 2 acquire token calls
    XCTAssertEqual([receivedEvents count], 2);
    
    // the following properties are expected for the 1st acquire token call
    NSArray* firstEvent = [receivedEvents firstObject];
    XCTAssertEqual([self adGetPropertyCount:firstEvent
                             propertyName:@"api_id"], 1);
    XCTAssertEqual([self adGetPropertyCount:firstEvent
                             propertyName:@"request_id"], 1);
    XCTAssertEqual([self adGetPropertyCount:firstEvent
                             propertyName:@"correlation_id"], 1);
#if TARGET_OS_IPHONE
    // application_version is only available in unit test framework with host app
    XCTAssertEqual([self adGetPropertyCount:firstEvent
                             propertyName:@"application_version"], 1);
#endif
    XCTAssertEqual([self adGetPropertyCount:firstEvent
                             propertyName:@"application_name"], 1);
    XCTAssertEqual([self adGetPropertyCount:firstEvent
                             propertyName:@"x-client-Ver"], 1);
    XCTAssertEqual([self adGetPropertyCount:firstEvent
                             propertyName:@"x-client-SKU"], 1);
    XCTAssertEqual([self adGetPropertyCount:firstEvent
                             propertyName:@"client_id"], 1);
    XCTAssertEqual([self adGetPropertyCount:firstEvent
                             propertyName:@"device_id"], 1);
    XCTAssertEqual([self adGetPropertyCount:firstEvent
                             propertyName:@"authority_type"], 1);
    XCTAssertEqual([self adGetPropertyCount:firstEvent
                             propertyName:@"extended_expires_on_setting"], 1);
    XCTAssertEqual([self adGetPropertyCount:firstEvent
                             propertyName:@"prompt_behavior"], 1);
    XCTAssertEqual([self adGetPropertyCount:firstEvent
                             propertyName:@"status"], 1);
    XCTAssertEqual([self adGetPropertyCount:firstEvent
                             propertyName:@"user_id"], 1);
    XCTAssertEqual([self adGetPropertyCount:firstEvent
                             propertyName:@"response_time"], 1);
    XCTAssertEqual([self adGetPropertyCount:firstEvent
                             propertyName:@"cache_event_count"], 1);
    XCTAssertEqual([self adGetPropertyCount:firstEvent
                             propertyName:@"token_mrrt_status"], 1);
    XCTAssertEqual([self adGetPropertyCount:firstEvent
                             propertyName:@"token_frt_status"], 1);
    XCTAssertEqual([self adGetPropertyCount:firstEvent
                             propertyName:@"http_event_count"], 1);
    XCTAssertEqual([self adGetPropertyCount:firstEvent
                             propertyName:@"error_code"], 1);
    XCTAssertEqual([self adGetPropertyCount:firstEvent
                             propertyName:@"error_domain"], 1);
    XCTAssertEqual([self adGetPropertyCount:firstEvent
                             propertyName:@"error_description"], 1);
    
    // the following properties are expected for 2nd acquire token call
    NSArray* secondEvent = [receivedEvents objectAtIndex:1];
    XCTAssertEqual([self adGetPropertyCount:secondEvent
                             propertyName:@"api_id"], 1);
    XCTAssertEqual([self adGetPropertyCount:secondEvent
                             propertyName:@"request_id"], 1);
    XCTAssertEqual([self adGetPropertyCount:secondEvent
                             propertyName:@"correlation_id"], 1);
#if TARGET_OS_IPHONE
    // application_version is only available in unit test framework with host app
    XCTAssertEqual([self adGetPropertyCount:secondEvent
                             propertyName:@"application_version"], 1);
#endif
    XCTAssertEqual([self adGetPropertyCount:secondEvent
                             propertyName:@"application_name"], 1);
    XCTAssertEqual([self adGetPropertyCount:secondEvent
                             propertyName:@"x-client-Ver"], 1);
    XCTAssertEqual([self adGetPropertyCount:secondEvent
                             propertyName:@"x-client-SKU"], 1);
    XCTAssertEqual([self adGetPropertyCount:secondEvent
                             propertyName:@"client_id"], 1);
    XCTAssertEqual([self adGetPropertyCount:secondEvent
                             propertyName:@"device_id"], 1);
    XCTAssertEqual([self adGetPropertyCount:secondEvent
                             propertyName:@"authority_type"], 1);
    XCTAssertEqual([self adGetPropertyCount:secondEvent
                             propertyName:@"extended_expires_on_setting"], 1);
    XCTAssertEqual([self adGetPropertyCount:secondEvent
                             propertyName:@"prompt_behavior"], 1);
    XCTAssertEqual([self adGetPropertyCount:secondEvent
                             propertyName:@"status"], 1);
    XCTAssertEqual([self adGetPropertyCount:secondEvent
                             propertyName:@"user_id"], 1);
    XCTAssertEqual([self adGetPropertyCount:secondEvent
                             propertyName:@"response_time"], 1);
    XCTAssertEqual([self adGetPropertyCount:secondEvent
                             propertyName:@"cache_event_count"], 1);
    XCTAssertEqual([self adGetPropertyCount:secondEvent
                             propertyName:@"token_rt_status"], 1);
    XCTAssertEqual([self adGetPropertyCount:secondEvent
                             propertyName:@"token_mrrt_status"], 1);
    XCTAssertEqual([self adGetPropertyCount:secondEvent
                             propertyName:@"token_frt_status"], 1);
    XCTAssertEqual([self adGetPropertyCount:secondEvent
                             propertyName:@"error_code"], 1);
    XCTAssertEqual([self adGetPropertyCount:secondEvent
                             propertyName:@"error_domain"], 1);
    XCTAssertEqual([self adGetPropertyCount:secondEvent
                             propertyName:@"error_description"], 1);
    
    //unregister the dispatcher
    [[ADTelemetry sharedInstance] registerDispatcher:nil aggregationRequired:YES];
}

- (void)testSilentExpiredATRefreshMRRTNetwork
{
    ADAuthenticationError* error = nil;
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    // Add a expired access token with refresh token to the cache
    ADTokenCacheItem* item = [self adCreateATCacheItem];
    item.expiresOn = [NSDate date];
    [context.tokenCacheStore.dataSource addOrUpdateItem:item correlationId:nil error:&error];
    XCTAssertNil(error);
    
    // Add an MRRT to the cache as well
    [context.tokenCacheStore.dataSource addOrUpdateItem:[self adCreateMRRTCacheItem] correlationId:nil error:&error];
    XCTAssertNil(error);
    
    [ADTestURLConnection addResponse:[self adDefaultRefreshResponse:@"new refresh token" accessToken:@"new access token"]];
    
    [context acquireTokenSilentWithResource:TEST_RESOURCE
                                   clientId:TEST_CLIENT_ID
                                redirectUri:TEST_REDIRECT_URL
                                     userId:TEST_USER_ID
                            completionBlock:^(ADAuthenticationResult *result)
     {
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_SUCCEEDED);
         XCTAssertNotNil(result.tokenCacheItem);
         XCTAssertTrue([result.correlationId isKindOfClass:[NSUUID class]]);
         XCTAssertEqualObjects(result.accessToken, @"new access token");
         
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
    
    NSArray* allItems = [context.tokenCacheStore.dataSource allItems:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(allItems);
    XCTAssertEqual(allItems.count, 2);
    
    ADTokenCacheItem* mrrtItem = nil;
    ADTokenCacheItem* atItem = nil;
    
    // Pull the MRRT and AT items out of the cache
    for (ADTokenCacheItem * item in allItems)
    {
        if (item.refreshToken)
        {
            mrrtItem = item;
        }
        else if (item.accessToken)
        {
            atItem = item;
        }
    }
    
    XCTAssertNotNil(mrrtItem);
    XCTAssertNotNil(atItem);
    
    XCTAssertNil(atItem.refreshToken);
    XCTAssertNil(mrrtItem.accessToken);
    
    // Make sure the tokens got updated
    XCTAssertEqualObjects(atItem.accessToken, @"new access token");
    XCTAssertEqualObjects(mrrtItem.refreshToken, @"new refresh token");
}

- (void)testMRRTNoNetworkConnection
{
    ADAuthenticationError* error = nil;
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    // Add a expired access token with refresh token to the cache
    ADTokenCacheItem* item = [self adCreateATCacheItem];
    item.expiresOn = [NSDate date];
    [context.tokenCacheStore.dataSource addOrUpdateItem:item correlationId:nil error:&error];
    XCTAssertNil(error);
    
    // Add an MRRT to the cache as well
    ADTokenCacheItem* mrrtItem = [self adCreateMRRTCacheItem];
    [context.tokenCacheStore.dataSource addOrUpdateItem:mrrtItem correlationId:nil error:&error];
    XCTAssertNil(error);
    
    // Set up the mock connection to simulate a no internet connection error
    ADTestURLResponse* response =
    [ADTestURLResponse request:[NSURL URLWithString:TEST_AUTHORITY "/oauth2/token?x-client-Ver=" ADAL_VERSION_STRING]
              respondWithError:[NSError errorWithDomain:NSURLErrorDomain
                                                   code:NSURLErrorNotConnectedToInternet
                                               userInfo:nil]];
    [ADTestURLConnection addResponse:response];
    
    // Web UI should not attempt to launch when we fail to refresh the RT because there is no internet
    // connection
    [context acquireTokenWithResource:TEST_RESOURCE
                             clientId:TEST_CLIENT_ID
                          redirectUri:TEST_REDIRECT_URL
                               userId:TEST_USER_ID
                      completionBlock:^(ADAuthenticationResult *result)
    {
        XCTAssertNotNil(result);
        XCTAssertEqual(result.status, AD_FAILED);
        XCTAssertNotNil(result.error);
        
        TEST_SIGNAL;
    }];
    
    TEST_WAIT;
    
    // The expired AT should be removed from the cache but the MRRT should still be there.
    NSArray* allItems = [context.tokenCacheStore.dataSource allItems:&error];
    XCTAssertNotNil(allItems);
    XCTAssertEqual(allItems.count, 1);
    XCTAssertEqualObjects(allItems[0], mrrtItem);
}

- (void)testMRRTUnauthorizedClient
{
    // Refresh tokens should only be deleted when the server returns a 'invalid_grant' error
    ADAuthenticationError* error = nil;
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    // Add an MRRT to the cache as well
    ADTokenCacheItem* mrrtItem = [self adCreateMRRTCacheItem];
    [context.tokenCacheStore.dataSource addOrUpdateItem:mrrtItem correlationId:nil error:&error];
    XCTAssertNil(error);
    
    // Set up the mock connection to reject the MRRT with an error that should cause it to not remove the MRRT
    [ADTestURLConnection addResponse:[self adDefaultBadRefreshTokenResponseError:@"unauthorized_client"]];
    
    [context acquireTokenSilentWithResource:TEST_RESOURCE
                                   clientId:TEST_CLIENT_ID
                                redirectUri:TEST_REDIRECT_URL
                            completionBlock:^(ADAuthenticationResult *result)
    {
        XCTAssertNotNil(result);
        XCTAssertEqual(result.status, AD_FAILED);
        XCTAssertNotNil(result.error);
        
        TEST_SIGNAL;
    }];
    
    TEST_WAIT;
    
    // The MRRT should still be in the cache
    NSArray* allItems = [context.tokenCacheStore.dataSource allItems:&error];
    XCTAssertNotNil(allItems);
    XCTAssertEqual(allItems.count, 1);
    XCTAssertEqualObjects(allItems[0], mrrtItem);
}

- (void)testRequestRetryOnUnusualHttpResponse
{
    //Create a normal authority (not a test one):
    ADAuthenticationError* error = nil;
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    // Add a expired access token with refresh token to the cache
    ADTokenCacheItem* item = [self adCreateATCacheItem];
    item.expiresOn = [NSDate date];
    item.refreshToken = @"refresh token";
    [context.tokenCacheStore.dataSource addOrUpdateItem:item correlationId:nil error:&error];
    XCTAssertNil(error);
    
    // Add an MRRT to the cache as well
    [context.tokenCacheStore.dataSource addOrUpdateItem:[self adCreateMRRTCacheItem] correlationId:nil error:&error];
    XCTAssertNil(error);
    
    ADTestURLResponse* response = [ADTestURLResponse requestURLString:@"https://login.windows.net/contoso.com/oauth2/token?x-client-Ver=" ADAL_VERSION_STRING
                                                    responseURLString:@"https://contoso.com"
                                                         responseCode:500
                                                     httpHeaderFields:@{ } // maybe shoehorn correlation ID here
                                                     dictionaryAsJSON:@{ OAUTH2_ERROR : @"server_error",
                                                                         OAUTH2_ERROR_DESCRIPTION : @"AADSTS90036: Non-retryable error has occurred." }];
    
    //It should hit network twice for trying and retrying the refresh token because it is an server error
    //Then hit network twice again for broad refresh token for the same reason
    //So totally 4 responses are added
    //If there is an infinite retry, exception will be thrown becasuse there is not enough responses
    [ADTestURLConnection addResponse:response];
    [ADTestURLConnection addResponse:response];
    
    [context acquireTokenWithResource:TEST_RESOURCE
                             clientId:TEST_CLIENT_ID
                          redirectUri:TEST_REDIRECT_URL
                               userId:TEST_USER_ID
                      completionBlock:^(ADAuthenticationResult *result)
     {
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_FAILED);
         XCTAssertNotNil(result.error);
         
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
    
    NSArray* allItems = [context.tokenCacheStore.dataSource allItems:&error];
    XCTAssertNotNil(allItems);
    XCTAssertEqual(allItems.count, 2);
}

- (void)testAdditionalServerProperties
{
    ADAuthenticationError* error = nil;
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    id<ADTokenCacheDataSource> cache = [context tokenCacheStore].dataSource;
    XCTAssertNotNil(cache);
    
    XCTAssertTrue([cache addOrUpdateItem:[self adCreateMRRTCacheItem] correlationId:nil error:&error]);
    XCTAssertNil(error);
    
    NSDictionary* additional = @{ @"arbitraryProperty" : @"save_me",
                                  @"thing-that-if-it-doesnt-get-saved-might-hose-us-later" : @"not-hosed" };
    
    ADTestURLResponse* response = [self adResponseRefreshToken:TEST_REFRESH_TOKEN
                                                     authority:TEST_AUTHORITY
                                                      resource:TEST_RESOURCE
                                                      clientId:TEST_CLIENT_ID
                                                 correlationId:TEST_CORRELATION_ID
                                               newRefreshToken:TEST_REFRESH_TOKEN
                                                newAccessToken:TEST_ACCESS_TOKEN
                                              additionalFields:additional];
    
    [ADTestURLConnection addResponse:response];
    
    [context acquireTokenSilentWithResource:TEST_RESOURCE
                                   clientId:TEST_CLIENT_ID
                                redirectUri:TEST_REDIRECT_URL
                                     userId:TEST_USER_ID
                            completionBlock:^(ADAuthenticationResult *result)
     {
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_SUCCEEDED);
         XCTAssertNotNil(result.tokenCacheItem);
         XCTAssertEqualObjects(result.accessToken, TEST_ACCESS_TOKEN);
         
         NSDictionary* additionalServer = result.tokenCacheItem.additionalServer;
         XCTAssertNotNil(additionalServer);
         // We need to make sure the additionalServer dictionary contains everything in the additional
         // dictionary, but if there's other stuff there as well it's okay.
         for (NSString* key in additional)
         {
             XCTAssertEqualObjects(additionalServer[key], additional[key], @"Expected \"%@\" for \"%@\", Actual: \"%@\"", additionalServer[key], key, additional[key]);
         }
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
}

- (void)testAdditionalClientRetainedOnRefresh
{
    ADAuthenticationError* error = nil;
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    id<ADTokenCacheDataSource> cache = [context tokenCacheStore].dataSource;
    XCTAssertNotNil(cache);
    
    ADTokenCacheItem* item = [self adCreateMRRTCacheItem];
    NSMutableDictionary* additional = [NSMutableDictionary new];
    additional[@"client_prop_1"] = @"something-client-side";
    item.additionalClient = additional;
    
    XCTAssertTrue([cache addOrUpdateItem:item correlationId:nil error:&error]);
    XCTAssertNil(error);
    
    ADTestURLResponse* response = [self adResponseRefreshToken:TEST_REFRESH_TOKEN
                                                     authority:TEST_AUTHORITY
                                                      resource:TEST_RESOURCE
                                                      clientId:TEST_CLIENT_ID
                                                 correlationId:TEST_CORRELATION_ID
                                               newRefreshToken:@"new-mrrt"
                                                newAccessToken:TEST_ACCESS_TOKEN
                                              additionalFields:nil];
    [ADTestURLConnection addResponse:response];
    
    [context acquireTokenSilentWithResource:TEST_RESOURCE
                                   clientId:TEST_CLIENT_ID
                                redirectUri:TEST_REDIRECT_URL
                                     userId:TEST_USER_ID
                            completionBlock:^(ADAuthenticationResult *result)
     {
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_SUCCEEDED);
         XCTAssertNotNil(result.tokenCacheItem);
         XCTAssertEqualObjects(result.accessToken, TEST_ACCESS_TOKEN);
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
    
    // Pull the MRRT directly out of the cache after the acquireTokenSilent operation
    ADTokenCacheKey* mrrtKey = [ADTokenCacheKey keyWithAuthority:TEST_AUTHORITY resource:nil clientId:TEST_CLIENT_ID error:nil];
    XCTAssertNotNil(mrrtKey);
    ADTokenCacheItem* itemFromCache = [cache getItemWithKey:mrrtKey userId:TEST_USER_ID correlationId:TEST_CORRELATION_ID error:nil];
    XCTAssertNotNil(itemFromCache);
    
    // And make sure the additionalClient dictionary is still there unharmed
    XCTAssertEqualObjects(itemFromCache.additionalClient, additional);
    XCTAssertEqualObjects(itemFromCache.refreshToken, @"new-mrrt");
}

// Make sure that if we get a token response from the server that includes a family ID we cache it properly
- (void)testAcquireRefreshFamilyTokenNetwork
{
    ADAuthenticationError* error = nil;
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    id<ADTokenCacheDataSource> cache = [context tokenCacheStore].dataSource;
    XCTAssertNotNil(cache);
    
    XCTAssertTrue([cache addOrUpdateItem:[self adCreateMRRTCacheItem] correlationId:nil error:&error]);
    XCTAssertNil(error);
    
    ADTestURLResponse* response = [self adResponseRefreshToken:TEST_REFRESH_TOKEN
                                                     authority:TEST_AUTHORITY
                                                      resource:TEST_RESOURCE
                                                      clientId:TEST_CLIENT_ID
                                                 correlationId:TEST_CORRELATION_ID
                                               newRefreshToken:TEST_REFRESH_TOKEN
                                                newAccessToken:TEST_ACCESS_TOKEN
                                              additionalFields:@{ ADAL_CLIENT_FAMILY_ID : @"1"}];
    
    [ADTestURLConnection addResponse:response];
    
    [context acquireTokenSilentWithResource:TEST_RESOURCE
                                   clientId:TEST_CLIENT_ID
                                redirectUri:TEST_REDIRECT_URL
                                     userId:TEST_USER_ID
                            completionBlock:^(ADAuthenticationResult *result)
    {
        XCTAssertNotNil(result);
        XCTAssertEqual(result.status, AD_SUCCEEDED);
        XCTAssertNotNil(result.tokenCacheItem);
        XCTAssertEqualObjects(result.accessToken, TEST_ACCESS_TOKEN);
        XCTAssertEqualObjects(result.tokenCacheItem.familyId, @"1");
        TEST_SIGNAL;
    }];

    TEST_WAIT;
    
    // Verfiy the FRT is now properly stored in cache
    ADTokenCacheKey* frtKey = [ADTokenCacheKey keyWithAuthority:TEST_AUTHORITY
                                                       resource:nil
                                                       clientId:@"foci-1"
                                                          error:&error];
    XCTAssertNotNil(frtKey);
    XCTAssertNil(error);
    
    ADTokenCacheItem* frtItem = [cache getItemWithKey:frtKey
                                               userId:TEST_USER_ID
                                        correlationId:nil
                                                error:&error];
    XCTAssertNotNil(frtItem);
    XCTAssertNil(error);
    
    XCTAssertEqualObjects(TEST_REFRESH_TOKEN, frtItem.refreshToken);
}

- (void)testAcquireTokenUsingFRT
{
    // prepare and register telemetry dispatcher
    ADTelemetryTestDispatcher* dispatcher = [ADTelemetryTestDispatcher new];
    NSMutableArray* receivedEvents = [NSMutableArray new];
    [dispatcher setTestCallback:^(NSArray* event)
     {
         [receivedEvents addObject:event];
     }];
    [[ADTelemetry sharedInstance] registerDispatcher:dispatcher aggregationRequired:YES];
    
    // Simplest FRT case, the only RT available is the FRT so that would should be the one used
    ADAuthenticationError* error = nil;
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    id<ADTokenCacheDataSource> cache = [context tokenCacheStore].dataSource;
    XCTAssertNotNil(cache);
    
    XCTAssertTrue([cache addOrUpdateItem:[self adCreateFRTCacheItem] correlationId:nil error:&error]);
    XCTAssertNil(error);
    
    ADTestURLResponse* response = [self adResponseRefreshToken:@"family refresh token"
                                                     authority:TEST_AUTHORITY
                                                      resource:TEST_RESOURCE
                                                      clientId:TEST_CLIENT_ID
                                                 correlationId:TEST_CORRELATION_ID
                                               newRefreshToken:@"new family refresh token"
                                                newAccessToken:TEST_ACCESS_TOKEN
                                              additionalFields:@{ ADAL_CLIENT_FAMILY_ID : @"1"}];
    
    [ADTestURLConnection addResponse:response];
    
    [context acquireTokenSilentWithResource:TEST_RESOURCE
                                   clientId:TEST_CLIENT_ID
                                redirectUri:TEST_REDIRECT_URL
                                     userId:TEST_USER_ID
                            completionBlock:^(ADAuthenticationResult *result)
     {
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_SUCCEEDED);
         XCTAssertNotNil(result.tokenCacheItem);
         XCTAssertEqualObjects(result.accessToken, TEST_ACCESS_TOKEN);
         XCTAssertEqualObjects(result.tokenCacheItem.refreshToken, @"new family refresh token");
         XCTAssertEqualObjects(result.tokenCacheItem.familyId, @"1");
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
    
    // verify telemetry output
    // there should be 1 telemetry events recorded as aggregation flag is ON
    XCTAssertEqual([receivedEvents count], 1);
    
    // the following properties are expected in an aggregrated event
    NSArray* event = [receivedEvents firstObject];
    XCTAssertEqual([self adGetPropertyCount:event
                               propertyName:@"api_id"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                               propertyName:@"request_id"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                               propertyName:@"correlation_id"], 1);
#if TARGET_OS_IPHONE
    // application_version is only available in unit test framework with host app
    XCTAssertEqual([self adGetPropertyCount:event
                               propertyName:@"application_version"], 1);
#endif
    XCTAssertEqual([self adGetPropertyCount:event
                               propertyName:@"application_name"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                               propertyName:@"x-client-Ver"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                               propertyName:@"x-client-SKU"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                               propertyName:@"client_id"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                               propertyName:@"device_id"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                               propertyName:@"authority_type"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                               propertyName:@"extended_expires_on_setting"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                               propertyName:@"prompt_behavior"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                               propertyName:@"status"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                               propertyName:@"tenant_id"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                               propertyName:@"user_id"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                               propertyName:@"response_time"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                               propertyName:@"cache_event_count"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                               propertyName:@"token_rt_status"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                               propertyName:@"token_mrrt_status"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                               propertyName:@"token_frt_status"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                               propertyName:@"http_event_count"], 1);
    XCTAssertEqual([self adGetPropertyCount:event
                               propertyName:@"error_code"], 1);
    
    //unregister the dispatcher
    [[ADTelemetry sharedInstance] registerDispatcher:nil aggregationRequired:YES];
}

- (void)testAcquireTokenMRRTFailFRTFallback
{
    // In this case we have an invalid MRRT that's not tagged as being a family
    // token, but a valid FRT, we want to make sure that the FRT gets tried once
    // the MRRT fails.
    
    ADAuthenticationError* error = nil;
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    id<ADTokenCacheDataSource> cache = [context tokenCacheStore].dataSource;
    XCTAssertNotNil(cache);
    
    XCTAssertTrue([cache addOrUpdateItem:[self adCreateFRTCacheItem] correlationId:nil error:&error]);
    XCTAssertTrue([cache addOrUpdateItem:[self adCreateMRRTCacheItem] correlationId:nil error:&error]);
    XCTAssertNil(error);
    
    // This is the error message the server sends when MFA is required, it should cause the token to
    // not be deleted right away, but when we get the success response with the FRT it should cause
    // the MRRT to be replaced
    ADTestURLResponse* badMRRT = [self adDefaultBadRefreshTokenResponseError:@"interaction_required"];
    
    ADTestURLResponse* frtResponse =
    [self adResponseRefreshToken:@"family refresh token"
                       authority:TEST_AUTHORITY
                        resource:TEST_RESOURCE
                        clientId:TEST_CLIENT_ID
                   correlationId:TEST_CORRELATION_ID
                 newRefreshToken:@"new family refresh token"
                  newAccessToken:TEST_ACCESS_TOKEN
                additionalFields:@{ ADAL_CLIENT_FAMILY_ID : @"1"}];
    
    [ADTestURLConnection addResponses:@[badMRRT, frtResponse]];
    
    [context acquireTokenSilentWithResource:TEST_RESOURCE
                                   clientId:TEST_CLIENT_ID
                                redirectUri:TEST_REDIRECT_URL
                                     userId:TEST_USER_ID
                            completionBlock:^(ADAuthenticationResult *result)
     {
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_SUCCEEDED);
         XCTAssertNotNil(result.tokenCacheItem);
         XCTAssertEqualObjects(result.accessToken, TEST_ACCESS_TOKEN);
         XCTAssertEqualObjects(result.tokenCacheItem.refreshToken, @"new family refresh token");
         XCTAssertEqualObjects(result.tokenCacheItem.familyId, @"1");
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
    
    // Also make sure that cache state is properly updated
    ADTokenCacheKey* mrrtKey = [ADTokenCacheKey keyWithAuthority:TEST_AUTHORITY
                                                        resource:nil
                                                        clientId:TEST_CLIENT_ID
                                                           error:&error];
    XCTAssertNotNil(mrrtKey);
    XCTAssertNil(error);
    
    ADTokenCacheItem* mrrtItem = [cache getItemWithKey:mrrtKey userId:TEST_USER_ID correlationId:nil error:&error];
    XCTAssertNotNil(mrrtItem);
    XCTAssertNil(error);
    XCTAssertEqualObjects(mrrtItem.refreshToken, @"new family refresh token");
    XCTAssertEqualObjects(mrrtItem.familyId, @"1");
    
    ADTokenCacheKey* frtKey = [ADTokenCacheKey keyWithAuthority:TEST_AUTHORITY
                                                       resource:nil
                                                       clientId:@"foci-1"
                                                          error:&error];
    XCTAssertNotNil(frtKey);
    XCTAssertNil(error);
    
    ADTokenCacheItem* frtItem = [cache getItemWithKey:frtKey userId:TEST_USER_ID correlationId:nil error:&error];
    XCTAssertNotNil(frtItem);
    XCTAssertNil(error);
    XCTAssertEqualObjects(frtItem.refreshToken, @"new family refresh token");
}

- (void)testFRTFailFallbackToMRRT
{
    // In this case we have a MRRT marked with a family ID and a FRT that does not work, here we want
    // to make sure that we fallback onto the MRRT.
    ADAuthenticationError* error = nil;
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    id<ADTokenCacheDataSource> cache = [context tokenCacheStore].dataSource;
    XCTAssertNotNil(cache);
    
    XCTAssertTrue([cache addOrUpdateItem:[self adCreateFRTCacheItem] correlationId:nil error:&error]);
    XCTAssertTrue([cache addOrUpdateItem:[self adCreateMRRTCacheItem:TEST_USER_ID familyId:@"1"] correlationId:nil error:&error]);
    XCTAssertNil(error);
    
    ADTestURLResponse* badFRTResponse =
    [self adResponseBadRefreshToken:@"family refresh token"
                          authority:TEST_AUTHORITY
                           resource:TEST_RESOURCE
                           clientId:TEST_CLIENT_ID
                         oauthError:@"invalid_grant"
                      correlationId:TEST_CORRELATION_ID];
    
    ADTestURLResponse* mrrtResponse =
    [self adResponseRefreshToken:TEST_REFRESH_TOKEN
                       authority:TEST_AUTHORITY
                        resource:TEST_RESOURCE
                        clientId:TEST_CLIENT_ID
                   correlationId:TEST_CORRELATION_ID
                 newRefreshToken:@"new family refresh token"
                  newAccessToken:@"new access token"
                additionalFields:@{ ADAL_CLIENT_FAMILY_ID : @"1"}];
    
    [ADTestURLConnection addResponses:@[badFRTResponse, mrrtResponse]];
    
    [context acquireTokenSilentWithResource:TEST_RESOURCE
                                   clientId:TEST_CLIENT_ID
                                redirectUri:TEST_REDIRECT_URL
                            completionBlock:^(ADAuthenticationResult *result)
    {
        XCTAssertNotNil(result);
        XCTAssertEqual(result.status, AD_SUCCEEDED);
        XCTAssertNotNil(result.tokenCacheItem);
        XCTAssertEqualObjects(result.accessToken, @"new access token");
        XCTAssertEqualObjects(result.tokenCacheItem.refreshToken, @"new family refresh token");
        XCTAssertEqualObjects(result.tokenCacheItem.familyId, @"1");
        TEST_SIGNAL;
    }];
    
    TEST_WAIT;
    
    // Make sure that cache state is properly updated
    ADTokenCacheKey* mrrtKey = [ADTokenCacheKey keyWithAuthority:TEST_AUTHORITY
                                                        resource:nil
                                                        clientId:TEST_CLIENT_ID
                                                           error:&error];
    XCTAssertNotNil(mrrtKey);
    XCTAssertNil(error);
    
    ADTokenCacheItem* mrrtItem = [cache getItemWithKey:mrrtKey userId:TEST_USER_ID correlationId:nil error:&error];
    XCTAssertNotNil(mrrtItem);
    XCTAssertNil(error);
    XCTAssertEqualObjects(mrrtItem.refreshToken, @"new family refresh token");
    XCTAssertEqualObjects(mrrtItem.familyId, @"1");
    
    ADTokenCacheKey* frtKey = [ADTokenCacheKey keyWithAuthority:TEST_AUTHORITY
                                                       resource:nil
                                                       clientId:@"foci-1"
                                                          error:&error];
    XCTAssertNotNil(frtKey);
    XCTAssertNil(error);
    
    ADTokenCacheItem* frtItem = [cache getItemWithKey:frtKey userId:TEST_USER_ID correlationId:nil error:&error];
    XCTAssertNotNil(frtItem);
    XCTAssertNil(error);
    XCTAssertEqualObjects(frtItem.refreshToken, @"new family refresh token");
}

- (void)testFociMRRTWithNoFRT
{
    // This case is to make sure that if we have a MRRT marked with a family ID but no FRT in the
    // cache that we still use the MRRT
    ADAuthenticationError* error = nil;
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    
    id<ADTokenCacheDataSource> cache = [context tokenCacheStore].dataSource;
    XCTAssertNotNil(cache);
    
    XCTAssertTrue([cache addOrUpdateItem:[self adCreateMRRTCacheItem:TEST_USER_ID familyId:@"1"] correlationId:nil error:&error]);
    XCTAssertNil(error);
    
    ADTestURLResponse* mrrtResponse =
    [self adResponseRefreshToken:TEST_REFRESH_TOKEN
                       authority:TEST_AUTHORITY
                        resource:TEST_RESOURCE
                        clientId:TEST_CLIENT_ID
                   correlationId:TEST_CORRELATION_ID
                 newRefreshToken:@"new family refresh token"
                  newAccessToken:@"new access token"
                additionalFields:@{ ADAL_CLIENT_FAMILY_ID : @"1"}];
    [ADTestURLConnection addResponse:mrrtResponse];
    
    [context acquireTokenSilentWithResource:TEST_RESOURCE
                                   clientId:TEST_CLIENT_ID
                                redirectUri:TEST_REDIRECT_URL
                            completionBlock:^(ADAuthenticationResult *result)
     {
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_SUCCEEDED);
         XCTAssertNotNil(result.tokenCacheItem);
         XCTAssertEqualObjects(result.accessToken, @"new access token");
         XCTAssertEqualObjects(result.tokenCacheItem.refreshToken, @"new family refresh token");
         XCTAssertEqualObjects(result.tokenCacheItem.familyId, @"1");
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
    
    // Make sure that cache state is properly updated
    ADTokenCacheKey* mrrtKey = [ADTokenCacheKey keyWithAuthority:TEST_AUTHORITY
                                                        resource:nil
                                                        clientId:TEST_CLIENT_ID
                                                           error:&error];
    XCTAssertNotNil(mrrtKey);
    XCTAssertNil(error);
    
    ADTokenCacheItem* mrrtItem = [cache getItemWithKey:mrrtKey userId:TEST_USER_ID correlationId:nil error:&error];
    XCTAssertNotNil(mrrtItem);
    XCTAssertNil(error);
    XCTAssertEqualObjects(mrrtItem.refreshToken, @"new family refresh token");
    XCTAssertEqualObjects(mrrtItem.familyId, @"1");
    
    ADTokenCacheKey* frtKey = [ADTokenCacheKey keyWithAuthority:TEST_AUTHORITY
                                                       resource:nil
                                                       clientId:@"foci-1"
                                                          error:&error];
    XCTAssertNotNil(frtKey);
    XCTAssertNil(error);
    
    ADTokenCacheItem* frtItem = [cache getItemWithKey:frtKey userId:TEST_USER_ID correlationId:nil error:&error];
    XCTAssertNotNil(frtItem);
    XCTAssertNil(error);
    XCTAssertEqualObjects(frtItem.refreshToken, @"new family refresh token");
}

- (void)testExtraQueryParams
{
    // TODO: Requires testing auth code flow
}

- (void)testUserSignIn
{
    // TODO: Requires testing auth code flow
}


- (void)testADFSUserSignIn
{
    // TODO: Requires testing auth code flow
    
    // Sign in a user without an idtoken coming back
}

- (void)testResilencyTokenReturn
{
    ADAuthenticationError* error = nil;
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    id<ADTokenCacheDataSource> cache = [context tokenCacheStore].dataSource;
    
    // Add an MRRT to the cache
    [cache addOrUpdateItem:[self adCreateMRRTCacheItem] correlationId:nil error:&error];
    XCTAssertNil(error);
    
    // Response with ext_expires_in value
    [ADTestURLConnection addResponse:[self adResponseRefreshToken:TEST_REFRESH_TOKEN
                                                        authority:TEST_AUTHORITY
                                                         resource:TEST_RESOURCE
                                                         clientId:TEST_CLIENT_ID
                                                    correlationId:TEST_CORRELATION_ID
                                                  newRefreshToken:@"refresh token"
                                                   newAccessToken:@"access token"
                                                 additionalFields:@{ @"ext_expires_in" : @"3600"}]];
    
    [context acquireTokenWithResource:TEST_RESOURCE
                             clientId:TEST_CLIENT_ID
                          redirectUri:TEST_REDIRECT_URL
                               userId:TEST_USER_ID
                      completionBlock:^(ADAuthenticationResult *result)
     {
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_SUCCEEDED);
         XCTAssertNil(result.error);
         
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
    
    // retrieve the AT from cache
    ADTokenCacheKey* atKey = [ADTokenCacheKey keyWithAuthority:TEST_AUTHORITY
                                                        resource:TEST_RESOURCE
                                                        clientId:TEST_CLIENT_ID
                                                           error:&error];
    XCTAssertNotNil(atKey);
    XCTAssertNil(error);
    
    ADTokenCacheItem* atItem = [cache getItemWithKey:atKey userId:TEST_USER_ID correlationId:nil error:&error];
    XCTAssertNotNil(atItem);
    XCTAssertNil(error);
    
    // Make sure ext_expires_on is in the AT and set with proper value
    NSDate* extExpires = [atItem.additionalServer valueForKey:@"ext_expires_on"];
    NSDate* expectedExpiresTime = [NSDate dateWithTimeIntervalSinceNow:3600];
    XCTAssertNotNil(extExpires);
    XCTAssertTrue([expectedExpiresTime timeIntervalSinceDate:extExpires]<10); // 10 secs as tolerance
    
    // Purposely expire the AT
    atItem.expiresOn = [NSDate date];
    [cache addOrUpdateItem:atItem correlationId:nil error:&error];
    XCTAssertNil(error);
    
    // Test resiliency when response code 503/504 happens
    ADTestURLResponse* response = [ADTestURLResponse requestURLString:[NSString stringWithFormat:@"%@/oauth2/token?x-client-Ver=" ADAL_VERSION_STRING, TEST_AUTHORITY]
                                                    responseURLString:@"https://contoso.com"
                                                         responseCode:504
                                                     httpHeaderFields:@{ }
                                                     dictionaryAsJSON:@{ }];
    // Add the responsce twice because retry will happen
    [ADTestURLConnection addResponse:response];
    [ADTestURLConnection addResponse:response];
    
    // Test whether valid stale access token is returned
    [context setExtendedLifetimeEnabled:YES];
    [context acquireTokenWithResource:TEST_RESOURCE
                             clientId:TEST_CLIENT_ID
                          redirectUri:TEST_REDIRECT_URL
                               userId:TEST_USER_ID
                      completionBlock:^(ADAuthenticationResult *result)
     {
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_SUCCEEDED);
         XCTAssertNil(result.error);
         XCTAssertTrue(result.extendedLifeTimeToken);
         XCTAssertEqualObjects(result.tokenCacheItem.accessToken, @"access token");
         
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
    
    XCTAssertTrue([ADTestURLConnection noResponsesLeft]);
}

- (void)testResilencyTokenDeletion
{
    ADAuthenticationError* error = nil;
    ADAuthenticationContext* context = [self getTestAuthenticationContext];
    id<ADTokenCacheDataSource> cache = [context tokenCacheStore].dataSource;
    
    // Add an MRRT to the cache
    [cache addOrUpdateItem:[self adCreateMRRTCacheItem] correlationId:nil error:&error];
    XCTAssertNil(error);
    
    // Response with ext_expires_in value being 0
    [ADTestURLConnection addResponse:[self adResponseRefreshToken:TEST_REFRESH_TOKEN
                                                        authority:TEST_AUTHORITY
                                                         resource:TEST_RESOURCE
                                                         clientId:TEST_CLIENT_ID
                                                    correlationId:TEST_CORRELATION_ID
                                                  newRefreshToken:@"refresh token"
                                                   newAccessToken:@"access token"
                                                 additionalFields:@{ @"ext_expires_in" : @"0"}]];
    
    [context acquireTokenWithResource:TEST_RESOURCE
                             clientId:TEST_CLIENT_ID
                          redirectUri:TEST_REDIRECT_URL
                               userId:TEST_USER_ID
                      completionBlock:^(ADAuthenticationResult *result)
     {
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_SUCCEEDED);
         XCTAssertNil(result.error);
         
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
    
    // Purposely expire the AT
    ADTokenCacheKey* atKey = [ADTokenCacheKey keyWithAuthority:TEST_AUTHORITY
                                                      resource:TEST_RESOURCE
                                                      clientId:TEST_CLIENT_ID
                                                         error:&error];
    XCTAssertNotNil(atKey);
    XCTAssertNil(error);
    
    ADTokenCacheItem* atItem = [cache getItemWithKey:atKey userId:TEST_USER_ID correlationId:nil error:&error];
    XCTAssertNotNil(atItem);
    XCTAssertNil(error);
    
    atItem.expiresOn = [NSDate date];
    [cache addOrUpdateItem:atItem correlationId:nil error:&error];
    XCTAssertNil(error);
    
    // Delete the MRRT
    ADTokenCacheKey* rtKey = [ADTokenCacheKey keyWithAuthority:TEST_AUTHORITY
                                                      resource:nil
                                                      clientId:TEST_CLIENT_ID
                                                         error:&error];
    XCTAssertNotNil(rtKey);
    XCTAssertNil(error);
    
    ADTokenCacheItem* rtItem = [cache getItemWithKey:rtKey userId:TEST_USER_ID correlationId:nil error:&error];
    XCTAssertNotNil(rtItem);
    XCTAssertNil(error);
    
    [cache removeItem:rtItem error:&error];
    XCTAssertNil(error);

    // AT is no longer valid neither in terms of expires_on and ext_expires_on
    [context acquireTokenSilentWithResource:TEST_RESOURCE
                                   clientId:TEST_CLIENT_ID
                                redirectUri:TEST_REDIRECT_URL
                                     userId:TEST_USER_ID
                            completionBlock:^(ADAuthenticationResult *result)
     {
         // Request should fail because it's silent
         XCTAssertNotNil(result);
         XCTAssertEqual(result.status, AD_FAILED);
         XCTAssertNotNil(result.error);
         XCTAssertEqual(result.error.code, AD_ERROR_SERVER_USER_INPUT_NEEDED);
         
         TEST_SIGNAL;
     }];
    
    TEST_WAIT;
    
    // Verify that the AT is removed from the cache
    NSArray* allItems = [cache allItems:&error];
    XCTAssertNil(error);
    
    XCTAssertTrue([ADTestURLConnection noResponsesLeft]);
    XCTAssertEqual(allItems.count, 0);
}

@end
