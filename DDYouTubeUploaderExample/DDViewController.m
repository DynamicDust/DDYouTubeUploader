//
//  DDViewController.m
//  DDYouTubeUploaderExample
//
//  Created by Dominik Hádl on 07/07/14.
//  Copyright (c) 2014 DynamicDust s.r.o. All rights reserved.
//

#import "DDViewController.h"
#import "DDYouTubeUploader.h"

@interface DDViewController ()

@property (nonatomic, weak) UITextField *keyField;
@property (nonatomic, weak) UITextField *emailField;
@property (nonatomic, weak) UITextField *passwordField;
@property (nonatomic, weak) UILabel *progressLabel;

@property (nonatomic, strong) DDYouTubeUploader *uploader;

@end

@implementation DDViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    [self.view setBackgroundColor:[UIColor whiteColor]];
    
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    CGPoint center    = CGPointMake(screenSize.width/2, screenSize.height/2);
    
    UITextField *keyField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 250, 35)];
    [keyField setCenter:CGPointMake(center.x, center.y - 150)];
    [keyField setPlaceholder:@"Developer Key"];
    [keyField setBorderStyle:UITextBorderStyleRoundedRect];
    [keyField setAutocapitalizationType:UITextAutocapitalizationTypeNone];
    [keyField setAutocorrectionType:UITextAutocorrectionTypeNo];
    
    UITextField *emailField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 250, 35)];
    [emailField setCenter:CGPointMake(center.x, center.y - 100)];
    [emailField setPlaceholder:@"Email"];
    [emailField setBorderStyle:UITextBorderStyleRoundedRect];
    [emailField setAutocapitalizationType:UITextAutocapitalizationTypeNone];
    [emailField setAutocorrectionType:UITextAutocorrectionTypeNo];
    
    UITextField *passwordField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 250, 35)];
    [passwordField setCenter:CGPointMake(center.x, center.y - 50)];
    [passwordField setPlaceholder:@"Password"];
    [passwordField setSecureTextEntry:YES];
    [passwordField setBorderStyle:UITextBorderStyleRoundedRect];
    [passwordField setAutocorrectionType:UITextAutocorrectionTypeNo];
    
    UIButton *uploadButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [uploadButton setTitle:@"Test Upload" forState:UIControlStateNormal];
    [uploadButton setFrame:CGRectMake(0, 0, 200, 35)];
    [uploadButton setCenter:center];
    [uploadButton addTarget:self
                     action:@selector(uploadPressed:)
           forControlEvents:UIControlEventTouchUpInside];
    
    UILabel *progressLabel = [[UILabel alloc] initWithFrame:uploadButton.frame];
    [progressLabel setText:@"Logging in..."];
    [progressLabel setTextAlignment:NSTextAlignmentCenter];
    [progressLabel setAlpha:0];
    [progressLabel setTextColor:[UIColor blackColor]];
    
    [self.view addSubview:uploadButton];
    [self.view addSubview:keyField];
    [self.view addSubview:emailField];
    [self.view addSubview:passwordField];
    [self.view addSubview:progressLabel];
    
    self.emailField     = emailField;
    self.passwordField  = passwordField;
    self.keyField       = keyField;
    self.progressLabel  = progressLabel;
}

- (void)uploadPressed:(UIButton *)sender
{    
    [self.keyField resignFirstResponder];
    [self.passwordField resignFirstResponder];
    [self.emailField resignFirstResponder];
    
    [UIView animateWithDuration:0.5 animations:^{
        self.keyField.alpha = 0;
        self.passwordField.alpha = 0;
        self.emailField.alpha = 0;
        sender.alpha = 0;
        self.progressLabel.alpha = 1;
    }];
    
    __weak DDViewController *weakSelf = self;
    
    // Start the uploader
    self.uploader = [DDYouTubeUploader uploaderWithDeveloperKey:self.keyField.text];
    [self.uploader setLogLevel:DDYouTubeUploaderLogLevelDebug];
    
    // Login
    [self.uploader loginWithEmail:self.emailField.text
                 andPassword:self.passwordField.text
              withCompletion:^(BOOL success, NSError *error)
     {
        if (success && !error)
        {
            [weakSelf.progressLabel setText:@"Login success."];
            [weakSelf uploadVideo];
        }
     }];
    
    
}

- (void)uploadVideo
{
    __weak DDViewController *weakSelf = self;
    
    // Set the progress block
    [self.uploader setProgressBlock:^(CGFloat progress)
     {
         [weakSelf.progressLabel setText:[NSString stringWithFormat:@"Progress: %.02f", progress]];
     }];
    
    // Upload now
    [self.uploader uploadVideoAtPath:[[NSBundle mainBundle] pathForResource:@"sample" ofType:@"mov"]
                   withMetadata:@{kDDYouTubeVideoMetadataTitleKey:@"title",
                                  kDDYouTubeVideoMetadataDescriptionKey:@"description",
                                  kDDYouTubeVideoMetadataKeywordsKey:@"key,word",
                                  kDDYouTubeVideoMetadataCategoryKey:@"Entertainment"}
                 withCompletion:^(BOOL success, NSError *error)
     {
         if (success && !error)
         {
             [weakSelf.progressLabel setText:@"Upload success."];
         }
     }];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
