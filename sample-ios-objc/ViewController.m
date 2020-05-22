//
//  ViewController.m
//  sample-ios-objc
//

#import "ViewController.h"
#import "CZiti-Swift.h"

@interface ViewController () <UIDocumentPickerDelegate>
@property (weak, nonatomic) IBOutlet UITextField *urlTextField;
@property (weak, nonatomic) IBOutlet UITextView *textView;
@end

@implementation ViewController

Ziti *ziti;

- (NSString*)zidFile {
    NSString *documentPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    return [documentPath stringByAppendingString:@"/zid.json"];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [_urlTextField addTarget:self action:@selector(onTextFieldDidEndOnExit:) forControlEvents:UIControlEventEditingDidEndOnExit];
    
    if (ziti == NULL) {
        [self runZiti];
    }
}

- (void)runZiti {
    NSLog(@"zidFile = %@", [self zidFile]);
    ziti = [[Ziti alloc] initFromFile:[self zidFile]];
    
    if (ziti != NULL) {
        [ziti runAsync: ^(ZitiError *zErr) {
            if (zErr != NULL) {
                [self handleZitiInitError:zErr];
                return;
            }
            [ZitiUrlProtocol register:ziti :10000];
        }];
    } else {
        [self onNoIdentity];
    }
}

- (void)handleZitiInitError:(ZitiError *)zErr {
    UIAlertController* alert = [UIAlertController
                                 alertControllerWithTitle:@"Ziti Init Error"
                                 message:[zErr localizedDescription]
                                 preferredStyle:UIAlertControllerStyleAlert];
     
    
     [alert addAction:[UIAlertAction
                       actionWithTitle:@"Retry"
                       style:UIAlertActionStyleDefault
                       handler:^(UIAlertAction * action) {
         [self runZiti];
     }]];
     
     [alert addAction:[UIAlertAction
                       actionWithTitle:@"Forget This Identity"
                       style:UIAlertActionStyleDefault
                       handler:^(UIAlertAction * action) {
         
         if (ziti != NULL) {
             [ziti forget];
         }
         
         NSError *error;
         [[NSFileManager defaultManager] removeItemAtPath:[self zidFile] error:&error];
         
         [self onNoIdentity];
     }]];
    
    [alert addAction:[UIAlertAction
                      actionWithTitle:@"Exit"
                      style:UIAlertActionStyleDefault
                      handler:^(UIAlertAction * action) {
        exit(1);
    }]];
     
     dispatch_async(dispatch_get_main_queue(), ^{
         [self presentViewController:alert animated:YES completion:nil];
     });
}

- (void) onNoIdentity {
    UIAlertController* alert = [UIAlertController
                                alertControllerWithTitle:@"Ziti Identity Not Found"
                                message:@"What do you want to do now?"
                                preferredStyle:UIAlertControllerStyleAlert];
    
   
    
    [alert addAction:[UIAlertAction
                      actionWithTitle:@"Enroll"
                      style:UIAlertActionStyleDefault
                      handler:^(UIAlertAction * action) {
        [self enroll];
    }]];
    
    [alert addAction:[UIAlertAction
                      actionWithTitle:@"Exit"
                      style:UIAlertActionStyleDefault
                      handler:^(UIAlertAction * action) {
        exit(1);
    }]];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void) enroll {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIDocumentPickerViewController* dp =
          [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.item"]
                                                                 inMode:UIDocumentPickerModeImport];
        dp.modalPresentationStyle = UIModalPresentationFormSheet;
        dp.allowsMultipleSelection = NO;
        dp.delegate = self;
        [self presentViewController:dp animated:YES completion:^{}];
    });
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    [self onNoIdentity];
}

- (void) documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    
    [Ziti enroll:[urls firstObject].path : ^(ZitiIdentity *zid, ZitiError *zErr) {
        
        // Alert on Error
        if (zErr != NULL) {
            UIAlertController* alert = [UIAlertController
                                       alertControllerWithTitle:@"Enrollment Error"
                                       message:[zErr localizedDescription]
                                       preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction
                             actionWithTitle:@"OK"
                             style:UIAlertActionStyleDefault
                             handler:^(UIAlertAction * action) {
                   [self onNoIdentity];
            }]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
        
        // Attempt to save the identity file
        if (![zid save:[self zidFile]]) {
            UIAlertController* alert = [UIAlertController
                                           alertControllerWithTitle:@"Unable to store identity file"
                                           message:[self zidFile]
                                           preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction
                                 actionWithTitle:@"OK"
                                 style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction * action) {
                   [self onNoIdentity];
            }]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
        
        // All good.  Tell user "good job" and attempt to runZiti
        UIAlertController* alert = [UIAlertController
                                       alertControllerWithTitle:@"Enrolled!"
                                       message:@"You have successfully enrolled"
                                       preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction
                             actionWithTitle:@"OK"
                             style:UIAlertActionStyleDefault
                             handler:^(UIAlertAction * action) {}]];
        [self presentViewController:alert animated:YES completion:nil];
        [self runZiti];
    }];
}

- (void) onTextFieldDidEndOnExit:(id) obj {
    
    NSURL *url = [[NSURL alloc] initWithString:_urlTextField.text];
    NSURLRequest *urlReq = [[NSURLRequest alloc] initWithURL:url];
    BOOL zitiCanHandle = [ZitiUrlProtocol canInitWithRequest:urlReq];
    
    if (!zitiCanHandle) {
        UIAlertController* alert = [UIAlertController
                                   alertControllerWithTitle:@"Not a Ziti request"
                                   message:@"This request will not be routed over your Ziti nework.\nAre you sure you'd like to request this URL?"
                                   preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction
                         actionWithTitle:@"OK"
                         style:UIAlertActionStyleDefault
                         handler:^(UIAlertAction * action) {
               [self loadUrl:urlReq];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    } else {
        [self loadUrl:urlReq];
    }
    [_urlTextField resignFirstResponder];
}

-(void)setScrollableText:(NSString *)txt {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_textView.textStorage.mutableString setString:txt];
    });
}

- (void)loadUrl:(NSURLRequest *)urlReq {
    
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:urlReq
                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error != NULL) {
            [self setScrollableText:error.localizedDescription];
            return;
        }
        
        NSString *docStr = @"";
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        if (httpResp != NULL) {
            NSString *statusStr = [NSHTTPURLResponse localizedStringForStatusCode:httpResp.statusCode];
            docStr = [NSString stringWithFormat:@"Status: %ld (%@)\n", (long)httpResp.statusCode, statusStr];
            
            NSDictionary *dict = [httpResp allHeaderFields];
            for (NSString *key in dict) {
                docStr = [NSString stringWithFormat:@"%@%@: %@\n", docStr, key, dict[key]];
            }
            docStr = [NSString stringWithFormat:@"%@\n", docStr];
        }
        
        BOOL canPrintData = NO;
        if (data != NULL) {
            NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (str != NULL) {
                canPrintData = YES;
                docStr = [NSString stringWithFormat:@"%@%@", docStr, str];
            }
        }
        
        if (!canPrintData) {
            docStr = [NSString stringWithFormat:@"%@...Unable to decode body to string...", docStr];
        }
        [self setScrollableText:docStr];
    }];
    
    [dataTask resume];
}

@end
