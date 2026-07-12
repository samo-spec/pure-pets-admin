

// PPBannerViewModel.h


NS_ASSUME_NONNULL_BEGIN

/// Defines the action to perform when a banner is tapped.
typedef NS_ENUM(NSInteger, PPBannerOnTapAction) {
    PPBannerOnTapViewAccessory = 0,  // default: e.g., view a specific accessory in app
    PPBannerOnTapViewAd,            // view an ad or detailed banner page
    PPBannerOnTapOpenUrl,           // open a web URL
    PPBannerOnTapCallPhoneNumber,   // initiate a phone call
    PPBannerOnTapWhatsApp           // open WhatsApp with a given number/chat
};


typedef NS_ENUM(NSInteger, PPBannerTextStyle) {
    PPBannerTextStyleBlack = 1,  // default: e.g., view a specific accessory in app
    PPBannerTextStyleWhite = 2      // open WhatsApp with a given number/chat
};

@interface PPBannerViewModel : NSObject


@property (nonatomic, copy, nullable) NSURL *backgroundImageURL;
@property (nonatomic, copy, nullable) NSURL *sampleImageURL;
@property (nonatomic, copy, nullable) NSURL *badgeImageURL;

@property (nonatomic, copy) NSString *titleTextEn;
@property (nonatomic, copy) NSString *titleTextAr;
@property (nonatomic, copy) NSString *descTextEn;
@property (nonatomic, copy) NSString *descTextAr;
@property (nonatomic, copy) NSString *postDateText;

@property (nonatomic, strong, nullable) NSDate *postDate;
@property (nonatomic, assign) PPBannerOnTapAction onTapAction;
@property (nonatomic, assign) PPBannerTextStyle pannerTextStyle;
@property (nonatomic, copy, nullable) NSString *onTapValue;
@property (nonatomic, assign) NSUInteger tapCount;
@property (nonatomic, strong, nullable) NSDate *expirationDate;
@property (nonatomic, strong, nullable) NSDateComponents *validityDuration;
@property (nonatomic, copy) NSString *bannerID;

// Designated initializer
- (instancetype)initWithTitleEn:(NSString *)titleEn
                        titleAr:(NSString *)titleAr
                     descTextEn:(NSString *)descEn
                     descTextAr:(NSString *)descAr
                       postDate:(NSDate * _Nullable)postDate
              backgroundImageURL:(NSURL * _Nullable)bgURL
                  sampleImageURL:(NSURL * _Nullable)sampleURL
                   badgeImageURL:(NSURL * _Nullable)badgeURL
                     onTapAction:(PPBannerOnTapAction)action
                      textStyle:(PPBannerTextStyle)textStyle
                      onTapValue:(NSString * _Nullable)value
                        bannerID:(NSString *)bannerID NS_DESIGNATED_INITIALIZER;

// Convenience initializers
- (instancetype)initWithTitle:(NSString *)title
                  description:(NSString *)desc
                     postDate:(NSString *)postDateText
            backgroundImageURL:(NSURL * _Nullable)bgURL
                sampleImageURL:(NSURL * _Nullable)sampleURL
                 badgeImageURL:(NSURL * _Nullable)badgeURL;

- (instancetype)initWithDictionary:(NSDictionary *)dict;

// Disable plain init if you want to enforce proper init
- (instancetype)init NS_UNAVAILABLE;

/// Returns a localized title based on current locale (defaults to English if Arabic not selected).
- (NSString *)localizedTitleText;
/// Returns a localized description text based on current locale.
- (NSString *)localizedDescText;
/// Returns YES if the banner is expired (current date is past expirationDate).
- (BOOL)isExpired;
/// Returns the remaining time on this banner's validity as a formatted string (e.g., "2d 5h 30m").
- (nullable NSString *)countdownTimeRemaining;


- (NSDictionary *)toDictionary;

@end

NS_ASSUME_NONNULL_END

/*
 
 Write a full and clean MainBannerModel and Modify PPBannerViewModel for those updates bellow
i want to add properites for all text like (titleTextAr , titleTextAr)
 and also add for me
 typedef NS_ENUM(NSInteger, PPBannerOnTapAction) {
     PPBannerOnTapViewAccessory, // default
     PPBannerOnTapViewAd,
     PPBannerOnTapOpenUrl,
     PPBannerOnTapCallPhoneNumber,
     PPBannerOnTapWhatsApp
 };

 and PPBannerPosition

 typedef NS_ENUM(NSInteger, PPBannerPosition) {
     PPBannerPositionTop, // default
     PPBannerPositionCenter,
     PPBannerPositionBorrom
 };


 and add PPBannerTransaction
 typedef NS_ENUM(NSInteger, PPBannerTransaction) {
     PPBannerTransactionScroll, // default
     PPBannerTransactionFace,
     PPBannerTransactionReplace
 };

 and add property  validateDaysHoursMins , later if admin set validate Days days or Hours or Mins we will show here to users count down label if admin keep nil nothing will shown


 and add any needs functions or property thats used for best prictics banners controll
 
 and add for me PPBamanersManager to do :
 - featching banners and apply them from conllection called BannersCollection have structure somthing like :

 MainBannersViewsCol{
     documentID {
         BannerViewID,
         BannerViewVisible,  // true/false admin can show and hide the banner live listenr for all any time
         BannerViewHolder,   // the view name that banner will display on
         BannerViewPosition, // is PPBannerPosition // banner position on holder can be top,center,bottom
         BannerViewTransaction,
         ChildsPannersModels
         {
             ChildsPannerID,
             titleTextAr, titleTextEn,
             descText, descText,
             descText, descText,
             postDate,
             pannerValidity,
             expireInDateTime,
             backgroundImageURL,
             sampleImageURL,
             badgeImageURL,
             pannerOnTapAction,
             pannerOnTapValue,
             pannerTapsCount,
         },
     }
 }

 also write function on PPBamanersManager
- add Banner
- Modify Banner
- Delete Banner
 
 
but in mind bro all those porperiter will control from Pure Pets Admin app
 
 
if you needs any informations from my current PPBannerViewModel here bellow PPBannerViewModel.h/PPBannerViewModel.m source to use it
 
 //  PPBannerViewModel.h
 @interface PPBannerViewModel : NSObject
 @property (nonatomic, copy, nullable) NSURL *backgroundImageURL;
 @property (nonatomic, copy, nullable) NSURL *sampleImageURL;   // product image
 @property (nonatomic, copy, nullable) NSURL *badgeImageURL;    // small badge icon (optional)
 @property (nonatomic, copy) NSString *titleText;
 @property (nonatomic, copy) NSString *descText;
 @property (nonatomic, copy) NSString *postDateText;            // e.g. "Sep 7, 2025"

 /// Designated initializer
 - (instancetype)initWithTitle:(NSString *)title
                    description:(NSString *)desc
                      postDate:(NSString *)postDate
              backgroundImageURL:(nullable NSURL *)bgURL
                  sampleImageURL:(nullable NSURL *)sampleURL
                   badgeImageURL:(nullable NSURL *)badgeURL NS_DESIGNATED_INITIALIZER;

 @end
 
 
 
 
 //  PPBannerViewModel.m
 @implementation PPBannerViewModel
 - (instancetype)initWithTitle:(NSString *)title
                    description:(NSString *)desc
                      postDate:(NSString *)postDate
              backgroundImageURL:(nullable NSURL *)bgURL
                  sampleImageURL:(nullable NSURL *)sampleURL
                   badgeImageURL:(nullable NSURL *)badgeURL {
     if (self = [super init]) {
         _titleText        = [title copy];
         _descText         = [desc copy];
         _postDateText     = [postDate copy];
         _backgroundImageURL = bgURL;
         _sampleImageURL     = sampleURL;
         _badgeImageURL      = badgeURL;
     }
     return self;
 }

 // Override default init to funnel through designated initializer
 - (instancetype)init {
     return [self initWithTitle:@"" description:@"" postDate:@"" backgroundImageURL:nil sampleImageURL:nil badgeImageURL:nil];
 }

 @end

 
 ChatGPT said:

 To create a full, scalable MainBannerModel, modify PPBannerViewModel, and implement PPBannersManager with real-time syncing, I’d like to clarify a few points:

 Data Source: Should the PPBannersManager fetch banners from Firestore in real-time (e.g., with a snapshot listener)? If so, do you already use Firebase SDK? YES

 BannerViewHolder: What values can this take? Is it a UIView name string like @"HomeHeaderView", or should we expect predefined enums? enums like BannerHolderMainView,BannerAccessoriesView,BannerHolderAdsView,BannerHolderFood,BannerHolderVetsView
     that means we will name it BannerHolder
 
 
 pannerOnTapValue: Should this be generic (e.g., URL string, phone number, etc.) depending on PPBannerOnTapAction? yes

 validateDaysHoursMins: Should we represent this as NSDateComponents or a dictionary like @{ @"days": 1, @"hours": 5 }? the best practis you choose

 Add/Modify/Delete: Should PPBannersManager also push updates back to Firestore, or just manage local state for now? sure push updates direct

 Let me know so I can tailor everything perfectly.
 
 
 
 */
