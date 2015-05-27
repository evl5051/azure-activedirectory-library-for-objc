// Copyright © Microsoft Open Technologies, Inc.
//
// All Rights Reserved
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
// OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
// ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A
// PARTICULAR PURPOSE, MERCHANTABILITY OR NON-INFRINGEMENT.
//
// See the Apache License, Version 2.0 for the specific language
// governing permissions and limitations under the License.

@interface ADAuthenticationContext (TokenCaching)

/*Attemps to use the cache. Returns YES if an attempt was successful or if an
 internal asynchronous call will proceed the processing. */
- (void)attemptToUseCacheItem:(ADTokenCacheStoreItem*)item
               useAccessToken:(BOOL)useAccessToken
                samlAssertion:(NSString*)samlAssertion
                assertionType:(ADAssertionType)assertionType
                     resource:(NSString*)resource
                     clientId:(NSString*)clientId
                  redirectUri:(NSString*)redirectUri
                       userId:(NSString*)userId
                correlationId:(NSUUID*)correlationId
              completionBlock:(ADAuthenticationCallback)completionBlock;

/*Attemps to use the cache. Returns YES if an attempt was successful or if an
 internal asynchronous call will proceed the processing. */
- (void)attemptToUseCacheItem:(ADTokenCacheStoreItem*)item
               useAccessToken:(BOOL)useAccessToken
                     resource:(NSString*)resource
                     clientId:(NSString*)clientId
                  redirectUri:(NSURL*)redirectUri
               promptBehavior:(ADPromptBehavior)promptBehavior
                       silent:(BOOL)silent
                       userId:(NSString*)userId
         extraQueryParameters:(NSString*)queryParams
                correlationId:(NSUUID*)correlationId
              completionBlock:(ADAuthenticationCallback)completionBlock;

//Understands and processes the access token response:
- (ADAuthenticationResult *)processTokenResponse:(NSDictionary *)response
                                         forItem:(ADTokenCacheStoreItem*)item
                                     fromRefresh:(BOOL)fromRefreshTokenWorkflow
                            requestCorrelationId:(NSUUID*)requestCorrelationId;

//Checks the cache for item that can be used to get directly or indirectly an access token.
//Checks the multi-resource refresh tokens too.
- (ADTokenCacheStoreItem*)findCacheItemWithKey:(ADTokenCacheStoreKey*) key
                                        userId:(NSString*) userId
                                useAccessToken:(BOOL*) useAccessToken
                                         error:(ADAuthenticationError* __autoreleasing*) error;

//Stores the result in the cache. cacheItem parameter may be nil, if the result is successfull and contains
//the item to be stored.
- (void)updateCacheToResult:(ADAuthenticationResult*)result
                  cacheItem:(ADTokenCacheStoreItem*)cacheItem
           withRefreshToken:(NSString*)refreshToken;
- (void)updateCacheToResult:(ADAuthenticationResult*)result
              cacheInstance:(id<ADTokenCacheStoring>)tokenCacheStoreInstance
                  cacheItem:(ADTokenCacheStoreItem*)cacheItem
           withRefreshToken:(NSString*)refreshToken;

@end