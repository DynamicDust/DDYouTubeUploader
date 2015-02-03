//
//  DDYouTubeUploader.m
//  DDYouTubeUploader
//
//  Created by Dominik Hadl on 7/2/14.
//  Copyright (c) 2013 DynamicDust s.r.o. All rights reserved.
//
//----------------------------------------------------------------------
#import "DDYouTubeUploader.h"
@import Security;
//----------------------------------------------------------------------

NSString *const kDDYouTubeVideoMetadataTitleKey       = @"kDDYouTubeVideoMetadataTitleKey";
NSString *const kDDYouTubeVideoMetadataDescriptionKey = @"kDDYouTubeVideoMetadataDescriptionKey";
NSString *const kDDYouTubeVideoMetadataKeywordsKey    = @"kDDYouTubeVideoMetadataKeywordsKey";
NSString *const kDDYouTubeVideoMetadataCategoryKey    = @"kDDYouTubeVideoMetadataCategoryKey";

// Keychain constants
NSString *const kDDYouTubeAuthorizationEmailKey     = @"kDDYouTubeAuthorizationEmailKey";
NSString *const kDDYouTubeAuthorizationPasswordKey  = @"kDDYouTubeAuthorizationPasswordKey";

typedef NS_ENUM(NSInteger, DDYouTubeUploaderConnectionType)
{
    DDYouTubeUploaderConnectionTypeLogIn,
    DDYouTubeUploaderConnectionTypePrepare,
    DDYouTubeUploaderConnectionTypeUpload
};

//----------------------------------------------------------------------
#pragma mark - DDURLConnection -
//----------------------------------------------------------------------
@interface DDURLConnection : NSURLConnection
//----------------------------------------------------------------------

@property (nonatomic, assign) DDYouTubeUploaderConnectionType type;

// Overriden to return DDURLConnection *
+ (DDURLConnection *)connectionWithRequest:(NSURLRequest *)request delegate:(id)delegate;

//----------------------------------------------------------------------
@end
//----------------------------------------------------------------------
@implementation DDURLConnection
//----------------------------------------------------------------------

+ (DDURLConnection *)connectionWithRequest:(NSURLRequest *)request delegate:(id)delegate
{
    return [[self alloc] initWithRequest:request delegate:delegate];
}

//----------------------------------------------------------------------

- (instancetype)initWithRequest:(NSURLRequest *)request delegate:(id)delegate
{
    self = [super initWithRequest:request delegate:delegate];
    
    return self;
}

//----------------------------------------------------------------------
@end

//----------------------------------------------------------------------
#pragma mark - Interface -
//----------------------------------------------------------------------
@interface DDYouTubeUploader () <NSXMLParserDelegate>
{
    NSUInteger _videoFileLength;
}

// Log In
@property (nonatomic, assign) BOOL isLoggedIn;
@property (nonatomic, strong) NSString *authorizationToken;

// Connection, response, parser
@property (nonatomic, strong) NSMutableData   *responseData;
@property (nonatomic, strong) DDURLConnection *currentConnection;
@property (nonatomic, strong) NSMutableString *currentParserString;

// Video URLs
@property (nonatomic, strong) NSURL *localVideoURL;
@property (nonatomic, strong) NSURL *remoteVideoURL;

// Upload Authorization
@property (nonatomic, strong) NSString *uploadToken;
@property (nonatomic, strong) NSString *uploadURLString;

// State and completion block
@property (nonatomic, assign, readwrite) DDYouTubeUploaderState state;

@property (nonatomic, copy, readwrite) loginCompletionBlock loginCompletionBlock;
@property (nonatomic, copy, readwrite) uploadCompletionBlock uploadCompletionBlock;

//----------------------------------------------------------------------
@end

//----------------------------------------------------------------------
#pragma mark - Implementation -
//----------------------------------------------------------------------

@implementation DDYouTubeUploader

//----------------------------------------------------------------------
#pragma mark - Init & Public Methods -
//----------------------------------------------------------------------

+ (instancetype)uploaderWithDeveloperKey:(NSString *)developerKey
{
    return [[self alloc] initWithDeveloperKey:developerKey];
}

//----------------------------------------------------------------------

- (instancetype)initWithDeveloperKey:(NSString *)developerKey
{
    NSAssert(developerKey && developerKey.length > 0, @"Developer key must be specified!");
    
    self = [self init];
    
    if (self)
    {
        self.developerKey = developerKey;
        self.logLevel     = DDYouTubeUploaderLogLevelError;
        self.isCredentialsSavingEnabled = YES;
    }
    
    return self;
}

//----------------------------------------------------------------------
#pragma mark Log In
//----------------------------------------------------------------------

- (void)loginWithEmail:(NSString *)userEmail
           andPassword:(NSString *)userPassword
        withCompletion:(loginCompletionBlock)completionBlock
{
    NSAssert(self.developerKey, @"DDYoutubeUploader: Developer key must be set first.");
    
    self.loginCompletionBlock = completionBlock;
    
    NSString *savedEmail     = [self getUserCredentialForKey:kDDYouTubeAuthorizationEmailKey];
    NSString *savedPassword  = [self getUserCredentialForKey:kDDYouTubeAuthorizationPasswordKey];
    
    if (savedEmail && savedPassword)
    {
        [self logInToYouTubeWithEmail:savedEmail andPassword:savedPassword];
    }
    else
    {
        [self saveUserEmail:userEmail
                andPassword:userPassword];
        
        [self logInToYouTubeWithEmail:userEmail
                          andPassword:userPassword];
    }
}

//----------------------------------------------------------------------
#pragma mark Upload
//----------------------------------------------------------------------

- (void)uploadVideoAtPath:(NSString *)videoPath
             withMetadata:(NSDictionary *)videoMetadata
           withCompletion:(uploadCompletionBlock)completionBlock
{
    NSAssert(self.developerKey, @"DDYoutubeUploader: Developer key must be set first.");
    
    if (!self.isLoggedIn)
    {
        [self logError:@"User not logged in, cannot upload video."];
        return;
    }
    
    
    self.localVideoURL          = [NSURL fileURLWithPath:videoPath];
    self.uploadCompletionBlock  = completionBlock;
    self.state                  = DDYouTubeUploaderStatePreparingFile;
    NSError *error              = nil;

    // Send file info
    [self sendVideoFileMetadata:videoMetadata error:&error];
    
    if (error)
    {
        self.state = DDYouTubeUploaderStateNotUploading;
        
        [self logError:@"Cannot create connection for sending file info."];
        
        [self loginOrUploadFailedWithError:error];
    }
}

//----------------------------------------------------------------------

- (void)cancelUpload
{
    [self logDebug:@"Cancelling all active operations..."];

    self.uploadCompletionBlock = nil;
    self.progressBlock         = nil;

    // Cancel the current upload operation
    switch (self.state)
    {
        case DDYouTubeUploaderStatePreparingFile:
        case DDYouTubeUploaderStateUploading:
            [self.currentConnection cancel];
            self.currentConnection = nil;
            break;
        default:
            break;
    }
    
    self.state = DDYouTubeUploaderStateNotUploading;
}

//----------------------------------------------------------------------
#pragma mark - YouTube API Calls -
#pragma mark Login
//----------------------------------------------------------------------

- (void)logInToYouTubeWithEmail:(NSString *)userEmail
                    andPassword:(NSString *)userPassword
{
    self.state = DDYouTubeUploaderStateLoggingIn;

    NSURL *logInURL = [NSURL URLWithString:@"https://www.google.com/accounts/ClientLogin"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:logInURL];
    
    // Set the request parameters
    NSString *emailParam    = [NSString stringWithFormat:@"Email=%@", userEmail];
    NSString *passwordParam = [NSString stringWithFormat:@"Passwd=%@", userPassword];
    NSString *serviceParam  = @"service=youtube";
    NSString *sourceParam   = @"source=";
    NSString *continueParam = @"continue=http://www.google.com/";
    
    NSString *parameters = [NSString stringWithFormat:@"%@&%@&%@&%@&%@",
                        emailParam, passwordParam, serviceParam, sourceParam, continueParam];
    
    // Set other request values
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[parameters dataUsingEncoding:NSUTF8StringEncoding]];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-type"];
    [request setTimeoutInterval:20];
    
    self.responseData      = [[NSMutableData alloc] init];
    self.currentConnection = [DDURLConnection connectionWithRequest:request delegate:self];
    [self.currentConnection setType:DDYouTubeUploaderConnectionTypeLogIn];
    
    if (!self.currentConnection)
    {
        NSError *error = [self createErrorWithCode:DDYouTubeUploaderErrorCodeCannotCreateConnection
                                       description:@"Cannot create connection to YouTube."];
        
        // Cannot create connection to YouTube
        [self loginOrUploadFailedWithError:error];
    }
}

//----------------------------------------------------------------------

- (BOOL)processLoginData:(NSData *)data
                   error:(NSError **)error
{
    NSString *replyString   = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    self.authorizationToken = nil;

    if ([replyString rangeOfString:@"Auth="].location != NSNotFound)
    {
        NSArray *tokens = [replyString componentsSeparatedByString:@"\n"];
        
        if ([tokens count] >= 3)
        {
            // Separate the token into array
            NSArray *authToken = [[tokens objectAtIndex:2] componentsSeparatedByString:@"="];
            
            // Get the token if present
            if ([authToken count] >= 2)
                self.authorizationToken = [authToken objectAtIndex:1];
        }
    }
    
    [self logDebug:@"Login finished authentication."];
    
    if (!self.authorizationToken)
    {
        // Delete the credentials, as they are wrong
        [self deleteSavedUserCredentials];
        
        *error = [self createErrorWithCode:DDYouTubeUploaderErrorCodeWrongCredentials
                               description:@"Email or Password is Wrong."];
    }

    return (self.authorizationToken != nil);
}

//----------------------------------------------------------------------

- (void)loginOrUploadFailedWithError:(NSError *)error
{
    self.state = DDYouTubeUploaderStateNotUploading;
    
    if (self.loginCompletionBlock)
        self.loginCompletionBlock(NO, error);
    else if (self.uploadCompletionBlock)
        self.uploadCompletionBlock(NO, nil, error);
}

//----------------------------------------------------------------------
#pragma mark Upload URL & Token
//----------------------------------------------------------------------

- (void)sendVideoFileMetadata:(NSDictionary *)videoMetadata
                        error:(NSError **)error
{
    [self logDebug:@"Sending file info..."];
    
    NSString *category = videoMetadata[kDDYouTubeVideoMetadataCategoryKey];
    NSString *keywords = videoMetadata[kDDYouTubeVideoMetadataKeywordsKey];
    NSString *title    = videoMetadata[kDDYouTubeVideoMetadataTitleKey];
    NSString *desc     = videoMetadata[kDDYouTubeVideoMetadataDescriptionKey];

    NSString *xml = [NSString stringWithFormat:
                     @"<?xml version=\"1.0\"?>"
                     @"<entry xmlns=\"http://www.w3.org/2005/Atom\" xmlns:media=\"http://search.yahoo.com/mrss/\" xmlns:yt=\"http://gdata.youtube.com/schemas/2007\">"
                     @"<media:group>"
                     @"<media:title type=\"plain\">%@</media:title>"
                     @"<media:description type=\"plain\">%@</media:description>"
                     @"<media:category scheme=\"http://gdata.youtube.com/schemas/2007/categories.cat\">%@</media:category>"
                     @"<media:keywords>%@</media:keywords>"
                     @"</media:group>"
                     @"</entry>", title, desc, category, keywords];
    
    NSURL *url = [NSURL URLWithString:@"https://gdata.youtube.com/action/GetUploadToken"];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    
    [request setHTTPMethod:@"POST"];
    [request setValue:[NSString stringWithFormat:@"GoogleLogin auth=\"%@\"", self.authorizationToken] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"2" forHTTPHeaderField:@"GData-Version"];
    [request setValue:[NSString stringWithFormat:@"key=%@", self.developerKey] forHTTPHeaderField:@"X-GData-Key"];
    [request setValue:@"application/atom+xml; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"%u", (unsigned int)xml.length] forHTTPHeaderField:@"Content-Length"];
    [request setHTTPBody:[xml dataUsingEncoding:NSUTF8StringEncoding]];
    
    self.responseData          = [[NSMutableData alloc] init];
    self.currentConnection = [DDURLConnection connectionWithRequest:request delegate:self];
    [self.currentConnection setType:DDYouTubeUploaderConnectionTypePrepare];
    
    // Create error if there were
    // problems creating a connection
    if (!self.currentConnection)
    {
        *error = [self createErrorWithCode:DDYouTubeUploaderErrorCodeCannotCreateConnection
                               description:@"Cannot create connection to YouTube."];
    }
}

//----------------------------------------------------------------------

- (void)parseUploadURLAndTokenFromData:(NSData *)data
{
    if (!data) [self logError:@"UploadURL and UploadToken is not received!"];
    
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    [parser setDelegate:self];
    [parser setShouldProcessNamespaces:NO];
    [parser setShouldReportNamespacePrefixes:NO];
    [parser setShouldResolveExternalEntities:NO];
    [parser parse];
}

//----------------------------------------------------------------------

- (void)uploadUrlAndTokenIsReady
{
    [self logDebug:@"UploadURL and UploadToken received."];
    [self logDebug:@"Uploading..."];

    self.state      = DDYouTubeUploaderStateUploading;
    NSError *error  = nil;
    
    if (![self uploadVideoFile:self.localVideoURL error:&error])
    {
        self.state = DDYouTubeUploaderStateNotUploading;
        [self logError:@"Cannot create connection for file upload."];
    }
}

//----------------------------------------------------------------------

- (void)uploadUrlAndTokenFailed
{
    [self logError:@"UploadURL and UploadToken not received."];
    
    NSError *error = [self createErrorWithCode:DDYouTubeUploaderErrorCodeUploadURLTokenError
                                   description:@"UploadURL and UploadToken not received."];

    [self loginOrUploadFailedWithError:error];
}

//----------------------------------------------------------------------
#pragma mark Upload
//----------------------------------------------------------------------

- (BOOL)uploadVideoFile:(NSURL *)fileURL
                  error:(NSError **)error
{
    NSString *boundary = @"AbyRvAlG";
    NSString *nextURL  = @"http://www.youtube.com";
    
    NSData *fileData = [NSData dataWithContentsOfFile:[fileURL relativePath]];
    _videoFileLength = [fileData length];
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?nexturl=%@", self.uploadURLString, nextURL]];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setHTTPMethod:@"POST"];
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
    
    NSMutableData *body         = [NSMutableData data];
    NSMutableString *bodyString = [NSMutableString new];
    
    // Add token
    [bodyString appendFormat:@"\r\n--%@\r\n", boundary];
    [bodyString appendString:@"Content-Disposition: form-data; name=\"token\"\r\n"];
    [bodyString appendString:@"Content-Type: text/plain\r\n\r\n"];
    [bodyString appendFormat:@"%@", self.uploadToken];
    
    // Add file name
    [bodyString appendFormat:@"\r\n--%@\r\n", boundary];
    [bodyString appendFormat:@"Content-Disposition: form-data; name=\"file\"; filename=\"%@\"\r\n", [fileURL lastPathComponent]];
    [bodyString appendFormat:@"Content-Type: application/octet-stream\r\n\r\n"];
    
    // Create the data
    [body appendData:[bodyString dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[NSData dataWithData:fileData]];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    
    // Set the body
    [request setHTTPBody:body];
    
    // Create the connection
    self.responseData          = [[NSMutableData alloc] init];
    self.currentConnection = [DDURLConnection connectionWithRequest:request delegate:self];
    [self.currentConnection setType:DDYouTubeUploaderConnectionTypeUpload];

    if (!self.currentConnection)
    {
        *error = [self createErrorWithCode:DDYouTubeUploaderErrorCodeCannotCreateConnection
                               description:@"Cannot create connection to YouTube."];
        return NO;
    }
    
    return YES;
}

//----------------------------------------------------------------------

- (void)videoIsUploaded
{
    self.state = DDYouTubeUploaderStateNotUploading;

    if (self.uploadCompletionBlock)
        self.uploadCompletionBlock(YES, self.remoteVideoURL, nil);
}

//----------------------------------------------------------------------
#pragma mark - URL Connection Delegate -
//----------------------------------------------------------------------

// Final event, memory is cleaned up at the end of this.
- (void)connection:(DDURLConnection *)connection didFailWithError:(NSError *)error
{
    [self logError:@"Connection problem - %@", error.localizedDescription];
    
    // Failed
    [self loginOrUploadFailedWithError:error];
    
    self.state = DDYouTubeUploaderStateNotUploading;
    self.currentConnection = nil;
}

//----------------------------------------------------------------------

// Final event, memory is cleaned up at the end of this.
- (void)connectionDidFinishLoading:(DDURLConnection *)connection
{
    [self logDebug:@"A connection did finish."];
    
    switch (connection.type)
    {
        case DDYouTubeUploaderConnectionTypeLogIn:
        {
            self.currentConnection = nil;
            NSError *error         = nil;
            BOOL loggedIn          = [self processLoginData:self.responseData error:&error];
            
            if (loggedIn)
            {
                [self logDebug:@"User is logged in to YouTube."];
                
                self.isLoggedIn = YES;
                
                if (self.loginCompletionBlock)
                    self.loginCompletionBlock(YES, nil);
            }
            else
            {
                // Wrong login or password
                [self logError:@"Login to YouTube failed."];
                [self loginOrUploadFailedWithError:error];
            }
            break;
        }
        case DDYouTubeUploaderConnectionTypePrepare:
        {
            self.currentConnection = nil;
            [self parseUploadURLAndTokenFromData:self.responseData];
            
            break;
        }
        default: break;
    }
}

//----------------------------------------------------------------------

- (NSURLRequest *)connection:(DDURLConnection *)connection
             willSendRequest:(NSURLRequest *)request
            redirectResponse:(NSURLResponse *)redirectResponse
{
    if (connection.type == DDYouTubeUploaderConnectionTypeUpload)
    {
        if (redirectResponse)
        {
            [self logDebug:@"Redirect to %@", request.URL];
            
            NSString* urlString = [request.URL absoluteString];
            NSRange range = [urlString rangeOfString:@"id=" options:NSBackwardsSearch];
            if (range.location != NSNotFound)
            {
                NSString *videoID   = [urlString substringFromIndex:range.location + 3];
                NSString *upString  = [NSString stringWithFormat:@"http://www.youtube.com/watch?v=%@", videoID];
                self.remoteVideoURL = [NSURL URLWithString:upString];
                
                [self logDebug:@"Video did upload to %@", upString];
            }
            else
            {
                self.remoteVideoURL = nil;
                [self logWarning:@"Video is uploaded, but has no URL!"];
            }
            
            self.currentConnection = nil;
            [connection cancel];
            
            // Finish
            [self videoIsUploaded];
            
            return nil;
        }
    }
    
    return request;
}

//----------------------------------------------------------------------

- (void)connection:(DDURLConnection *)connection didReceiveData:(NSData *)data
{
    switch (connection.type)
    {
        case DDYouTubeUploaderConnectionTypeLogIn:
        case DDYouTubeUploaderConnectionTypePrepare:
        {
            // Append the new data to receivedData.
            // receivedData is an instance variable declared elsewhere.
            [self.responseData appendData:data];
            break;
        }
        default: break;
    }
}

//----------------------------------------------------------------------

- (void)connection:(DDURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten
 totalBytesWritten:(NSInteger)totalWritten totalBytesExpectedToWrite:(NSInteger)bExpectedToWrite
{
    if (connection.type == DDYouTubeUploaderConnectionTypeUpload)
    {
        CGFloat progress = ((CGFloat)totalWritten / (CGFloat)_videoFileLength);

        if (self.progressBlock)
            self.progressBlock(progress);
    }
}

//----------------------------------------------------------------------
#pragma mark - NSXMLParser Delegate -
//----------------------------------------------------------------------

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
    attributes:(NSDictionary *)attributeDict
{
    switch (self.state)
    {
        case DDYouTubeUploaderStatePreparingFile:
        {
            if ([elementName isEqualToString:@"url"] ||
                [elementName isEqualToString:@"token"])
            {
                self.currentParserString = [NSMutableString new];
            }
            break;
        }
        default: break;
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    switch (self.state)
    {
        case DDYouTubeUploaderStatePreparingFile:
        {
            if ([elementName isEqualToString:@"url"])
            {
                self.uploadURLString     = self.currentParserString;
                self.currentParserString = nil;
            }
            else if ([elementName isEqualToString:@"token"])
            {
                self.uploadToken         = self.currentParserString;
                self.currentParserString = nil;
            }
            break;
        }
        default: break;
    }
}

//----------------------------------------------------------------------

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    switch (self.state)
    {
        case DDYouTubeUploaderStatePreparingFile:
        {
            if (self.currentParserString)
                [self.currentParserString appendString:string];
            break;
        }
        default: break;
    }
}

//----------------------------------------------------------------------

- (void)parserDidEndDocument:(NSXMLParser *)parser
{
    switch (self.state)
    {
        case DDYouTubeUploaderStatePreparingFile:
        {
            if (self.uploadURLString && self.uploadToken)
                [self uploadUrlAndTokenIsReady];
            else
                [self uploadUrlAndTokenFailed];
            break;
        }
        default: break;
    }
}

//----------------------------------------------------------------------
#pragma mark - Keychain Handling -
//----------------------------------------------------------------------

- (void)saveUserEmail:(NSString *)userEmail
          andPassword:(NSString *)userPassword
{
    // Create the queries
    NSMutableDictionary *passwordQuery  = nil;
    NSMutableDictionary *emailQuery     = [NSMutableDictionary dictionary];
    [emailQuery setObject:(__bridge id)kSecClassGenericPassword
                   forKey:(__bridge id)kSecClass];
    [emailQuery setObject:(__bridge id)kSecAttrAccessibleWhenUnlocked
                   forKey:(__bridge id)kSecAttrAccessible];
    
    // Create the copy
    passwordQuery = [emailQuery mutableCopy];
    
    // Add the keys
    [emailQuery setObject:kDDYouTubeAuthorizationEmailKey forKey:(__bridge id)kSecAttrAccount];
    [passwordQuery setObject:kDDYouTubeAuthorizationPasswordKey forKey:(__bridge id)kSecAttrAccount];
    
    // Try to delete first
    SecItemDelete((__bridge  CFDictionaryRef)emailQuery);
    SecItemDelete((__bridge  CFDictionaryRef)passwordQuery);
    
    // Now add the protected data to the query
    [emailQuery setObject:[userEmail dataUsingEncoding:NSUTF8StringEncoding]
                   forKey:(__bridge id)kSecValueData];
    [passwordQuery setObject:[userPassword dataUsingEncoding:NSUTF8StringEncoding]
                   forKey:(__bridge id)kSecValueData];
    
    // Try to save it
    OSStatus emailError    = SecItemAdd((__bridge CFDictionaryRef)emailQuery, NULL);
    OSStatus passwordError = SecItemAdd((__bridge CFDictionaryRef)passwordQuery, NULL);
    
    // If error, log it
    if (emailError != errSecSuccess || passwordError != errSecSuccess)
    {
        [self logError:@"Error while saving credentials to keychain."];
    }
}

//----------------------------------------------------------------------

- (NSString *)getUserCredentialForKey:(NSString const*)key
{
    // Create the queries
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    [query setObject:(__bridge id)kSecClassGenericPassword
              forKey:(__bridge id)kSecClass];
    [query setObject:(__bridge id)kSecAttrAccessibleWhenUnlocked
              forKey:(__bridge id)kSecAttrAccessible];
    
    // Add the key
    [query setObject:key
              forKey:(__bridge id)kSecAttrAccount];
    
    // Add search attributes
    [query setObject:(__bridge id)kSecMatchLimitOne
              forKey:(__bridge id)kSecMatchLimit];
    
    // Add search return types
    [query setObject:(__bridge id)kCFBooleanTrue
              forKey:(__bridge id)kSecReturnData];
    
    // Get it from the keychain
    CFDataRef resultRef = NULL;
    OSStatus status     = SecItemCopyMatching((__bridge CFDictionaryRef)query,
                                              (CFTypeRef *)&resultRef);
    
    if (status != errSecSuccess)
    {
        [self logWarning:@"Failed to get saved credentials. Maybe no credentials were yet saved."];
        return nil;
    }
    
    NSData *result = (__bridge_transfer NSData *)resultRef;
    NSString *string = [[NSString alloc] initWithData:result encoding:NSUTF8StringEncoding];
    
    return string;
}

//----------------------------------------------------------------------

- (void)deleteSavedUserCredentials
{
    // Create the queries
    NSMutableDictionary *passwordQuery  = nil;
    NSMutableDictionary *emailQuery     = [NSMutableDictionary dictionary];
    [emailQuery setObject:(__bridge id)kSecClassGenericPassword
                   forKey:(__bridge id)kSecClass];
    [emailQuery setObject:(__bridge id)kSecAttrAccessibleWhenUnlocked
                   forKey:(__bridge id)kSecAttrAccessible];
    
    // Create the copy
    passwordQuery = [emailQuery mutableCopy];
    
    // Add the keys
    [emailQuery setObject:kDDYouTubeAuthorizationEmailKey forKey:(__bridge id)kSecAttrAccount];
    [emailQuery setObject:kDDYouTubeAuthorizationPasswordKey forKey:(__bridge id)kSecAttrAccount];
    
    // Try to delete first
    SecItemDelete((__bridge  CFDictionaryRef)emailQuery);
    SecItemDelete((__bridge  CFDictionaryRef)passwordQuery);
}

//----------------------------------------------------------------------
#pragma mark - Errors -
//----------------------------------------------------------------------

- (NSError *)createErrorWithCode:(NSUInteger)errorCode
                     description:(NSString *)errorDescription
{
    NSDictionary *errorInfo = @{NSLocalizedDescriptionKey : errorDescription};
    NSString *errorDomain   = @"com.dynamicdust.YouTubeUploader";
    
    return [NSError errorWithDomain:errorDomain
                               code:errorCode
                           userInfo:errorInfo];
}

//----------------------------------------------------------------------
#pragma mark - Logging -
//----------------------------------------------------------------------

- (void)logError:(NSString *)logMessage, ...
{
    if (self.logLevel >= DDYouTubeUploaderLogLevelError)
    {
        NSString *argString = nil;
        
        va_list args;
        va_start(args, logMessage);
        argString = [[NSString alloc] initWithFormat:logMessage arguments:args];
        va_end(args);
        
        NSLog(@"DDYouTubeUploader: <ERROR> %@", argString);
    }
}

//----------------------------------------------------------------------

- (void)logWarning:(NSString *)logMessage, ...
{
    if (self.logLevel >= DDYouTubeUploaderLogLevelWarning)
    {
        NSString *argString = nil;
        
        va_list args;
        va_start(args, logMessage);
        argString = [[NSString alloc] initWithFormat:logMessage arguments:args];
        va_end(args);
        
        NSLog(@"DDYouTubeUploader: <WARNING> %@", argString);
    }
}

//----------------------------------------------------------------------

- (void)logDebug:(NSString *)logMessage, ...
{
    if (self.logLevel >= DDYouTubeUploaderLogLevelDebug)
    {
        NSString *argString = nil;
        
        va_list args;
        va_start(args, logMessage);
        argString = [[NSString alloc] initWithFormat:logMessage arguments:args];
        va_end(args);
        
        NSLog(@"DDYouTubeUploader: <DEBUG> %@", argString);
    }
}

//----------------------------------------------------------------------
@end
