#import <UIKit/UIKit.h>
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>

@interface DisplayController : UIViewController
@property UITextField *address;
@property UIImageView *picture;
@property UILabel *status;
@property UIButton *button;
@property NSURLSession *network;
@property NSURLSessionDataTask *pending;
@property NSURL *base;
@property NSString *key;
@property BOOL connected;
@property NSUInteger generation;
@end

@implementation DisplayController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Second Display";
    self.view.backgroundColor = UIColor.blackColor;
    self.network = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    self.address = [UITextField new];
    self.address.placeholder = @"Paste the laptop pairing URL";
    self.address.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"pairingURL"];
    self.address.borderStyle = UITextBorderStyleRoundedRect;
    self.address.keyboardType = UIKeyboardTypeURL;
    self.address.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.address.autocorrectionType = UITextAutocorrectionTypeNo;
    self.button = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.button setTitle:@"Connect" forState:UIControlStateNormal];
    [self.button addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    self.status = [UILabel new];
    self.status.text = @"Connect to the same Wi-Fi as your laptop.";
    self.status.textColor = UIColor.whiteColor;
    self.status.numberOfLines = 2;
    self.status.font = [UIFont systemFontOfSize:14];
    self.picture = [UIImageView new];
    self.picture.contentMode = UIViewContentModeScaleAspectFit;
    UIStackView *controls = [[UIStackView alloc] initWithArrangedSubviews:@[self.address,self.button,self.status]];
    controls.axis = UILayoutConstraintAxisVertical;
    controls.spacing = 8;
    for (UIView *v in @[controls,self.picture]) {v.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:v];}
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [controls.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12],
        [controls.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [controls.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
        [self.picture.topAnchor constraintEqualToAnchor:controls.bottomAnchor constant:8],
        [self.picture.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [self.picture.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [self.picture.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor]
    ]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(disconnect) name:UIApplicationDidEnterBackgroundNotification object:nil];
}
- (NSURL *)endpoint:(NSString *)path {
    NSURLComponents *u = [NSURLComponents componentsWithURL:self.base resolvingAgainstBaseURL:NO];
    u.path=path;u.queryItems=@[[NSURLQueryItem queryItemWithName:@"key" value:self.key]];
    return u.URL;
}
- (void)toggle {
    if(self.connected){[self disconnect];return;}
    NSURLComponents *u = [NSURLComponents componentsWithString:self.address.text];
    NSString *key=nil;
    for(NSURLQueryItem *q in u.queryItems) if([q.name isEqualToString:@"key"]) key=q.value;
    if(![u.scheme isEqualToString:@"http"] || !u.host.length || !key.length){self.status.text=@"Paste the complete pairing link shown on the laptop.";return;}
    self.base=u.URL;self.key=key;
    [self.address resignFirstResponder];
    [[NSUserDefaults standardUserDefaults] setObject:self.address.text forKey:@"pairingURL"];
    self.connected=YES;NSUInteger generation=++self.generation;
    [self.button setTitle:@"Disconnect" forState:UIControlStateNormal];
    self.status.text=@"Creating the laptop’s extra monitor…";
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[self endpoint:@"/display/start"]];
    request.HTTPMethod=@"POST";
    self.pending=[self.network dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            if(!self.connected || generation!=self.generation)return;
            if(error || ((NSHTTPURLResponse *)response).statusCode!=200){[self disconnect];self.status.text=@"Could not connect. Check the pairing link and Wi-Fi.";return;}
            UIApplication.sharedApplication.idleTimerDisabled=YES;
            [self nextFrame:generation];
        });
    }];[self.pending resume];
}
- (void)nextFrame:(NSUInteger)generation {
    if(!self.connected || generation!=self.generation)return;
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[self endpoint:@"/display/frame.jpg"] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10];
    self.pending=[self.network dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        UIImage *image=(!error && ((NSHTTPURLResponse *)response).statusCode==200)?[UIImage imageWithData:data]:nil;
        dispatch_async(dispatch_get_main_queue(),^{
            if(!self.connected || generation!=self.generation)return;
            if(image){self.picture.image=image;self.status.text=@"Extended desktop — move a window to the right of the laptop screen.";}
            else self.status.text=@"Waiting for the laptop display…";
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)((image?0.08:1.0)*NSEC_PER_SEC)),dispatch_get_main_queue(),^{[self nextFrame:generation];});
        });
    }];[self.pending resume];
}
- (void)disconnect {
    if(!self.connected)return;
    self.connected=NO;++self.generation;
    [self.pending cancel];
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[self endpoint:@"/display/stop"]];
    request.HTTPMethod=@"POST";[[self.network dataTaskWithRequest:request] resume];
    UIApplication.sharedApplication.idleTimerDisabled=NO;
    self.picture.image=nil;self.status.text=@"Disconnected.";
    [self.button setTitle:@"Connect" forState:UIControlStateNormal];
}
- (void)viewWillDisappear:(BOOL)animated {[super viewWillDisappear:animated];[self disconnect];}
@end

@interface MoviesController : UITableViewController <UIDocumentPickerDelegate>
@property NSArray<NSURL *> *movies;
- (void)importOpenedMovieAtURL:(NSURL *)url;
@end

@interface OfflinePlayerController : AVPlayerViewController
@end

@implementation OfflinePlayerController
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    UIApplication.sharedApplication.idleTimerDisabled=YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    UIApplication.sharedApplication.idleTimerDisabled=NO;
}
@end

@implementation MoviesController
- (NSURL *)documents {return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];}
- (NSArray<NSString *> *)movieExtensions {return @[@"mp4",@"m4v",@"mov"];}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"Offline Movies";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(importMovie)];
}
- (void)viewWillAppear:(BOOL)animated {[super viewWillAppear:animated];[self reloadMovies];}
- (void)reloadMovies {
    NSArray *files=[[NSFileManager defaultManager] contentsOfDirectoryAtURL:[self documents] includingPropertiesForKeys:@[NSURLFileSizeKey,NSURLIsRegularFileKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    NSPredicate *moviePredicate=[NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *bindings){
        return [[self movieExtensions] containsObject:url.pathExtension.lowercaseString];
    }];
    self.movies=[[files filteredArrayUsingPredicate:moviePredicate]
        sortedArrayUsingComparator:^NSComparisonResult(NSURL *a,NSURL *b){
            return [a.lastPathComponent localizedCaseInsensitiveCompare:b.lastPathComponent];
        }];
    [self.tableView reloadData];
    UILabel *empty=[UILabel new];empty.numberOfLines=0;empty.textAlignment=NSTextAlignmentCenter;
    empty.text=@"No movies saved in JuanPad yet.\nTap + to import from Files, or use Open in JuanPad.\nSaved movies play in airplane mode.";
    self.tableView.backgroundView=self.movies.count?nil:empty;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {return self.movies.count;}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"movie"];
    if(!cell)cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"movie"];
    cell.textLabel.text=self.movies[indexPath.row].lastPathComponent;
    NSError *error=nil;
    NSDictionary *attributes=[self.movies[indexPath.row] resourceValuesForKeys:@[NSURLFileSizeKey] error:&error];
    unsigned long long bytes=[attributes[NSURLFileSizeKey] unsignedLongLongValue];
    NSString *size=error?@"Unknown size":[NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile];
    cell.detailTextLabel.text=[NSString stringWithFormat:@"Saved on iPad · %@ · Airplane-ready",size];
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    OfflinePlayerController *player=[OfflinePlayerController new];
    player.player=[AVPlayer playerWithURL:self.movies[indexPath.row]];
    player.showsPlaybackControls=YES;
    [self presentViewController:player animated:YES completion:^{[player.player play];}];
}
- (void)importMovie {
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.movie"] inMode:UIDocumentPickerModeImport];
    picker.delegate=self;[self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    for(NSURL *url in urls){
        [self importOpenedMovieAtURL:url];
    }
    [self reloadMovies];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {return YES;}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if(editingStyle!=UITableViewCellEditingStyleDelete)return;
    [NSFileManager.defaultManager removeItemAtURL:self.movies[indexPath.row] error:nil];
    [self reloadMovies];
}

- (NSURL *)uniqueTargetForURL:(NSURL *)url {
    NSURL *target=[[self documents] URLByAppendingPathComponent:url.lastPathComponent];
    NSString *base=[url.lastPathComponent stringByDeletingPathExtension];
    NSString *extension=url.pathExtension;
    NSUInteger copy=2;
    while([NSFileManager.defaultManager fileExistsAtPath:target.path]){
        NSString *name=[NSString stringWithFormat:@"%@ %lu.%@",base,(unsigned long)copy++,extension];
        target=[[self documents] URLByAppendingPathComponent:name];
    }
    return target;
}

- (void)importOpenedMovieAtURL:(NSURL *)url {
    if(!url.fileURL || ![[self movieExtensions] containsObject:url.pathExtension.lowercaseString])
        return;
    BOOL scoped=[url startAccessingSecurityScopedResource];
    NSError *error=nil;
    NSURL *target=[self uniqueTargetForURL:url];
    if(![NSFileManager.defaultManager copyItemAtURL:url toURL:target error:&error]){
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Could not save movie" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
    if(scoped)[url stopAccessingSecurityScopedResource];
    [self reloadMovies];
}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property UIWindow *window;
@property DisplayController *display;
@property MoviesController *movies;
@property UITabBarController *tabs;
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    self.display=[DisplayController new];
    self.movies=[MoviesController new];
    UINavigationController *d=[[UINavigationController alloc] initWithRootViewController:self.display];
    UINavigationController *m=[[UINavigationController alloc] initWithRootViewController:self.movies];
    d.tabBarItem=[[UITabBarItem alloc] initWithTitle:@"Second Display" image:nil tag:0];
    m.tabBarItem=[[UITabBarItem alloc] initWithTitle:@"Movies" image:nil tag:1];
    self.tabs=[UITabBarController new];self.tabs.viewControllers=@[d,m];
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController=self.tabs;[self.window makeKeyAndVisible];return YES;
}
- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary *)options {
    if(url.fileURL){
        [self.movies loadViewIfNeeded];
        self.tabs.selectedIndex=1;
        [self.movies importOpenedMovieAtURL:url];
        return YES;
    }
    if(![url.scheme isEqualToString:@"juanpad"] || !url.host.length)return NO;
    NSURLComponents *u=[NSURLComponents new];u.scheme=@"http";u.host=url.host;u.port=url.port;
    u.path=@"/";u.queryItems=@[[NSURLQueryItem queryItemWithName:@"key" value:url.lastPathComponent]];
    [self.display loadViewIfNeeded];self.tabs.selectedIndex=0;self.display.address.text=u.URL.absoluteString;
    return YES;
}
@end
int main(int argc,char *argv[]){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(AppDelegate.class));}}
