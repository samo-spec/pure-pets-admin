//  MainBannerModel.m
//  Pure Pets

#import "MainBannerModel.h"

@implementation MainBannerModel

- (instancetype)initWithID:(NSString *)bannerViewID
                   visible:(BOOL)visible
                    holder:(PPBannerHolder)holder
                  position:(PPBannerPosition)position
               transaction:(PPBannerTransaction)transaction
                   banners:(NSArray<PPBannerViewModel *> *)banners {
    if (self = [super init]) {
        _bannerViewID        = PPSafeString(bannerViewID);
        _bannerViewVisible   = visible;
        _bannerViewHolder    = holder;
        _bannerViewPosition  = position;
        _bannerViewTransaction = transaction;
        _childBanners        = [banners copy] ?: @[];
    }
    return self;
}

- (instancetype)init {
    return [self initWithID:@""
                    visible:YES
                     holder:PPBannerHolderMainView
                   position:PPBannerPositionTop
                transaction:PPBannerTransactionScroll
                    banners:@[]];
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    NSString *docID  = PPSafeString(dict[@"docID"]);
    NSString *bannerViewID = PPSafeString(dict[@"BannerViewID"]);
    if (bannerViewID.length == 0) {
        bannerViewID = docID;
    }
    BOOL visible     = [dict[@"BannerViewVisible"] boolValue];

    PPBannerHolder holder = PPBannerHolderMainView;
    if ([dict[@"BannerViewHolder"] isKindOfClass:[NSNumber class]]) {
        holder = (PPBannerHolder)[dict[@"BannerViewHolder"] integerValue];
    }

    PPBannerPosition position = PPBannerPositionTop;
    if ([dict[@"BannerViewPosition"] isKindOfClass:[NSNumber class]]) {
        position = (PPBannerPosition)[dict[@"BannerViewPosition"] integerValue];
    }

    PPBannerTransaction transaction = PPBannerTransactionScroll;
    if ([dict[@"BannerViewTransaction"] isKindOfClass:[NSNumber class]]) {
        transaction = (PPBannerTransaction)[dict[@"BannerViewTransaction"] integerValue];
    }

    NSMutableArray<PPBannerViewModel *> *children = [NSMutableArray array];
    if ([dict[@"ChildsPannersModels"] isKindOfClass:[NSArray class]]) {
        for (NSDictionary *childDict in dict[@"ChildsPannersModels"]) {
            NSLog(@"childDict %@",childDict);
            PPBannerViewModel *bannerItem = [[PPBannerViewModel alloc] initWithDictionary:childDict];
            [children addObject:bannerItem];
        }
    }

    MainBannerModel *model = [self initWithID:bannerViewID
                                      visible:visible
                                       holder:holder
                                     position:position
                                  transaction:transaction
                                      banners:children];
    model.docID = docID.length ? docID : bannerViewID;
    return model;
}

#pragma mark - 🔥 To Dictionary

- (NSDictionary *)toDictionary {
    NSMutableArray *childDicts = [NSMutableArray array];
    for (PPBannerViewModel *vm in self.childBanners) {
        if ([vm respondsToSelector:@selector(toDictionary)]) {
            [childDicts addObject:[vm toDictionary]];
        }
    }

    return @{
        @"docID"                : PPSafeString(self.docID.length ? self.docID : self.bannerViewID),
        @"BannerViewID"         : PPSafeString(self.bannerViewID),
        @"BannerViewVisible"    : @(self.bannerViewVisible),
        @"BannerViewHolder"     : @(self.bannerViewHolder),
        @"BannerViewPosition"   : @(self.bannerViewPosition),
        @"BannerViewTransaction": @(self.bannerViewTransaction),
        @"ChildsPannersModels"  : childDicts
    };
}


- (instancetype)copy {
    MainBannerModel *copy = [[MainBannerModel alloc] initWithID:self.bannerViewID
                                                       visible:self.bannerViewVisible
                                                        holder:self.bannerViewHolder
                                                      position:self.bannerViewPosition
                                                   transaction:self.bannerViewTransaction
                                                       banners:[self.childBanners mutableCopy]];
    copy.docID = self.docID;
    return copy;
}
@end
