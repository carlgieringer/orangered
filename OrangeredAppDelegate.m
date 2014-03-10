//
//  OrangeredAppDelegate.m
//  Orangered
//
//  Created by Carl Gieringer on 2010-04-30.
//

#import "OrangeredAppDelegate.h"

static NSString *MAIL_URL = @"http://www.reddit.com/";
static NSString *LOGIN_URL = @"http://www.reddit.com/post/login";
static NSString *LOGOUT_URL = @"http://www.reddit.com/logout";
static NSString *LOGIN_POST_DATA_FORMAT = @"user=%@&passwd=%@";
static NSString *LOGOUT_POST_DATA_FORMAT = @"uh=%@&top=off";
static NSTimeInterval UPDATE_INTERVAL = 8.0;
static NSTimeInterval TIMEOUT_INTERVAL = 30.0;
static NSString *NOT_LOGGED_IN_STATUS_FORMAT = @"Not logged in";
static NSString *LOGGED_IN_STATUS_FORMAT = @"You are logged in as %@";
static NSString *LOGGING_IN_STATUS_FORMAT = @"Logging in as %@";
static NSString *INVALID_PASSWORD_STATUS_FORMAT = @"Invalid password for %@";
static NSString *INBOX_URL = @"http://www.reddit.com/message/inbox/";


@interface OrangeredAppDelegate (Private)
- (void)initializeRequests;
- (void)initializeImages;
- (void)activateStatusMenu;
- (void)activateTimer;
- (NSString *)urlEncodeValue:(NSString *)str;
- (void)logout;
- (void)updateLogoutRequest;
- (void)updateCsrfKey:(NSString*)response;
@end


@implementation OrangeredAppDelegate

- (id)init
{
	self = [super init];
	
	connecting = NO;
	state = uninitializedPasswordState;
	
	return self;
}

- (IBAction)viewMessages:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:INBOX_URL]];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	
	initialLabelString = [label stringValue];
	[statusMenuItem setTitle:NOT_LOGGED_IN_STATUS_FORMAT];
	
	NSLog(@"Application did finish launching.  Initializing...");
	[self initializeImages];
	NSLog(@"Initialized Images.");
	[self initializeRequests];
	NSLog(@"Initialized Requests.");
	[self activateStatusMenu];
	NSLog(@"Initialized Status Menu.");
	[self activateTimer];
	NSLog(@"Initialized Active Timer.");
	[self requestAccountInfo:nil];
}

- (void)initializeRequests
{
	NSURL *loginUrl = [NSURL URLWithString:LOGIN_URL];
	loginRequest = [[NSMutableURLRequest alloc] initWithURL:loginUrl
												cachePolicy:NSURLRequestUseProtocolCachePolicy
											timeoutInterval:TIMEOUT_INTERVAL];
	[loginRequest setHTTPMethod:@"POST"];
	
	NSURL *logoutUrl = [NSURL URLWithString:LOGOUT_URL];
	logoutRequest = [[NSMutableURLRequest alloc] initWithURL:logoutUrl
												cachePolicy:NSURLRequestUseProtocolCachePolicy
											timeoutInterval:TIMEOUT_INTERVAL];
	[logoutRequest setHTTPMethod:@"POST"];
	
	
	NSURL *mailUrl = [NSURL URLWithString:MAIL_URL];
	mailRequest = [[NSMutableURLRequest alloc] initWithURL:mailUrl 
											   cachePolicy:NSURLRequestUseProtocolCachePolicy
										   timeoutInterval:TIMEOUT_INTERVAL];
}

- (IBAction)requestAccountInfo:(id)sender
{
	[accountWindow makeKeyAndOrderFront:self]; //TODO: is self the correct sender to 
	[[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
}
- (IBAction)readAccountInfo:(id)sender
{
	[accountWindow close];
	[label setTextColor:[NSColor blackColor]];
	[label setStringValue:initialLabelString];
	
	[orangeredItem setImage:refreshImage];
	
	if (username) {
		//if we already had a username, we need to logout
		state = needLogoutState;
	} else {
		state = unknownPasswordState;
	}
	
	username = [usernameTextField stringValue];
	password = [passwordTextField stringValue];
	
	[passwordTextField setStringValue:@""]; // Get rid of the password from the UI
	
	[statusMenuItem setTitle:[NSString stringWithFormat:LOGGING_IN_STATUS_FORMAT, username]];
	
	NSString *loginPostString =[NSString stringWithFormat:LOGIN_POST_DATA_FORMAT,
								[self urlEncodeValue:username],
								[self urlEncodeValue:password]];
	
	NSData *loginData = [loginPostString dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
	NSString *loginDataLength = [NSString stringWithFormat:@"%d", [loginData length]];
	
	[loginRequest setValue:loginDataLength forHTTPHeaderField:@"Content-Length"];
	[loginRequest setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
	[loginRequest setHTTPBody:loginData];
}

- (void)initializeImages
{
	NSString* orangeredPath = [[NSBundle mainBundle] pathForResource:@"envelope-orangered" ofType:@"png"];
	orangeredImage = [[NSImage alloc] initWithContentsOfFile:orangeredPath];
	
	NSString* grayPath = [[NSBundle mainBundle] pathForResource:@"envelope-gray" ofType:@"png"];
	grayImage = [[NSImage alloc] initWithContentsOfFile:grayPath];
	
	NSString* errorPath = [[NSBundle mainBundle] pathForResource:@"envelope-error" ofType:@"png"];
	errorImage = [[NSImage alloc] initWithContentsOfFile:errorPath];
	
	NSString* refreshPath = [[NSBundle mainBundle] pathForResource:@"envelope-refresh" ofType:@"png"];
	refreshImage = [[NSImage alloc] initWithContentsOfFile:refreshPath];
}

- (void)activateStatusMenu
{
    NSStatusBar *bar = [NSStatusBar systemStatusBar];
    orangeredItem = [[bar statusItemWithLength:NSVariableStatusItemLength] retain];
	[orangeredItem setImage:refreshImage];
    //[orangeredItem setTitle: NSLocalizedString(@"Orangered",@"")];
    [orangeredItem setHighlightMode:YES];
    [orangeredItem setMenu:menu];
}

- (void)activateTimer
{
	updateTimer = [[NSTimer scheduledTimerWithTimeInterval:UPDATE_INTERVAL
												 target:self
											   selector:@selector(timerFired:)
											   userInfo:nil
												repeats:YES] retain];
}

- (void)timerFired:(NSTimer*)timer
{
	NSLog(@"Timer fired.");
	
	if (state == uninitializedPasswordState) {
		// TODO: should invalidate timer and have UI for user to enter password.
		NSLog(@"Account information not set.");
		return;
	}
	
	if (state == incorrectPasswordState) {
		// TODO: should invalidate timer and have UI for user to enter password.
		[label setTextColor:[NSColor redColor]];
		[label setStringValue:@"Invalid account information"];
		[accountWindow makeKeyAndOrderFront:self];
		NSLog(@"Still incorrect password.");
		return;
	}
	
	NSDate *now = [NSDate date];
	if (connecting) {
		NSLog(@"Already connecting.");
		return;
	} else if (lastUpdated && ([lastUpdated dateByAddingTimeInterval:UPDATE_INTERVAL] > now)) {
		NSLog(@"Updating too fast; skipping.");
		return;
	}
	
	NSURLRequest *request;
	if (state == correctPasswordState) {
		request = mailRequest;
	} else if (state == needLogoutState) {
		[self updateLogoutRequest];
		request = logoutRequest;
	}
	else {
		request = loginRequest;
	}
	
	NSLog(@"Connecting to %@", [[request URL] absoluteString]);
	connecting = YES;
	lastUpdated = [now retain];
	
	NSURLConnection *connection = [[NSURLConnection alloc]
								   initWithRequest:request
								   delegate:self];
	if (connection) {
		// Create the NSMutableData to hold the received data.
		// receivedData is an instance variable declared elsewhere.
		receivedData = [[NSMutableData data] retain];
	} else {
		NSLog(@"Connection failed");
		[orangeredItem setImage:errorImage];
		[statusMenuItem setTitle:@"Connection failed"];
	}
}

- (void)updateLogoutRequest
{	
	NSString *logoutPostDataString =[NSString stringWithFormat:LOGOUT_POST_DATA_FORMAT, csrfKey];
	
	NSData *logoutData = [logoutPostDataString dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
	NSString *logoutDataLength = [NSString stringWithFormat:@"%d", [logoutData length]];
	
	[logoutRequest setValue:logoutDataLength forHTTPHeaderField:@"Content-Length"];
	[logoutRequest setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
	[logoutRequest setHTTPBody:logoutData];
}

/* Utility Function */
- (NSString *)urlEncodeValue:(NSString *)str
{
	NSString *result = (NSString *) CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault, 
																			(CFStringRef)str, 
																			NULL, 
																			CFSTR("?=&+"), 
																			kCFStringEncodingUTF8);
	return [result autorelease];
}

/* NSConnection delegate methods */
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    [receivedData setLength:0];
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [receivedData appendData:data];
	
}
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
//	if (state == needLogoutState) {
//		// Sending a POST request to reddit.com/logout failed with the error "too many redirects", but it accomplished the logout so that's okay.
//		NSLog(@"Logged out");
//		state = unknownPasswordState;
//	} else {
	
		NSLog(@"Connection failed! Error - %@ %@",
			  [error localizedDescription],
			  [[error userInfo] objectForKey:NSURLErrorFailingURLStringErrorKey]);
		
		[statusMenuItem setTitle:[error localizedDescription]];
		
		[orangeredItem setImage:errorImage];
//	}
	
    [connection release];
    [receivedData release];
	
	connecting = NO;
	
}
- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	NSLog(@"Connection did finish loading.  Received %d bytes of data", [receivedData length]);
	
	[statusMenuItem setTitle:[NSString stringWithFormat:LOGGED_IN_STATUS_FORMAT, username]];
	
	// HTML when no mail:
	//<a class="nohavemail" title="no new mail" href="http://www.reddit.com/message/inbox/" alt="no new mail" id="mail" ><img src="/static/mailgray.png" alt="messages"/></a>
	// HTML when mail:
	//<a class="havemail" title="new mail!" href="http://www.reddit.com/message/inbox/" alt="new mail!" id="mail" ><img src="/static/mail.png" alt="messages"/></a>
	
//	NSString *mailFindString = @"class=\"havemail\"";
//	NSString *noMailFindString = @"class=\"nohavemail\"";
	NSString *mailFindString = @"/static/mail.png";
	NSString *noMailFindString = @"/static/mailgray.png";
	
	NSString *response = [NSString stringWithUTF8String:[receivedData bytes]];
	// NSLog(response);
	NSRange noMailFindRange = [response rangeOfString:noMailFindString];
	if (noMailFindRange.location != NSNotFound) {
		
		NSLog(@"%@", [response substringWithRange:NSMakeRange(noMailFindRange.location - 200, 400)]);
		
		NSLog(@"No mail.");
		if (![[orangeredItem image] isEqual:grayImage]) {
			[orangeredItem setImage:grayImage];
		}
		
		if (state != correctPasswordState) {
			state = correctPasswordState;
		}
		
	} else {
		
		NSRange mailFindRange = [response rangeOfString:mailFindString];
		
		if (mailFindRange.location != NSNotFound) {
			
			NSLog(@"%@", [response substringWithRange:NSMakeRange(mailFindRange.location - 200, 400)]);
			
			NSLog(@"New mail!");
			if (![[orangeredItem image] isEqual:orangeredImage]) {
				[orangeredItem setImage:orangeredImage];
			}
			
			if (state != correctPasswordState) {
				state = correctPasswordState;
			}
			
		} else {
			
			if (state == needLogoutState) {
				// if this was a logout request, it's okay not to have found mail html
				NSLog(@"Logged out");
				state = unknownPasswordState;
			} else {
				NSLog(@"Incorrect password.");
				if (![[orangeredItem image] isEqual:errorImage]) {
					[statusMenuItem setTitle:[NSString stringWithFormat:INVALID_PASSWORD_STATUS_FORMAT, username]];
					[orangeredItem setImage:errorImage];
				}
				
				if (state != incorrectPasswordState) {
					state = incorrectPasswordState;
				}
			}
		}
	}
	
	[self updateCsrfKey:response];
	
    [connection release];
    [receivedData release];
	
	connecting = NO;
}

- (void)updateCsrfKey:(NSString*)response
{
	// find the input with the correct name "uh"
	NSRange namePropertyRange = [response rangeOfString:@"name=\"uh\""];
	
	NSLog(@"%@", [response substringWithRange:NSMakeRange(namePropertyRange.location - 80, 160)]);
	
	int namePropertyEnd = namePropertyRange.location + namePropertyRange.length;
	//find the value within the input
	NSRange valuePropertyRange;
	//first try after the name property
	valuePropertyRange = [response rangeOfString:@"value=\"" 
										 options:0
										   range:NSMakeRange(namePropertyEnd, [response length] - namePropertyEnd)];
	if (valuePropertyRange.location == NSNotFound) {
		//if that didn't work try searching before it
		valuePropertyRange = [response rangeOfString:@"value=\"" 
											 options:(NSBackwardsSearch)  // search backwards
											   range:NSMakeRange(0, namePropertyRange.location)]; // from the start of the nameRange
	}
	
	NSRange tagEndRange = [response rangeOfString:@">" 
										  options:0
											range:NSMakeRange(namePropertyEnd, [response length] - namePropertyEnd)];
	
	int valueStart = valuePropertyRange.location + valuePropertyRange.length;
	NSRange endValueRange = [response rangeOfString:@"\"" 
											options:0 
											  range:NSMakeRange(valueStart, tagEndRange.location - valueStart )];
	csrfKey = [response substringWithRange:NSMakeRange(valueStart, endValueRange.location - valueStart)];
	NSLog(@"CSRF Key: %@", csrfKey);
}

@end
