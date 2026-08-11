#import "PPAdminWebAppViewController.h"
#import <WebKit/WebKit.h>
#import "Styling.h"
#import "Language.h"
#import "UIViewController+PPNavBar.h"

static NSString * const kPPAdminWebAppURLString = @"https://pure-pets-49199.web.app/";

@interface PPAdminWebAppViewController () <WKNavigationDelegate, WKUIDelegate>

@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;
@property (nonatomic, strong) UIView *errorContainer;
@property (nonatomic, strong) UILabel *errorTitleLabel;
@property (nonatomic, strong) UILabel *errorMessageLabel;
@property (nonatomic, strong) UIButton *retryButton;

@end

@implementation PPAdminWebAppViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.title = kLang(@"AdminWebApp_Title");
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = AppBackgroundClr;
    self.view.semanticContentAttribute = [Language semanticAttributeForCurrentLanguage];

    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];

    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    webView.translatesAutoresizingMaskIntoConstraints = NO;
    webView.navigationDelegate = self;
    webView.UIDelegate = self;
    webView.backgroundColor = AppBackgroundClr;
    webView.scrollView.backgroundColor = AppBackgroundClr;
    webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    webView.allowsBackForwardNavigationGestures = YES;
    webView.opaque = NO;
    self.webView = webView;

    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    indicator.translatesAutoresizingMaskIntoConstraints = NO;
    indicator.hidesWhenStopped = YES;
    indicator.color = [UIColor ppPrimary];
    self.loadingIndicator = indicator;

    UIView *errorContainer = [[UIView alloc] initWithFrame:CGRectZero];
    errorContainer.translatesAutoresizingMaskIntoConstraints = NO;
    errorContainer.backgroundColor = [UIColor ppElevatedSurface];
    errorContainer.layer.cornerRadius = 24.0;
    errorContainer.layer.masksToBounds = YES;
    errorContainer.hidden = YES;
    self.errorContainer = errorContainer;

    UILabel *errorTitle = [UILabel new];
    errorTitle.translatesAutoresizingMaskIntoConstraints = NO;
    errorTitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    errorTitle.textColor = [UIColor ppTextPrimary];
    errorTitle.textAlignment = NSTextAlignmentCenter;
    errorTitle.numberOfLines = 0;
    errorTitle.text = kLang(@"AdminWebApp_Error_Title");
    self.errorTitleLabel = errorTitle;

    UILabel *errorMessage = [UILabel new];
    errorMessage.translatesAutoresizingMaskIntoConstraints = NO;
    errorMessage.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    errorMessage.textColor = [UIColor ppTextSecondary];
    errorMessage.textAlignment = NSTextAlignmentCenter;
    errorMessage.numberOfLines = 0;
    errorMessage.text = kLang(@"AdminWebApp_Error_Message");
    self.errorMessageLabel = errorMessage;

    UIButton *retryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    retryButton.translatesAutoresizingMaskIntoConstraints = NO;
    retryButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    [retryButton setTitle:kLang(@"AdminWebApp_Retry") forState:UIControlStateNormal];
    [retryButton addTarget:self action:@selector(didTapRetry) forControlEvents:UIControlEventTouchUpInside];
    self.retryButton = retryButton;

    [errorContainer addSubview:errorTitle];
    [errorContainer addSubview:errorMessage];
    [errorContainer addSubview:retryButton];

    [self.view addSubview:webView];
    [self.view addSubview:indicator];
    [self.view addSubview:errorContainer];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [webView.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [webView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [indicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [indicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [errorContainer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [errorContainer.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [errorContainer.leadingAnchor constraintGreaterThanOrEqualToAnchor:guide.leadingAnchor constant:24.0],
        [errorContainer.trailingAnchor constraintLessThanOrEqualToAnchor:guide.trailingAnchor constant:-24.0],
        [errorContainer.widthAnchor constraintLessThanOrEqualToConstant:420.0],

        [errorTitle.topAnchor constraintEqualToAnchor:errorContainer.topAnchor constant:24.0],
        [errorTitle.leadingAnchor constraintEqualToAnchor:errorContainer.leadingAnchor constant:20.0],
        [errorTitle.trailingAnchor constraintEqualToAnchor:errorContainer.trailingAnchor constant:-20.0],

        [errorMessage.topAnchor constraintEqualToAnchor:errorTitle.bottomAnchor constant:12.0],
        [errorMessage.leadingAnchor constraintEqualToAnchor:errorContainer.leadingAnchor constant:20.0],
        [errorMessage.trailingAnchor constraintEqualToAnchor:errorContainer.trailingAnchor constant:-20.0],

        [retryButton.topAnchor constraintEqualToAnchor:errorMessage.bottomAnchor constant:18.0],
        [retryButton.leadingAnchor constraintEqualToAnchor:errorContainer.leadingAnchor constant:20.0],
        [retryButton.trailingAnchor constraintEqualToAnchor:errorContainer.trailingAnchor constant:-20.0],
        [retryButton.bottomAnchor constraintEqualToAnchor:errorContainer.bottomAnchor constant:-20.0],
    ]];

    [self loadWebApp];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self pp_navBarApplyBase:PPNavBarBaseLayoutAuto button:nil title:kLang(@"AdminWebApp_Title") showBack:YES];

    [self pp_navBarSetRightIcon:@"arrow.clockwise"
                            key:@"admin_web_reload"
                         target:self
                         action:@selector(didTapReload)
                             tap:nil];
    [self pp_navBarSetRightIcon:@"safari"
                            key:@"admin_web_safari"
                         target:self
                         action:@selector(didTapOpenInSafari)
                             tap:nil];
}

- (void)dealloc {
    _webView.navigationDelegate = nil;
    _webView.UIDelegate = nil;
}

- (void)loadWebApp {
    NSURL *url = [NSURL URLWithString:kPPAdminWebAppURLString];
    if (!url) return;

    self.errorContainer.hidden = YES;
    [self.loadingIndicator startAnimating];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url
                                              cachePolicy:NSURLRequestUseProtocolCachePolicy
                                          timeoutInterval:60.0]];
}

- (void)didTapReload {
    if (self.webView.URL != nil) {
        [self hideErrorState];
        [self.loadingIndicator startAnimating];
        [self.webView reload];
        return;
    }
    [self loadWebApp];
}

- (void)didTapRetry {
    [self loadWebApp];
}

- (void)didTapOpenInSafari {
    NSURL *url = self.webView.URL ?: [NSURL URLWithString:kPPAdminWebAppURLString];
    if (!url) return;
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)showErrorState {
    [self.loadingIndicator stopAnimating];
    self.errorContainer.hidden = NO;
}

- (void)hideErrorState {
    self.errorContainer.hidden = YES;
}

- (BOOL)shouldIgnoreNavigationError:(NSError *)error {
    if (![error isKindOfClass:NSError.class]) return NO;
    return error.code == NSURLErrorCancelled;
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    (void)webView;
    (void)navigation;
    [self hideErrorState];
    [self.loadingIndicator startAnimating];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    (void)webView;
    (void)navigation;
    [self.loadingIndicator stopAnimating];
    [self hideErrorState];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)webView;
    (void)navigation;
    if ([self shouldIgnoreNavigationError:error]) return;
    [self showErrorState];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)webView;
    (void)navigation;
    if ([self shouldIgnoreNavigationError:error]) return;
    [self showErrorState];
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    (void)webView;
    [self loadWebApp];
}

- (nullable WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
    (void)webView;
    (void)configuration;
    (void)windowFeatures;

    if (!navigationAction.targetFrame.isMainFrame) {
        [self.webView loadRequest:navigationAction.request];
    }
    return nil;
}

@end
