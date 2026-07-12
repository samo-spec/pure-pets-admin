//
//  AccessoriesListViewController.h
//  PurePetsAdmin
//
//  Created by Mohammed Ahmed on 22/08/2025.
//


//
//  AccessoriesListViewController.h
//  PurePetsAdmin
//
//  Created by Admin on 22/08/2025.
//

#import <UIKit/UIKit.h>
#import "PPS.h"
@interface AccessoriesListViewController : UIViewController

@property (nonatomic, assign) AccessKindType listKind;
@property (nonatomic, copy) NSString *currentAccessQuery;
@property (nonatomic, strong) UITableView *tableView;
- (instancetype)initWithKind:(AccessKindType)kind;

@end
