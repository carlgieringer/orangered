//
//  OrangeredAppDelegate.h
//  Orangered
//
//  Created by Carl Gieringer on 2010-04-30.
//

#import <Cocoa/Cocoa.h>

typedef enum {
	uninitializedPasswordState, // The user hasn't set the account information, so it cannot  be invalid
	unknownPasswordState, // the user has set the account information but it hasn't been tested for validity yet
	incorrectPasswordState, // the account information is invalid
	correctPasswordState, // the account information is valid
	needLogoutState // User has changed login info, so perform a logout next
} State;

@interface OrangeredAppDelegate : NSObject <NSApplicationDelegate> {
    IBOutlet NSWindow *accountWindow;
	IBOutlet NSTextField *usernameTextField;
	IBOutlet NSTextField *passwordTextField;
	IBOutlet NSTextField *label;
	NSString *initialLabelString;
	IBOutlet NSMenu *menu;
	IBOutlet NSMenuItem *statusMenuItem;
	
	NSString *username;
	NSString *password;
	NSStatusItem *orangeredItem;
	NSImage *orangeredImage;
	NSImage *grayImage;
	NSImage *errorImage;
	NSImage *refreshImage;
	NSMutableURLRequest *loginRequest;
	NSMutableURLRequest *mailRequest;
	NSMutableURLRequest *logoutRequest;
	NSMutableData *receivedData;
	NSTimer *updateTimer;
	BOOL connecting;
	State state;
	NSDate *lastUpdated;
	NSString *csrfKey;
}
- (IBAction)requestAccountInfo:(id)sender;
- (IBAction)viewMessages:(id)sender;
- (IBAction)readAccountInfo:(id)sender;
@end
