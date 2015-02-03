//
//  DDYouTubeUploader.h
//  DDYouTubeUploader
//
//  Created by Dominik Hadl on 7/2/14.
//  Copyright (c) 2013 DynamicDust s.r.o. All rights reserved.
//
//----------------------------------------------------------------------
#import <Foundation/Foundation.h>
//----------------------------------------------------------------------

typedef NS_ENUM (NSInteger, DDYouTubeUploaderErrorCode)
{
    DDYouTubeUploaderErrorCodeCannotCreateConnection = 10,
    DDYouTubeUploaderErrorCodeWrongCredentials       = 20,
    DDYouTubeUploaderErrorCodeUploadURLTokenError    = 30
};


typedef NS_ENUM(NSInteger, DDYouTubeUploaderState)
{
    DDYouTubeUploaderStateNotUploading,
    DDYouTubeUploaderStateLoggingIn,
    DDYouTubeUploaderStatePreparingFile,
    DDYouTubeUploaderStateUploading
};

typedef NS_ENUM(NSInteger, DDYouTubeUploaderLogLevel)
{
    DDYouTubeUploaderLogLevelNothing = 0,
    DDYouTubeUploaderLogLevelError   = 1,
    DDYouTubeUploaderLogLevelWarning = 2,
    DDYouTubeUploaderLogLevelDebug   = 3
};

/**
 *  Video metadata keys
 */
extern NSString *const kDDYouTubeVideoMetadataTitleKey;
extern NSString *const kDDYouTubeVideoMetadataDescriptionKey;
extern NSString *const kDDYouTubeVideoMetadataKeywordsKey;
extern NSString *const kDDYouTubeVideoMetadataCategoryKey;

// Completion blocks typedefs
typedef void (^loginCompletionBlock)(BOOL success, NSError *error);
typedef void (^uploadCompletionBlock)(BOOL success, NSURL *videoURL, NSError *error);

//----------------------------------------------------------------------
#pragma mark - Interface -
//----------------------------------------------------------------------

@interface DDYouTubeUploader : NSObject

//----------------------------------------------------------------------
#pragma mark Properties
//----------------------------------------------------------------------

/**
 *  This property has to be set before starting any upload.
 *  Find it at http://code.google.com/apis/youtube/dashboard/gwt/index.html
 */
@property (nonatomic, copy) NSString *developerKey;

/**
 *  This enables saving of user credentials in the keychain,
 *  which is useful, so that the user has to enter them once.
 *  By default, this is set to YES.
 */
@property (nonatomic, assign) BOOL isCredentialsSavingEnabled;

/**
 *  This block is called frequently when uploading the video,
 *  thus can be used to update the user interface and inform
 *  the user about the progress.
 */
@property (nonatomic, copy) void(^progressBlock)(CGFloat);

/**
 *  The curent state of the uploader.
 *  See DDYouTubeUploaderState for possible values.
 */
@property (nonatomic, assign, readonly) DDYouTubeUploaderState state;

/**
 *  This affects which log messages will be printed.
 *  Default value is DDYouTubeUploaderLogLevelError.
 */
@property (nonatomic, assign) DDYouTubeUploaderLogLevel logLevel;

//----------------------------------------------------------------------
#pragma mark Methods
//----------------------------------------------------------------------

+ (instancetype)uploaderWithDeveloperKey:(NSString *)developerKey;
- (instancetype)initWithDeveloperKey:(NSString *)developerKey;

/**
 *  Uses the credentials provided as parameters to log into YouTube and
 *  get the required auth key to be able to upload. This has to be called
 *  before uploading any video, otherwise the upload will fail.
 *
 *  @param userEmail    Email address of the user who wants to upload the video.
 *  @param userPassword Corresponding password for the email address specified in the userEmail parameter.
 */
- (void)loginWithEmail:(NSString *)userEmail
           andPassword:(NSString *)userPassword
        withCompletion:(loginCompletionBlock)completionBlock;

/**
 *  This is the main method of this class which triggers the upload.
 *
 *  @param videoPath     Path to the video which should be uploaded.
 *  @param videoMetadata A dictionary containing video metadata as string values for constant keys.
 */
- (void)uploadVideoAtPath:(NSString *)videoPath
             withMetadata:(NSDictionary *)videoMetadata
           withCompletion:(uploadCompletionBlock)completionBlock;

/**
 *  This method cancels all currently active operations,
 *  if any, otherwise does nothing.
 */
- (void)cancelUpload;

/**
 *  Deletes the user credentials from the keychain, where they
 *  were stored to be used in automatic log in.
 */
- (void)deleteSavedUserCredentials;

@end
