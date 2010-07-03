//
//  DBTimerWindowController.m
//  Vidi
//
//  Created by Mitz Pettel on Feb 27 2003.
//  Copyright (c) 2003 Mitz Pettel. All rights reserved.
//

#import "DBTimerWindowController.h"

#import "DBAudioCompression.h"
#import "DBTVChannel.h"
#import "DBVidi.h"
#import "NSDictionary-DBVidiJobAdditions.h"


NSString * const DBOriginalChannelIndexKey = @"original index";
NSString * const DBTimerStatusColumnIdentifier = @"status";
NSString * const DBTimerChannelColumnIdentifier = @"channel";
NSString * const DBTimerFileColumnIdentifier = @"file";
NSString * const DBTimerStartColumnIdentifier = @"start";
NSString * const DBTimerEndColumnIdentifier = @"end";
NSString * const DBTimerDateColumnIdentifier = @"date";

@implementation DBTimerWindowController

- (id)initWithVidi:(DBVidi *)vidi
{
    _vidi = vidi;
    self = [super initWithWindowNibName:@"Timer"];
    return self;
}

- (void)dealloc
{
    [_updateTimer release];
    [_audioFormat release];
    [_timeFormatString release];
    [_dateFormatString release];

    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_sortedJobs release];
    [super dealloc];
}

- (void)windowDidLoad
{
    NSMutableString *cleanShortDateFormatString;
    NSString *tmpString;
    NSScanner *scanner;
    NSDateFormatter *shortDateFormatter;
    NSDateFormatter *timeFormatter;
    
    [self updateSortedJobs];
    [super windowDidLoad];
    [self setShouldCascadeWindows:NO];
    [self setWindowFrameAutosaveName:@"timer"];
    [self updateButtons];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(jobsUpdated:) name:DBVidiJobsUpdatedNotification object:_vidi];
    [self updateScheduledMinutes];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(selectedJobChanged:) name:DBVidiSelectedJobChangedNotification object:_vidi];
    _updateTimer = [NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(updateTimerFired:) userInfo:nil repeats:YES];

    cleanShortDateFormatString = [NSMutableString string];
    scanner = [NSScanner scannerWithString:[[NSUserDefaults standardUserDefaults] objectForKey:NSShortDateFormatString]];
    
    while ([scanner scanUpToString:@"1" intoString:&tmpString]) {
        [cleanShortDateFormatString appendString:tmpString];
        [scanner scanString:@"1" intoString:nil];
    }

    shortDateFormatter = [[[NSDateFormatter alloc] initWithDateFormat:cleanShortDateFormatString allowNaturalLanguage:YES] autorelease];

    timeFormatter = [[[NSDateFormatter alloc] initWithDateFormat:[[[NSUserDefaults standardUserDefaults] objectForKey:NSTimeFormatString] stringByAppendingString:@"%p"] allowNaturalLanguage:YES] autorelease];

    [startDateField setFormatter:shortDateFormatter];

    _timeFormatString = [[NSUserDefaults standardUserDefaults] objectForKey:NSTimeFormatString];

    // Try to eliminate the seconds component while preserving the user-defined format
    BOOL needsAMPM = NO;
    NSRange hoursRange = [_timeFormatString rangeOfString:@"H"];
    if (hoursRange.location == NSNotFound) {
        hoursRange = [_timeFormatString rangeOfString:@"I"];
        needsAMPM = YES;
    }
    if (hoursRange.location != NSNotFound) {
        if ([[_timeFormatString substringWithRange:NSMakeRange(hoursRange.location + 1, 1)] isEqual:@"%"])
            hoursRange.location--;
        _timeFormatString = [[_timeFormatString substringToIndex:hoursRange.location + 2] stringByAppendingString:@"%M"];
        if (needsAMPM)
            _timeFormatString = [[_timeFormatString stringByAppendingString:@"%p"] retain];
        else
            [_timeFormatString retain];
    }

    _dateFormatString = [[NSUserDefaults standardUserDefaults] objectForKey:NSShortDateFormatString];

    // Try to eliminate the year component while preserving the user-defined format
    NSRange yearRange = [_dateFormatString rangeOfString:@"%y"];
    if (yearRange.location == NSNotFound)
        yearRange = [_dateFormatString rangeOfString:@"%Y"];
    if (yearRange.location != NSNotFound) {
        if (yearRange.location > 0)
            yearRange.location--;
        yearRange.length++;
        _dateFormatString = [[NSString alloc] initWithFormat:@"%@%@", [_dateFormatString substringToIndex:yearRange.location], [_dateFormatString substringFromIndex:yearRange.location+yearRange.length]];
    }
}

- (NSDictionary *)jobFromSheet
{
    NSCalendarDate *startDate;
    NSCalendarDate *startTime = [startTimeField objectValue];
    NSCalendarDate *endDate;
    NSCalendarDate *endTime = [endTimeField objectValue];
    NSMutableDictionary *job;
    int recurrence;
    int day = [dayPopUp indexOfSelectedItem];

    if ([[recurrenceMatrix selectedCell] tag] == 1) {
        if (day == 8)
            recurrence = 1;
        else
            recurrence = 7;
    } else
        recurrence = 0;

    if (recurrence == 0)
        startDate = [startDateField objectValue];
    else {
        startDate = [NSCalendarDate date];
        if (recurrence == 7)
            startDate = [startDate addTimeInterval:60.0 * 60 * 24 * (day - [startDate dayOfWeek])];
    }

    // Now set the time of day on each of the dates
    startDate = [NSCalendarDate dateWithYear:[startDate yearOfCommonEra] month:[startDate monthOfYear] day:[startDate dayOfMonth] hour:[startTime hourOfDay] minute:[startTime minuteOfHour] second:[startTime secondOfMinute] timeZone:[NSTimeZone defaultTimeZone]];
    endDate = [NSCalendarDate dateWithYear:[startDate yearOfCommonEra] month:[startDate monthOfYear] day:[startDate dayOfMonth] hour:[endTime hourOfDay] minute:[endTime minuteOfHour] second:[endTime secondOfMinute] timeZone:[NSTimeZone defaultTimeZone]];

    if ([startDate compare:endDate] != NSOrderedAscending)
        endDate = [endDate addTimeInterval:60 * 60 *24];

    job = [NSMutableDictionary vidiJobWithStartDate:startDate endDate:endDate channel:[DBTVChannel channelWithDictionary:[[channelPopUp selectedItem] representedObject]] file:[fileTextField stringValue] comments:@"" permanent:YES];

    if ([splitCheckbox state])
        [job setObject:[NSNumber numberWithUnsignedInt:DBChunkSize] forKey:DBVidiJobChunkSizeKey];
    if ([overwriteCheckbox state])
        [job setObject:[NSNumber numberWithBool:YES] forKey:DBVidiJobOverwriteKey];
    if (recurrence != 0)
        [job setObject:[NSNumber numberWithInt:recurrence] forKey:DBVidiJobRecurrenceKey];
    if ([[job channel] inputSource] == DBRadioInput) {
        [job setObject:[NSNumber numberWithBool:YES] forKey:DBVidiJobIsAudioKey];
        [job setObject:[_audioFormat objectForKey:DBVidiJobAudioSampleRateKey] forKey:DBVidiJobAudioSampleRateKey];
        [job setObject:[_audioFormat objectForKey:DBVidiJobAudioSampleSizeKey] forKey:DBVidiJobAudioSampleSizeKey];
        [job setObject:[_audioFormat objectForKey:DBVidiJobAudioChannelsKey] forKey:DBVidiJobAudioChannelsKey];
        [job setObject:[_audioFormat objectForKey:DBVidiJobAudioCompressionKey] forKey:DBVidiJobAudioCompressionKey];
        if ([_audioFormat objectForKey:DBVidiJobAudioCompressionParamsKey])
            [job setObject:[_audioFormat objectForKey:DBVidiJobAudioCompressionParamsKey] forKey:DBVidiJobAudioCompressionParamsKey];
    }
    return job;
}

- (void)updateSheetFromJob:(NSDictionary *)job
{
    int recurrence = [job recurrence];
    NSString *file = [job scheduledFile];
    int channelIndex = [channelPopUp indexOfItemWithRepresentedObject:[[job channel] dictionaryWithoutLogo]];

    [startTimeField setObjectValue:[job scheduledStartDate]];
    [endTimeField setObjectValue:[job scheduledEndDate]];
    if (recurrence == 0)
        [startDateField setObjectValue:[job scheduledStartDate]];
    else
        [startDateField setStringValue:@""];
    if (recurrence == 1)
        [dayPopUp selectItemAtIndex:8];	// "every day"
    else
        [dayPopUp selectItemAtIndex:[[job scheduledStartDate] dayOfWeek]];
    [recurrenceMatrix selectCellWithTag:(recurrence != 0)];
    if ([recurrenceMatrix isEnabled])
        [self recurrenceMatrixChanged:recurrenceMatrix];
    [overwriteCheckbox setState:[job overwrite]];
    [fileTextField setStringValue:file ? file : @""];
    [_audioFormat release];
    _audioFormat = [job copy];
    if ([job isAudio]) {
        [splitCheckbox setState:NSOffState];
        [splitCheckbox setEnabled:NO];
    } else {
        [splitCheckbox setState:[job chunkSize] != 0];
        [changeAudioFormatButton setEnabled:NO];
    }
    if (channelIndex == -1) {
        // A channel that is not on the menu
        [[channelPopUp menu] addItem:[NSMenuItem separatorItem]];
        [[[channelPopUp menu] addItemWithTitle:[[job channel] name] action:nil keyEquivalent:@""] setRepresentedObject:[[job channel] dictionaryWithoutLogo]];
        channelIndex = [channelPopUp numberOfItems] - 1;
    }
    [channelPopUp selectItemAtIndex:channelIndex];
    [self updateInfoText];
    [self updateAudioFormatText:[job isAudio]];
}

- (void)updateAudioFormatText:(BOOL)isAudioOnly
{
    [audioFormatTextField setStringValue:isAudioOnly ? [DBAudioCompression descriptionOfFormat:_audioFormat] : NSLocalizedString(@"DV Audio, 32kHz, 16 bits", @"")];
}

- (void)enableSheetControlsForActiveJob:(BOOL)isActive
{
    [startDateField setEnabled:!isActive];
    [startTimeField setEnabled:!isActive];
    [channelPopUp setEnabled:!isActive && [_vidi firmwareVersion] != 0];
    [recurrenceMatrix setEnabled:!isActive];
    [dayPopUp setEnabled:!isActive];
    [selectButton setEnabled:!isActive];
    [overwriteCheckbox setEnabled:!isActive];
    [splitCheckbox setEnabled:!isActive];
    [changeAudioFormatButton setEnabled:!isActive];
}

#pragma mark Timer window actions

- (IBAction)addClicked:(id)sender
{
    NSCalendarDate *now = [NSCalendarDate date];
    DBTVChannel *channel;
    NSMutableDictionary *job;

    channel = [_vidi selectedChannel];

    job = [NSMutableDictionary vidiJobWithStartDate:now endDate:[now addTimeInterval:60*30] channel:channel file:nil comments:nil permanent:YES];

    if ([channel inputSource] == DBRadioInput)
        [job setObject:[NSNumber numberWithBool:YES] forKey:DBVidiJobIsAudioKey];

    [job addEntriesFromDictionary:[[NSUserDefaults standardUserDefaults] objectForKey:DBAudioFormatSettingName]];

    if ([[NSUserDefaults standardUserDefaults] boolForKey:DBSplitMoviesSettingName])
        [job setObject:[NSNumber numberWithUnsignedInt:DBChunkSize] forKey:DBVidiJobChunkSizeKey];

    [self updateChannelPopUp];
    [self enableSheetControlsForActiveJob:NO];
    [self updateSheetFromJob:job];

    [[_vidi server] selectJobAtIndex:-1];
    [NSApp beginSheet:jobSheet modalForWindow:[self window] modalDelegate:self didEndSelector:@selector(jobSheet:endedWithReturnCode:contextInfo:) contextInfo:NULL];
}

- (IBAction)timeFieldChanged:(id)sender
{
    [self updateInfoText];
}

- (IBAction)recurrenceMatrixChanged:(id)sender
{
    BOOL recurring = [[sender selectedCell] tag];

    [startDateField setEnabled:!recurring];
    [dayPopUp setEnabled:recurring];
    [overwriteCheckbox setEnabled:recurring];
    if (!recurring)
        [overwriteCheckbox setState:NSOffState];
}

- (IBAction)editClicked:(id)sender
{
    NSDictionary *job = [_sortedJobs objectAtIndex:[tableView selectedRow]];
    BOOL isActive = [[job status] isEqual:DBVidiJobStatusActive];

    [self updateChannelPopUp];
    [self enableSheetControlsForActiveJob:isActive];
    [[_vidi server] selectJobAtIndex:[[job objectForKey:DBOriginalChannelIndexKey] intValue]];
    [self updateSheetFromJob:job];
    [NSApp beginSheet:jobSheet modalForWindow:[self window] modalDelegate:self didEndSelector:@selector(jobSheet:endedWithReturnCode:contextInfo:) contextInfo:NULL];
}

- (IBAction)removeClicked:(id)sender
{
    [[_vidi server] removeJobAtIndex:[[[_sortedJobs objectAtIndex:[tableView selectedRow]] objectForKey:DBOriginalChannelIndexKey]intValue]];
}

#pragma mark Job sheet actions

- (IBAction)jobOKClicked:(id)sender
{
    [NSApp endSheet:jobSheet returnCode:NSOKButton];
}

- (IBAction)jobCancelClicked:(id)sender
{
    [NSApp endSheet:jobSheet returnCode:NSCancelButton];
}

- (IBAction)changeAudioFormatClicked:(id)sender
{
    NSDictionary *newFormat;

    newFormat = [DBAudioCompression runStandardSoundCompressionDialogWithFormat:_audioFormat];
    if (newFormat) {
        [_audioFormat release];
        _audioFormat = [newFormat retain];
        [self updateAudioFormatText:YES];
    }
}

- (IBAction)takeChannelFrom:(id)sender
{
    DBTVChannel *channel = [DBTVChannel channelWithDictionary:[[sender selectedItem] representedObject]];

    if ([channel inputSource] == DBRadioInput) {
        [splitCheckbox setState:NSOffState];
        [splitCheckbox setEnabled:NO];
        [changeAudioFormatButton setEnabled:YES];
        [self updateAudioFormatText:YES];
        if ([[[fileTextField stringValue] pathExtension] isEqual:@"dv"])
            [fileTextField setStringValue:[[[fileTextField stringValue] stringByDeletingPathExtension] stringByAppendingPathExtension:@"aiff"]];
    } else {
        if (![splitCheckbox isEnabled]) {
            [splitCheckbox setEnabled:YES];
            [splitCheckbox setState:[[NSUserDefaults standardUserDefaults] boolForKey:DBSplitMoviesSettingName]];
        }
        if ([[[fileTextField stringValue] pathExtension] isEqual:@"aiff"])
            [fileTextField setStringValue:[[[fileTextField stringValue] stringByDeletingPathExtension] stringByAppendingPathExtension:@"dv"]];
        [changeAudioFormatButton setEnabled:NO];
        [self updateAudioFormatText:NO];
    }
    [self updateInfoText];
}

- (IBAction)selectFile:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    NSString *directory = [[fileTextField stringValue] stringByDeletingLastPathComponent];
    NSString *file = [[fileTextField stringValue] lastPathComponent];

    if ([directory length] == 0)
        directory = [_vidi moviesDirectory];
    [panel setRequiredFileType:[[DBTVChannel channelWithDictionary:[[channelPopUp selectedItem] representedObject]] inputSource] == DBRadioInput ? @"aiff" : @"dv"];
    [panel setPrompt:NSLocalizedString(@"Select", @"prompt for file selection panel")];
    [panel setTitle:NSLocalizedString(@"Record To", @"title for file selection panel")];
    if ([panel runModalForDirectory:directory file:file]) {
        [fileTextField setStringValue:[panel filename]];
        [self updateInfoText];
    }
}

- (void)jobSheet:(NSWindow *)sheet endedWithReturnCode:(int)returnCode contextInfo:(void *)contextInfo
{
    [sheet orderOut:nil];
    if (returnCode == NSOKButton)
        [[_vidi server] replaceSelectedJobWith:[self jobFromSheet]];
    [[_vidi server] selectJobAtIndex:-1];
}

#pragma mark

- (NSMenu *)menuWithChannels
{
    NSArray *channels = [_vidi _privateChannels];
    int count = [channels count];
    int i;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    for (i = 0; i<count; i++)
        [[menu addItemWithTitle:[[channels objectAtIndex:i] name] action:nil keyEquivalent:@""] setRepresentedObject:[[channels objectAtIndex:i] dictionaryWithoutLogo]];
    return [menu autorelease];
}

- (void)updateChannelPopUp
{
    [channelPopUp selectItemAtIndex:-1];
    [channelPopUp setMenu:[self menuWithChannels]];
}

- (void)jobsUpdated:(NSNotification *)notification
{
    [self updateSortedJobs];
    [tableView reloadData];
    [self updateScheduledMinutes];
    [self updateButtons];
}

- (void)selectedJobChanged:(NSNotification *)notification
{
    NSDictionary *job = [[_vidi server] selectedJob];
    NSString *status = [job status];
    if ([status isEqual:DBVidiJobStatusScheduled] || [status isEqual:DBVidiJobStatusActive]) {
        [self enableSheetControlsForActiveJob:[status isEqual:DBVidiJobStatusActive]];
        [self updateSheetFromJob:[[_vidi server] selectedJob]];
    } else
        [self jobCancelClicked:nil];
}

#pragma mark Job sheet

- (void)updateInfoText
{
    NSString *path;
    NSDictionary *attributes;
    NSString *volumeName;
    NSString *timeToBeRecorded;
    NSString *spaceRequired;
    NSString *spaceAvailable;
    int minutes;
    UInt64 bytes;
    UInt64 availableBytes;
    NSString *infoText;
    NSImage *infoImage;

    minutes = 60 * ([[endTimeField objectValue] hourOfDay] - [[startTimeField objectValue] hourOfDay]) + ([[endTimeField objectValue] minuteOfHour] - [[startTimeField objectValue] minuteOfHour]);
    while (minutes <= 0)
        minutes += 1440;
    while (minutes > 1440)
        minutes -= 1440;
    bytes = (unsigned long long)minutes * 60 * 3600000;

    timeToBeRecorded = (minutes == 1 ? NSLocalizedString(@"1 minute to be recorded", nil) : [NSString stringWithFormat:NSLocalizedString(@"%d minutes to be recorded", nil), minutes]);

    if ([[DBTVChannel channelWithDictionary:[[channelPopUp selectedItem] representedObject]] inputSource] == DBRadioInput) {
        infoText = [NSString stringWithFormat:@"%@.", timeToBeRecorded];
        infoImage = nil;
    } else {
        path = [fileTextField stringValue];
        if ([path isEqual:@""])
            path = [_vidi moviesDirectory];
        else
            path = [path stringByDeletingLastPathComponent];
        attributes = [[NSFileManager defaultManager] fileSystemAttributesAtPath:path];
        volumeName = [[[NSFileManager defaultManager] componentsToDisplayForPath:path] objectAtIndex:0];
        spaceRequired = (bytes < 1024*1024*1024 ? [NSString stringWithFormat:@"%d MB", (int)(bytes / 1024 / 1024)] : [NSString stringWithFormat:@"%.2f GB", (bytes / 1024.0 / 1024.0 / 1024.0)]);

        availableBytes = [[attributes objectForKey:@"NSFileSystemFreeSize"] unsignedLongLongValue];

        spaceAvailable = (availableBytes < 1024*1024*1024 ? [NSString stringWithFormat:@"%d MB", (int)(availableBytes / 1024 / 1024)] :[NSString stringWithFormat:@"%.2f GB", (availableBytes / 1024.0 / 1024.0 / 1024.0)]);

        infoText = [NSString
stringWithFormat:NSLocalizedString( @"%@, which will require about %@ on %@. %@ currently available.", nil ), timeToBeRecorded, spaceRequired, volumeName, spaceAvailable];
        infoImage = (availableBytes < bytes + [[NSUserDefaults standardUserDefaults] integerForKey:DBMegabytesToReserveSettingName] * 1024 * 1024 ? [NSImage imageNamed:@"caution"] : nil);
    }
    [infoTextField setStringValue:infoText];
    [cautionImage setImage:infoImage];
}

#pragma mark Main window

- (void)updateSortedJobs
{
    NSMutableArray *jobs = [[[_vidi server] jobs] mutableCopy];
    int count = [jobs count];
    int i;
    for (i = 0; i<count; i++)
        [[jobs objectAtIndex:i] setObject:[NSNumber numberWithInt:i] forKey:DBOriginalChannelIndexKey];
    [jobs sortUsingSelector:@selector(compareToVidiJob:)];
    [_sortedJobs autorelease];
    _sortedJobs = [jobs retain];
}

- (void)updateTimerFired:(NSTimer *)timer
{
    [self updateScheduledMinutes];
}

- (void)updateScheduledMinutes
{
    NSDictionary *job;
    NSEnumerator *jobEnumerator;
    NSTimeInterval seconds = 0;
    NSString *status;
    NSString *scheduledMinutesString;

    jobEnumerator = [_sortedJobs objectEnumerator];
    while (job = [jobEnumerator nextObject]) {
        status = [job status];
        if (([status isEqual:DBVidiJobStatusScheduled] || [status isEqual:DBVidiJobStatusActive])
            && ![[job scheduledEndDate] isEqual:[NSCalendarDate distantFuture]])
            seconds += [[job scheduledEndDate] timeIntervalSinceDate:[[job scheduledStartDate] laterDate:[NSDate date]]];
    }
    if (seconds > 60)
        scheduledMinutesString = [NSString stringWithFormat:NSLocalizedString( @"About %d minutes to be recorded", nil), (int)((seconds + 59) / 60)];
    else if (seconds > 0)
        scheduledMinutesString = NSLocalizedString(@"Less than a minute to be recorded", nil);
    else
        scheduledMinutesString = @"";
    [scheduledMinutesTextField setStringValue:scheduledMinutesString];
}

- (void)updateButtons
{
    int i = [tableView numberOfSelectedRows];
    [removeButton setEnabled:(i == 1)];
    if (i == 1) {
        NSString *jobStatus = [(NSDictionary *)[_sortedJobs objectAtIndex:[tableView selectedRow]] status];
        [editButton setEnabled:[jobStatus isEqual:DBVidiJobStatusActive] || [jobStatus isEqual:DBVidiJobStatusScheduled]];
    } else
        [editButton setEnabled:NO];
}

#pragma mark NSObject (NSTableDataSource)

- (int)numberOfRowsInTableView:(NSTableView *)tableView
{
    return [_sortedJobs count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(int)row;
{
    NSDictionary *job = [_sortedJobs objectAtIndex:row];
    NSString *column = [tableColumn identifier];
    NSString *status = [job status];

    if ([column isEqual:DBTimerStatusColumnIdentifier]) {
        if ([status isEqual:DBVidiJobStatusScheduled] )
            return NSLocalizedString(@"Scheduled", nil);
        if ([status isEqual:DBVidiJobStatusUnscheduled])
            return NSLocalizedString(@"Unscheduled", nil);
        if ([status isEqual:DBVidiJobStatusActive])
            return NSLocalizedString(@"Active", nil);
        if ([status isEqual:DBVidiJobStatusCompleted])
            return NSLocalizedString(@"Finished", nil);
        if ([status isEqual:DBVidiJobStatusAbended])
            return NSLocalizedString(@"Error", nil);
    }

    if ([column isEqual:DBTimerChannelColumnIdentifier])
        return [[job channel] name];

    if ([column isEqual:DBTimerFileColumnIdentifier]) {
        NSString *file = nil;
        if ([status isEqual:DBVidiJobStatusCompleted] || [status isEqual:DBVidiJobStatusActive] || [status isEqual:DBVidiJobStatusAbended]) 
            file = [job actualFile];
        if (!file)
            file = [job scheduledFile];
        return [file lastPathComponent];
    }

    if ([column isEqual:DBTimerStartColumnIdentifier]) {
        NSDate *startDate = nil;
        if ([status isEqual:DBVidiJobStatusCompleted] || [status isEqual:DBVidiJobStatusActive] || [status isEqual:DBVidiJobStatusAbended]) 
            startDate = [job actualStartDate];
        if (!startDate)
            startDate = [job scheduledStartDate];
        return [startDate descriptionWithCalendarFormat:_timeFormatString timeZone:nil locale:nil];
    }

    if ([column isEqual:DBTimerEndColumnIdentifier]) {
        NSDate *endDate = nil;
        if ([status isEqual:DBVidiJobStatusCompleted] || [status isEqual:DBVidiJobStatusActive] || [status isEqual:DBVidiJobStatusAbended])
            endDate = [job actualEndDate];
        if (!endDate)
            endDate = [job scheduledEndDate];
        if ([endDate isEqual:[NSCalendarDate distantFuture]])
            return @"--";
        else
            return [endDate descriptionWithCalendarFormat:_timeFormatString timeZone:nil locale:nil];
    }

    if ([column isEqual:DBTimerDateColumnIdentifier]) {
        NSDate *startDate = nil;
        int recurrence = [job recurrence];
        if (recurrence == 0 && ([status isEqual:DBVidiJobStatusCompleted] || [status isEqual:DBVidiJobStatusActive] || [status isEqual:DBVidiJobStatusAbended]))
            startDate = [job actualStartDate];
        if (!startDate)
            startDate = [job scheduledStartDate];
        switch (recurrence) {
            case 1:
                return NSLocalizedString(@"Daily", @"start date substitute in Recording Schedule for recurring job");
                break;
            case 7:
                return [startDate descriptionWithCalendarFormat:@"%a" timeZone:nil locale:nil];
                break;
            default:
                return [startDate descriptionWithCalendarFormat:_dateFormatString timeZone:nil locale:nil];
                break;
        }
    }
    return @"";
}

#pragma mark NSObject (NSTableViewDelegate)

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    [self updateButtons];
}

@end
