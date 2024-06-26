/*
 * Copyright (c) 2017, Psiphon Inc.
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#import "DebugLogViewController.h"
#import "PsiphonDataSharedDB.h"
#import "SharedConstants.h"
#import "Logging.h"
#import "PsiFeedbackLogger.h"
#import "FileUtils.h"
#import "Psiphon-Swift.h"

// Initial maximum number of logs to load.
#define MAX_LOGS_LOAD 250

/*
 * Limitations:
 *      - Only the main rotating_notices log file and not the backup
 *        is read and monitored for changes.
 *      - File change monitoring fails if file the log file has not been created yet.
 *      - Log file truncation is not handled.
 */
@implementation DebugLogViewController {
    UIActivityIndicatorView *activityIndicator;

    PsiphonDataSharedDB *sharedDB;

    NSString *logFilePath;
    NSFileHandle *logFileHandle;
    unsigned long long bytesReadFileOffset;
    dispatch_queue_t workQueue;

    dispatch_source_t dispatchSource;
}

- (instancetype)initWithLogPath:(NSString *)logPath title:(NSString *)title {
    self = [super init];
    if (self) {

        [self setTitle:title];
        logFilePath = logPath;
        sharedDB = [[PsiphonDataSharedDB alloc] initForAppGroupIdentifier:PsiphonAppGroupIdentifier];

        // NSFileHandle opened with fileHandleForReadingFromURL ows its associated
        // file descriptor, and will close it automatically when deallocated.
        NSError *err;
        logFileHandle = [NSFileHandle
          fileHandleForReadingFromURL:[NSURL fileURLWithPath:logFilePath]
                                error:&err];

        bytesReadFileOffset = (unsigned long long) 0;

        workQueue = dispatch_queue_create([[PsiphonAppGroupIdentifier stringByAppendingString:@".LogViewWorkQueue"] UTF8String],
          DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Activity Indicator
    activityIndicator = [[UIActivityIndicatorView alloc]
      initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    [activityIndicator setHidesWhenStopped:TRUE];
    activityIndicator.color = [UIColor blueColor];
    activityIndicator.center = self.view.center;

    [self.view addSubview:activityIndicator];

    // UIBar

    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc]
      initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(onNavigationDoneTap)];

    UIBarButtonItem *reloadButton = [[UIBarButtonItem alloc]
      initWithTitle:@"Reload" style:UIBarButtonItemStylePlain target:self action:@selector(onReloadTap)];

    [self.navigationItem setRightBarButtonItem:doneButton];
    [self.navigationItem setLeftBarButtonItem:reloadButton];

    [self loadDataAsync:TRUE];

    // Setup listeners for logs file.
    [self setupLogFileListener];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // Cancel dispatch source to stop receiving file change notifications.
    if (dispatchSource) {
        dispatch_source_cancel(dispatchSource);
    }
}

#pragma mark - UI Callbacks

- (void)onNavigationDoneTap {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)onReloadTap {
    [self loadDataAsync:TRUE];
}

#pragma mark - Helper functions

/*!
 * Submits work to workQueue to read new bytes from the log file an update the tableView.
 * @param userAction Whether a user action initiated data loading.
 */
- (void)loadDataAsync:(BOOL)userAction {

    // Caller should show spinner only when user performs an action.
    if (userAction) {
        [activityIndicator startAnimating];
    }

    dispatch_async(workQueue, ^{

        unsigned long long newBytesReadFileOffset;

        BOOL isFirstLogRead = (self->bytesReadFileOffset == 0);

        NSString *logData = [FileUtils tryReadingFile:self->logFilePath
                                      usingFileHandle:&self->logFileHandle
                                       readFromOffset:self->bytesReadFileOffset
                                         readToOffset:&newBytesReadFileOffset];

        LOG_DEBUG(@"Log old file offset %llu", self->bytesReadFileOffset);
        LOG_DEBUG(@"Log new file offset %llu", newBytesReadFileOffset);
        LOG_DEBUG(@"Log bytes read %llu", (newBytesReadFileOffset - self->bytesReadFileOffset));

        if (logData && ([logData length] > 0)) {

            self->bytesReadFileOffset = newBytesReadFileOffset;
            NSArray<DiagnosticEntry *> *newEntries = [ParseLogs parseLogs:logData];

            // On the first load, truncate array entries to MAX_LOGS_LOAD
            if (isFirstLogRead && ([newEntries count] > MAX_LOGS_LOAD)) {
                newEntries = [[NSMutableArray alloc] initWithArray:
                  [newEntries subarrayWithRange:NSMakeRange([newEntries count] - MAX_LOGS_LOAD, MAX_LOGS_LOAD)]];
            }

            dispatch_async(dispatch_get_main_queue(), ^{

                // Checks if last row was visible before the update.
                BOOL lastRowWasVisible = isFirstLogRead || [self lastRowVisible];

                // Add new entries to the table.
                [self addEntries:newEntries];

                // Only scroll to bottom if last row before the update
                // was visible on the screen.
                if (lastRowWasVisible || userAction) {
                    [self scrollToBottom];
                }

                if (userAction) {
                    [self->activityIndicator stopAnimating];
                }
            });
        } else {
            // At this point there was nothing to load,
            // we resort to scrolling to bottom of screen.
            if (userAction) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self->activityIndicator stopAnimating];
                    [self scrollToBottom];
                });
            }
        }

    });
}

- (void)setupLogFileListener {

    // TODO: log file rotation is not handled.

    int fd = open([logFilePath UTF8String], O_RDONLY);

    if (fd == -1) {
        [PsiFeedbackLogger error:@"Error opening log file to watch. errno: %s", strerror(errno)];
        [activityIndicator stopAnimating];
        return;
    }

    unsigned long mask = DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_DELETE;

    dispatchSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t) fd,
      mask, workQueue);

    dispatch_source_set_event_handler(dispatchSource, ^{
        unsigned long flag = dispatch_source_get_data(self->dispatchSource);

        if (flag & DISPATCH_VNODE_WRITE) {
            LOG_DEBUG(@"Log Dispatch_vnode_write");
            [self loadDataAsync:FALSE];
        } else if (flag & DISPATCH_VNODE_EXTEND){
            LOG_DEBUG(@"Log Dispatch_vnode_extend");
        } else if (flag & DISPATCH_VNODE_DELETE) {
            LOG_DEBUG(@"Log Dispatch_vnode_delete");
            self->bytesReadFileOffset = 0;
            dispatch_source_cancel(self->dispatchSource);
        }
    });

    dispatch_source_set_cancel_handler(dispatchSource, ^{
        LOG_DEBUG(@"Log dispatchSource Cancelled");
        close(fd);
    });

    dispatch_resume(dispatchSource);
}

@end

#pragma 

