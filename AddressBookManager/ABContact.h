//
//  ABContact.h
//
//  Created by Albert Hernández on 29/11/10.
//  Updated by Ivan on 16/5/12.
//

#import <Foundation/Foundation.h>
#import <AddressBook/AddressBook.h>

typedef enum{
	ABContactLocaleNameSurname = 0,
	ABContactLocaleSurnameName = 1
}ABContactLocale;

typedef enum{
	ABContactStatusNew = 1,
	ABContactStatusModified = 2,
	ABContactStatusDeleted = 3
}ABContactStatus;

@interface ABContact : NSObject

@property (nonatomic, assign) ABRecordID contactId;
@property (nonatomic, retain) NSString *compositeName;
@property (nonatomic, retain) NSString *name;
@property (nonatomic, retain) NSString *middleName;
@property (nonatomic, retain) NSString *lastName;
@property (nonatomic, retain) NSArray<NSString*> *emails;
@property (nonatomic, retain) NSArray *emailsLabels;
@property (nonatomic, retain) NSDate *birthday;
@property (nonatomic, retain) NSString *department;
@property (nonatomic, retain) NSString *jobTitle;
@property (nonatomic, retain) NSString *company;
@property (nonatomic, retain) NSString *suffix;
@property (nonatomic, retain) NSString *nickName;
@property (nonatomic, retain) NSDate *creationDate;
@property (nonatomic, retain) NSDate *modificationDate;
/**
 * each element is a NSDictionary with keys:
 *  kABPersonAddressStreetKey
 *  kABPersonAddressCityKey
 *  kABPersonAddressStateKey;
 *  kABPersonAddressZIPKey;
 *  kABPersonAddressCountryKey;
 *  kABPersonAddressCountryCodeKey;
 */
@property (nonatomic, retain) NSArray *address;
@property (nonatomic, retain) NSArray *addressLabels;
@property (nonatomic, retain) NSArray *phones;
@property (nonatomic, retain) NSArray *phonesLabels;
@property (nonatomic, retain) UIImage *image;
@property (nonatomic) ABContactStatus status;
@property (nonatomic) ABContactLocale sortOrder;

- (NSString*)fullName;
- (NSString*)sortingName;
- (NSString*)indexCharacter;

@end
