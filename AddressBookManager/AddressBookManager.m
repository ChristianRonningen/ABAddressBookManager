//
//  AddressBookManager.m
//  fonyoukpn
//
//  Updated by Ivan Roige on 16/5/12.
//  Adapted to ARC by Eli Kohen on 24/04/13
//  Copyright FonYou 2013. All rights reserved.
//

#import <AddressBook/AddressBook.h>
#import "AddressBookManager.h"
#import "MobileContact.h"
#import "ProgressData.h"
#import "PersonDataConverter.h"

#define OLD_ADB (&ABAddressBookCreateWithOptions == NULL)

#define AddressBookCreate OLD_ADB ? ABAddressBookCreate() : ABAddressBookCreateWithOptions(NULL, NULL);

@implementation NSString (Phone)
- (NSString*)stringByCleaningPhoneNumber{
	
	//Stripping separators
	NSString *clean = [self stringByReplacingOccurrencesOfString:@" " withString:@""];
	clean = [clean stringByReplacingOccurrencesOfString:@"-" withString:@""];
	clean = [clean stringByReplacingOccurrencesOfString:@"(" withString:@""];
	clean = [clean stringByReplacingOccurrencesOfString:@")" withString:@""];
	clean = [clean stringByReplacingOccurrencesOfString:@"." withString:@""];
	clean = [clean stringByReplacingOccurrencesOfString:@"+" withString:@"00"];
	if (clean && clean.length > 0){
		return clean;
	}
	
	return [self copy];
}
@end

@interface AddressBookManager (){
    BOOL ios6AdbPermission;
	ABPersonSortOrdering mSortOrdering;
	ABPersonCompositeNameFormat mCompositeNameFormat;
}
/*
 *  Current contacts list readed.
 */
@property (atomic, strong) NSArray *mContacts;
@property (atomic, strong) NSDictionary *mContactsByPhone;

@end

@implementation AddressBookManager

#pragma mark -
#pragma mark Object lifecycle

- (id)init{
    self = [super init];
    if (self) {
		mSortOrdering = ABPersonGetSortOrdering();
		mCompositeNameFormat = ABPersonGetCompositeNameFormat();
        _readPhotos = NO;
		_contactsFilter = AddessBookManagerFilterAllContacts;
        ios6AdbPermission = YES;
    }
    return self;
}

#pragma mark -
#pragma mark Public methods

#pragma mark > Queries

- (void)retrieveContactsWithDelegate:(NSObject<AddressBookManagerDelegate>*)aDelegate{
	if (self){
		self.delegat = aDelegate;
		
		[NSThread detachNewThreadSelector:@selector(initContacts) toTarget:self withObject:nil];
	}
}

- (void)refreshContacts{
	[NSThread detachNewThreadSelector:@selector(initContacts) toTarget:self withObject:nil];
}

- (BOOL)hasContactAccessPermission{
    return ios6AdbPermission;
}

#pragma mark > Contacts array handling

- (NSArray*)contacts{
	return self.mContacts;
}

- (NSArray*) contactsWithQuery: (NSString*) query{
	NSMutableArray *result = [[NSMutableArray alloc] init];
	
	NSArray *queryStrings = [query componentsSeparatedByString:@" "];
	for (MobileContact * contact in self.mContacts){
		BOOL matches = YES;
		for(NSString *partQuery in queryStrings){
			if(!partQuery || partQuery.length == 0){
				continue;
			}
			
			NSRange range = [[contact fullName] rangeOfString:partQuery options:NSCaseInsensitiveSearch];
			if( range.location == NSNotFound){
				matches = NO;
				break;
			}
		}
		if(matches){
			[result addObject:contact];
		}
	}
	return result;
}

- (MobileContact*) contactByPhoneNumber: (NSString*) phoneNumber{
	MobileContact *contact = [self.mContactsByPhone objectForKey:[phoneNumber stringByCleaningPhoneNumber]];
	return contact;
}

- (BOOL)isOrderByLastName{
	return mSortOrdering == kABPersonSortByLastName;
}

- (BOOL)isShowByLastName{
	return mCompositeNameFormat == kABPersonCompositeNameFormatLastNameFirst;
}

#pragma mark > ABAddressBook modifications

- (BOOL)loadContactPhoto:(MobileContact*)contact{
	ABAddressBookRef addressbook = AddressBookCreate;
    
    ABRecordRef abItem = ABAddressBookGetPersonWithRecordID(addressbook, contact.contactId);
	
	if (!abItem) {
        NSLog(@"modifyItem: Unable to retrieve contact");
        CFRelease(addressbook);
        return NO;
    }
	
	// Retrieve contact img
	CFDataRef imageData = ABPersonCopyImageDataWithFormat(abItem, kABPersonImageFormatThumbnail);
	if (imageData) {
		contact.image = [UIImage imageWithData:(__bridge NSData*)imageData];
		CFRelease(imageData);
		CFRelease(addressbook);
		return YES;
	}
	
	CFRelease(addressbook);
	return NO;
}

-(BOOL) insertContact:(MobileContact*)theContact{

    if(!theContact){
        NSLog(@"[WARNING] insertContact: nil contact!");
        return NO;
    }

    ABAddressBookRef addressbook = AddressBookCreate;
    
    CFErrorRef err;
    
    ABRecordRef abItem = ABPersonCreate();
    if (!abItem) {
        NSLog(@"insertItem: Unable to create person");
        CFRelease(addressbook);
        return NO;
    }
    
    PersonDataConverter *pdc = [[PersonDataConverter alloc] init];
    [pdc convertContact:theContact toPerson:abItem];
    
    if (!ABAddressBookAddRecord(addressbook, abItem, &err)) {
        NSLog(@"insertItem: Unable to add Person to AddressBook for contact %@", theContact);
        CFRelease(err);
        CFRelease(abItem);
        CFRelease(addressbook);
        return NO;
    }
    
    if (!ABAddressBookSave(addressbook, &err)) {
        NSLog(@"insertItem: Unable to save AddressBook for contact %@", theContact);
        CFRelease(err);
        CFRelease(abItem);
        CFRelease(addressbook);
        return NO;
    }
    
    ABRecordID uid = ABRecordGetRecordID(abItem);
    
    [self copyPropertiesOfPerson:abItem toMobileContact:theContact];
    
    NSLog(@"insertItem: Success for item with key %d", uid);
    
    CFRelease(abItem);
    CFRelease(addressbook);
    
    return YES;
    
}

-(BOOL) modifyContact:(MobileContact*)theContact{
    
    if(!theContact){
        NSLog(@"[WARNING] modifyItem: nil contact!");
        return NO;
    }    

    ABAddressBookRef addressbook = AddressBookCreate;
    
    CFErrorRef err;
    
    ABRecordRef abItem = ABAddressBookGetPersonWithRecordID(addressbook, theContact.contactId);
    
    PersonDataConverter *pdc = [[PersonDataConverter alloc] init];
    [pdc convertContact:theContact toPerson:abItem];
    
    if (!abItem) {
        NSLog(@"modifyItem: Unable to modify contact");
        CFRelease(addressbook);
        return NO;
    }
    
    if (!ABAddressBookSave(addressbook, &err)) {
        NSLog(@"modifyItem: Unable to save AddressBook for contact %@", theContact);
        CFRelease(err);   
        CFRelease(addressbook);
        return NO;
    }
    
    ABRecordID uid = ABRecordGetRecordID(abItem);
    
    [self copyPropertiesOfPerson:abItem toMobileContact:theContact];
    
    NSLog(@"modifyItem: Success for item with key %d", uid);
    CFRelease(addressbook);
    return YES;
}

-(BOOL) removeContact:(MobileContact*)theContact{
    
    if(!theContact){
        NSLog(@"[WARNING] removeContact: nil contact!");
        return NO;
    }

    ABAddressBookRef addressbook = AddressBookCreate;
    
    CFErrorRef err;
    
    ABRecordRef abItem = ABAddressBookGetPersonWithRecordID(addressbook, theContact.contactId);
    
    if (!abItem) {
        NSLog(@"removeItem: Unable to get person to delete");
        CFRelease(addressbook);
        return NO;
    }
    
    if (!ABAddressBookRemoveRecord(addressbook, abItem, &err)) {
        NSLog(@"removeContact: Unable to save AddressBook for contact %@", theContact);
        CFRelease(err);
        CFRelease(addressbook);
        return NO;
    }
    
    if (!ABAddressBookSave(addressbook, &err)) {
        NSLog(@"removeContact: Unable to save AddressBook for contact %@", theContact);
        CFRelease(err);
        CFRelease(addressbook);
        return NO;
    }
    
    ABRecordID uid = ABRecordGetRecordID(abItem);
    
    NSLog(@"removeContact: Success for item with key %d", uid);
    CFRelease(addressbook);
    return YES;
}

- (BOOL) removeAllContacts{
    
    ABAddressBookRef addressbook = AddressBookCreate;
    
    CFErrorRef err;
    
    CFArrayRef arr = ABAddressBookCopyArrayOfAllPeople(addressbook);

    int count = CFArrayGetCount(arr);
    
    for (int x = 0; x < count; x++) {
        ABRecordRef rec = CFArrayGetValueAtIndex(arr, x);
        ABRecordID  key = ABRecordGetRecordID(rec);
        
        ABRecordRef abItem = ABAddressBookGetPersonWithRecordID(addressbook,key);
        if (!ABAddressBookRemoveRecord(addressbook, abItem, &err)) {
            NSLog(@"[Warning] removeAllItems: error removing record: %d", key);
            CFRelease(err);
            if(arr) CFRelease(arr);
            CFRelease(addressbook);
            return NO;
        }
        
    }
    
    if (!ABAddressBookSave(addressbook, &err)) {
        if(arr) CFRelease(arr);
        CFRelease(err);
        CFRelease(addressbook);
        return NO;
    }
    
    if(arr) CFRelease(arr);
    CFRelease(addressbook);
    return YES;
}

#pragma mark -
#pragma mark Private methods

- (void)addInfoFrom:(ABMutableMultiValueRef)baseArr toValuesArr:(NSMutableArray*)valuesArr andLabelsArr:(NSMutableArray*)labelsArr{
    
    if (baseArr){
        
		for (CFIndex idx = 0; idx < ABMultiValueGetCount(baseArr); idx++){
            
            CFTypeRef field = ABMultiValueCopyValueAtIndex(baseArr, idx);
            NSString *sField = (field) ? (__bridge NSString*)field : @"";
     		[valuesArr addObject:sField];
            if (field) CFRelease(field);
            
            CFTypeRef lbl = ABMultiValueCopyLabelAtIndex(baseArr, idx);
            NSString *sLbl = (lbl) ? (__bridge NSString*)lbl : @"";
			[labelsArr addObject:sLbl];
            if (lbl) CFRelease(lbl);
            
		}
        
	}

}

#pragma mark > ABAddressBook queries

- (void)initContacts{
	
    ABAddressBookRef addressBook;
    if (&ABAddressBookCreateWithOptions != NULL) {
        //iOS 6 requires address book permission.
        
        //Saving current thread queue.
        dispatch_queue_t currentQueue = dispatch_get_global_queue(0,0);
        
        CFErrorRef error = nil;
        addressBook = ABAddressBookCreateWithOptions(NULL,&error);
        ABAddressBookRequestAccessWithCompletion(addressBook, ^(bool granted, CFErrorRef error) {
            // callback can occur in background, address book must be accessed on thread it was created on
            dispatch_async(currentQueue, ^{
                if(error || !granted){
                    ios6AdbPermission = NO;
                    //Just call the delegate
                    [self performSelectorOnMainThread:@selector(contactsPermissionDenied) withObject:nil waitUntilDone:NO];
                }
                else {
                    [self commonInitContactsWithAddressBook:addressBook];
                }
            });
        });
    } else {
        // iOS 4/5 just access directly
        addressBook = AddressBookCreate;
        [self commonInitContactsWithAddressBook:addressBook];
    }
}


/*
 * Common initialization after ios 6 check
 */
- (void) commonInitContactsWithAddressBook: (ABAddressBookRef) addressBook{
	
	// Iterate the array of all contacts and add to our data structure
	CFArrayRef people = ABAddressBookCopyArrayOfAllPeople(addressBook);	// ahl: it makes a shallow copy, doesn't need to release it again
	
	// Init
	NSMutableArray *theContacts = [[NSMutableArray alloc] initWithCapacity:CFArrayGetCount(people)];
	NSMutableDictionary *theContactsByPhone = [[NSMutableDictionary alloc] initWithCapacity:CFArrayGetCount(people)];
    
	// Update composite name format & sort ordering
	mCompositeNameFormat = ABPersonGetCompositeNameFormat();
	mSortOrdering = ABPersonGetSortOrdering();
	
	// Copy contacts to mutable array
	CFMutableArrayRef peopleMutable = CFArrayCreateMutableCopy(kCFAllocatorDefault, CFArrayGetCount(people), people);
	
	// Order contacts in the way the user want
	CFRange fullRange = CFRangeMake(0, CFArrayGetCount(peopleMutable));
	CFArraySortValues(peopleMutable, fullRange, (CFComparatorFunction) ABPersonComparePeopleByName, (void*)mSortOrdering);
	CFRelease(people);
	
	NSNumber *itemsTotal = [NSNumber numberWithInt:CFArrayGetCount(peopleMutable)];
	
	NSMutableSet *contactsSet = [[NSMutableSet alloc] init];
	
	for (CFIndex idx = 0; idx < CFArrayGetCount(peopleMutable); idx++){
        
		ABRecordRef person = CFArrayGetValueAtIndex(peopleMutable, idx);
		
		if([contactsSet containsObject:(__bridge id)(person)]){
			continue;
		}
		
		[contactsSet addObject:(__bridge id)(person)];
		
		MobileContact *contact = [[MobileContact alloc] init];
		contact.sortOrder = (MobileContactLocale)mSortOrdering;
        [self copyPropertiesOfPerson:person toMobileContact:contact];
		
		//Merging all linked contacts into same MobileContact
		CFArrayRef linkedRef = ABPersonCopyArrayOfAllLinkedPeople(person);
		for (CFIndex lidx = 0; lidx < CFArrayGetCount(linkedRef); lidx++){
			ABRecordRef userLinked = CFArrayGetValueAtIndex(linkedRef, lidx);
			if([contactsSet containsObject:(__bridge id)(userLinked)]){
				continue;
			}
			[self addValuesOfPerson:userLinked toMobileContact:contact];
		}
		NSArray *linked = CFBridgingRelease(linkedRef);
		[contactsSet addObjectsFromArray:linked];
		
		//Filtering contacts
		if((self.contactsFilter == AddessBookManagerFilterOnlyWithNumbers || self.contactsFilter == AddessBookManagerFilterOnlyNameAndNumbers) && (!contact.phones || contact.phones.count == 0)){
			continue;
		}
		if(self.contactsFilter == AddessBookManagerFilterOnlyNameAndNumbers && !contact.compositeName){
			continue;
		}
        
		//Contacts list
        [theContacts addObject:contact];
		
		//Contacts by phone Dictionary
		for(NSString *phone in contact.phones){
			[theContactsByPhone setObject:contact forKey:[phone stringByCleaningPhoneNumber]];
		}
		
		
		NSNumber *itemsProcessed = [NSNumber numberWithInt:idx+1];
		ProgressData *pd = [[ProgressData alloc] initWithItemsProcessed:itemsProcessed itemsTotal:itemsTotal andLabel:nil];
		[self performSelectorOnMainThread:@selector(updateProgress:) withObject:pd waitUntilDone:NO];
	}
    CFRelease(addressBook);
	CFRelease(peopleMutable);
	
	self.mContacts = theContacts;
	self.mContactsByPhone = theContactsByPhone;
	
	[self performSelectorOnMainThread:@selector(contactsLoaded) withObject:nil waitUntilDone:NO];
}


- (void)retrieveEmailsAndEmailsLabelsForContact:(MobileContact*)contact withABRecordRef:(ABRecordRef)person{
    
	NSMutableArray *emailsArr = [[NSMutableArray alloc] init];
	NSMutableArray *emailsLabelsArr = [[NSMutableArray alloc] init];
    ABMultiValueRef emails  = ABRecordCopyValue(person, kABPersonEmailProperty); // ABMutableMultiValueRef: value list
    
    [self addInfoFrom:emails toValuesArr:emailsArr andLabelsArr:emailsLabelsArr];
	
    if (emails) CFRelease(emails);
    
	contact.emails = emailsArr;
	contact.emailsLabels = emailsLabelsArr;
}

- (void)addEmailsAndEmailsLabelsForContact:(MobileContact*)contact withABRecordRef:(ABRecordRef)person{
    
	NSMutableArray *emailsArr = [[NSMutableArray alloc] initWithArray:contact.emails];
	NSMutableArray *emailsLabelsArr = [[NSMutableArray alloc] initWithArray:contact.emailsLabels];
    ABMultiValueRef emails  = ABRecordCopyValue(person, kABPersonEmailProperty); // ABMutableMultiValueRef: value list
    
    [self addInfoFrom:emails toValuesArr:emailsArr andLabelsArr:emailsLabelsArr];
	
    if (emails) CFRelease(emails);
    
	contact.emails = emailsArr;
	contact.emailsLabels = emailsLabelsArr;
}

- (void)retrievePhonesAndPhoneLabelsForContact:(MobileContact*)contact withABRecordRef:(ABRecordRef)person{
    
	NSMutableArray *phonesArr = [[NSMutableArray alloc] init];
	NSMutableArray *phonesLabelsArr = [[NSMutableArray alloc] init];
	ABMutableMultiValueRef phones = ABRecordCopyValue(person, kABPersonPhoneProperty);	// ABMutableMultiValueRef: value list
	
    [self addInfoFrom:phones toValuesArr:phonesArr andLabelsArr:phonesLabelsArr];
	
    if (phones) CFRelease(phones);	
	
	contact.phones = phonesArr;
	contact.phonesLabels = phonesLabelsArr;
}

- (void)addPhonesAndPhoneLabelsForContact:(MobileContact*)contact withABRecordRef:(ABRecordRef)person{
    
	NSMutableArray *phonesArr = [[NSMutableArray alloc] initWithArray:contact.phones];
	NSMutableArray *phonesLabelsArr = [[NSMutableArray alloc] initWithArray:contact.phonesLabels];
	ABMutableMultiValueRef phones = ABRecordCopyValue(person, kABPersonPhoneProperty);	// ABMutableMultiValueRef: value list
	
    [self addInfoFrom:phones toValuesArr:phonesArr andLabelsArr:phonesLabelsArr];
	
    if (phones) CFRelease(phones);
	
	contact.phones = phonesArr;
	contact.phonesLabels = phonesLabelsArr;
}

- (void)retrieveAddressAndAddressLabelsForContact:(MobileContact*)contact withABRecordRef:(ABRecordRef)person{

    NSMutableArray *addressArr = [[NSMutableArray alloc] init];
	NSMutableArray *addressLabelsArr = [[NSMutableArray alloc] init];
	ABMutableMultiValueRef address = ABRecordCopyValue(person, kABPersonAddressProperty);	// ABMutableMultiValueRef: value list
	
    [self addInfoFrom:address toValuesArr:addressArr andLabelsArr:addressLabelsArr];
	
    if (address) CFRelease(address);
    
    contact.address = addressArr;
	contact.addressLabels = addressLabelsArr;
    
}

- (void)addAddressAndAddressLabelsForContact:(MobileContact*)contact withABRecordRef:(ABRecordRef)person{
	
    NSMutableArray *addressArr = [[NSMutableArray alloc] initWithArray:contact.address];
	NSMutableArray *addressLabelsArr = [[NSMutableArray alloc] initWithArray:contact.addressLabels];
	ABMutableMultiValueRef address = ABRecordCopyValue(person, kABPersonAddressProperty);	// ABMutableMultiValueRef: value list
	
    [self addInfoFrom:address toValuesArr:addressArr andLabelsArr:addressLabelsArr];
	
    if (address) CFRelease(address);
    
    contact.address = addressArr;
	contact.addressLabels = addressLabelsArr;
    
}

#pragma mark > AddressBookManagerDelegate calls

- (void)updateProgress:(ProgressData*)progress{
	if (_delegat && [_delegat respondsToSelector:@selector(updateProgress:)])
        [_delegat updateProgress:progress];
}

- (void)contactsLoaded{
	if (_delegat && [_delegat respondsToSelector:@selector(contactsLoaded)])
        [_delegat contactsLoaded];
	else{
		[[NSNotificationCenter defaultCenter] postNotificationName:kNotificationAddressBookManagerUpdated object:nil];
	}
}

- (void) contactsPermissionDenied{
    if (_delegat && [_delegat respondsToSelector:@selector(contactsPermissionDenied)]){
        [_delegat contactsPermissionDenied];
    }
	else{
		[[NSNotificationCenter defaultCenter] postNotificationName:kNotificationAddressBookManagerNoPermission object:nil];
	}
}

#pragma mark > ABAddressBook modifications

- (void)copyPropertiesOfPerson:(ABRecordRef)person toMobileContact:(MobileContact*)contact{
    
    //read direct properties from person
	NSString *compositeName = ( NSString*)CFBridgingRelease(ABRecordCopyCompositeName(person));
    NSString *name		 = ( NSString*)CFBridgingRelease(ABRecordCopyValue(person, kABPersonFirstNameProperty));
    NSString *middleName = ( NSString*)CFBridgingRelease(ABRecordCopyValue(person, kABPersonMiddleNameProperty));
    NSString *lastName	 = ( NSString*)CFBridgingRelease(ABRecordCopyValue(person, kABPersonLastNameProperty));
    NSDate *birthday = ( NSDate*)CFBridgingRelease(ABRecordCopyValue(person, kABPersonBirthdayProperty));
    NSString *department = ( NSString*)CFBridgingRelease(ABRecordCopyValue(person, kABPersonDepartmentProperty));
    NSString *jobTitle = ( NSString*)CFBridgingRelease(ABRecordCopyValue(person, kABPersonJobTitleProperty));
    NSString *company = ( NSString*)CFBridgingRelease(ABRecordCopyValue(person, kABPersonOrganizationProperty));
    NSString *suffix = ( NSString*)CFBridgingRelease(ABRecordCopyValue(person, kABPersonSuffixProperty));
    NSString *nickName = ( NSString*)CFBridgingRelease(ABRecordCopyValue(person, kABPersonNicknameProperty));
    NSDate *creationDate = ( NSDate*)CFBridgingRelease(ABRecordCopyValue(person, kABPersonCreationDateProperty));
    NSDate *modificationDate = ( NSDate*)CFBridgingRelease(ABRecordCopyValue(person, kABPersonModificationDateProperty));
    ABRecordID contactId = ABRecordGetRecordID(person);
    
    //copy previous properties to contact
	contact.compositeName = compositeName;
    contact.name = name;
    contact.middleName = middleName;
    contact.lastName = lastName;
    contact.contactId = contactId;
    contact.birthday = birthday;
    contact.department = department;
    contact.jobTitle = jobTitle;
    contact.company = company;
    contact.suffix = suffix;
    contact.nickName = nickName;
    contact.creationDate = creationDate;
    contact.modificationDate = modificationDate;
    
    //read multi-value properties
    [self retrieveEmailsAndEmailsLabelsForContact:contact withABRecordRef:person];    
    [self retrieveAddressAndAddressLabelsForContact:contact withABRecordRef:person];
    [self retrievePhonesAndPhoneLabelsForContact:contact withABRecordRef:person];
    
    //save photo if needed
    if (_readPhotos) {
        // Retrieve contact img
        CFDataRef imageData = ABPersonCopyImageDataWithFormat(person, kABPersonImageFormatThumbnail);
        if (imageData) {
            contact.image = [UIImage imageWithData:(__bridge NSData*)imageData];
            CFRelease(imageData);
        }
    }
    
    //release related variables
	name = nil;
	middleName = nil;
	lastName = nil;
	birthday = nil;
	department = nil;
	jobTitle = nil;
	company = nil;
	suffix = nil;
	nickName = nil;
	creationDate = nil;
	modificationDate = nil;
}

- (void)addValuesOfPerson:(ABRecordRef)person toMobileContact:(MobileContact*)contact{
	//read multi-value properties
    [self addEmailsAndEmailsLabelsForContact:contact withABRecordRef:person];
    [self addAddressAndAddressLabelsForContact:contact withABRecordRef:person];
    [self addPhonesAndPhoneLabelsForContact:contact withABRecordRef:person];
}

#pragma mark -
#pragma mark Singleton

+ (AddressBookManager *)sharedObject
{
    static AddressBookManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[AddressBookManager alloc] init];
        // Do any other initialisation stuff here
    });
    return sharedInstance;
}

- (void)dealloc {
    self.delegat = nil;
	self.mContacts = nil;
}

@end
