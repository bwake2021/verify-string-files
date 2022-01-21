//
//  main.m
//  verify-string-files
//
//  Created by Daniel Kennett on 22/08/14.
//  For license information, see LICENSE.markdown

#import <Foundation/Foundation.h>

#pragma mark - Usage

void printUsage() {

    NSString *processName = [[NSProcessInfo processInfo] processName];

    printf("%s by Daniel Kennett\n\n", processName.UTF8String);

	printf("Verifies that localizations of the given strings file contain all\n");
	printf("the master .strings file's keys. Intended to be used with an Xcode\n");
	printf("custom build step. \n\n");

	printf("Usage: %s -master <strings file path>\n", processName.UTF8String);
	printf("       %s [-warning-level <error | warning | note>] \n\n", [@"" stringByPaddingToLength:processName.length
																					withString:@" "
																			   startingAtIndex:0].UTF8String);

	printf("  -master         The path to a valid .strings file. Should be\n");
	printf("                  localized (that is, inside an .lproj folder),\n");
	printf("                  and what's considered the \"base\" strings file\n");
	printf("                  for the project.\n\n");

    printf("  -warning-level  The warning level to use: error, warning or note. \n");
    printf("                  Defaults to error.\n");

    printf("\n\n");
}

#pragma mark - Finding Other Files

/** Returns a dictionary of full strings files paths keyed be language code */
NSDictionary *stringsFilesMatchingMasterPath(NSString *masterPath) {

	NSString *basePath = nil;
	NSString *lProjSubPath = nil;

	NSMutableArray *subPathComponents = [NSMutableArray new];
	[subPathComponents addObject:[masterPath lastPathComponent]];

	while (YES) {

		masterPath = [masterPath stringByDeletingLastPathComponent];
		if ([[[masterPath lastPathComponent] pathExtension] caseInsensitiveCompare:@"lproj"] == NSOrderedSame) {
			basePath = [masterPath stringByDeletingLastPathComponent];
			lProjSubPath = [subPathComponents componentsJoinedByString:@"/"];
			break;
		} else {
			[subPathComponents insertObject:[masterPath lastPathComponent] atIndex:0];
		}
	}

	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtPath:basePath];
	NSMutableDictionary *stringsFiles = [NSMutableDictionary new];

	NSString *baseFileName = nil;
	while ((baseFileName = [enumerator nextObject])) {

		NSString *baseFilePath = [basePath stringByAppendingPathComponent:baseFileName];
		if ([baseFilePath caseInsensitiveCompare:masterPath] == NSOrderedSame) {
			// Skip original file
			continue;
		}

		BOOL isDirectory = NO;
		[fileManager fileExistsAtPath:baseFilePath isDirectory:&isDirectory];

		if (isDirectory && [[baseFileName pathExtension] caseInsensitiveCompare:@"lproj"] == NSOrderedSame) {

			NSString *stringsFilePath = [baseFilePath stringByAppendingPathComponent:lProjSubPath];
			if ([fileManager fileExistsAtPath:stringsFilePath]) {
				[stringsFiles setObject:stringsFilePath forKey:baseFileName];
			}
		}

		if (isDirectory) {
			[enumerator skipDescendants];
		}
	}

	if (stringsFiles.count > 0) {
		return [NSDictionary dictionaryWithDictionary:stringsFiles];
	} else {
		return nil;
	}
}

NSDictionary *contentsOfStringsFile(NSString *filePath) {

	NSError *error = nil;
	NSData *plistData = [NSData dataWithContentsOfFile:filePath
											   options:0
												 error:&error];

	if (error != nil) {
		printf("ERROR: Reading file failed with error: %s\n", error.localizedDescription.UTF8String);
		exit(EXIT_FAILURE);
	}

	id plist = [NSPropertyListSerialization propertyListWithData:plistData
														 options:0
														  format:nil
														   error:&error];

	if (error != nil) {
		printf("ERROR: Reading file failed with error: %s\n", error.localizedDescription.UTF8String);
		exit(EXIT_FAILURE);
	}

	if (![plist isKindOfClass:[NSDictionary class]]) {
		printf("ERROR: Strings file contained unexpected root object type.");
		exit(EXIT_FAILURE);
	}

	return plist;
}

NSDictionary *otherStringsFiles(NSString *masterPath) {

	NSDictionary *otherStringsFilePaths = stringsFilesMatchingMasterPath(masterPath);
	NSMutableDictionary *stringsFileContents = [NSMutableDictionary new];

	for (NSString *language in otherStringsFilePaths) {

		NSDictionary *strings = contentsOfStringsFile(otherStringsFilePaths[language]);
		if (strings) {
			[stringsFileContents setObject:strings forKey:language];
		}
	}

	if (stringsFileContents.count > 0) {
		return [NSDictionary dictionaryWithDictionary:stringsFileContents];
	} else {
		return nil;
	}
}

NSArray *checkKey(NSString *masterKey, NSDictionary *othersByLanguage) {

    NSMutableArray *missingLanguages = [NSMutableArray new];

    for (NSString *language in othersByLanguage) {

        NSDictionary *otherStrings = othersByLanguage[language];
        if (otherStrings[masterKey] == nil) {
            [missingLanguages addObject:language];
        }
    }

    return missingLanguages;
}

NSDictionary *checkForMissingKeys(NSDictionary *master, NSDictionary *othersByLanguage) {

    /** Arrays of languages missing by language key */
    NSMutableDictionary *problems = [NSMutableDictionary new];

    for (NSString *masterKey in master) {

        NSArray *missingLanguages = checkKey(masterKey, othersByLanguage);

        if (missingLanguages.count > 0) {
            problems[masterKey] = missingLanguages;
        }

    }

    if (problems.count > 0) {
        return [NSDictionary dictionaryWithDictionary: problems];
    } else {
        return nil;
    }
}

/// Rough-and-ready format count character count
int countFormats(NSString *string) {

    int count = 0;
    unsigned long len = string.length;
    for (int i = 0; i < len; ++i) {

        unichar c = [string characterAtIndex:i];
        if ('@' == c || '%' == c) {
            ++count;
        }
    }
    return count;
}

NSArray *checkFormat(NSString *masterKey, NSString *masterFormat, NSDictionary *othersByLanguage) {

    NSMutableArray *formatMismatch = [NSMutableArray new];

    int masterCount = countFormats(masterFormat);
    for (NSString *language in othersByLanguage) {

        NSDictionary *otherStrings = othersByLanguage[language];
        NSString *otherString = otherStrings[masterKey];
        if (otherString != nil && countFormats(otherString) != masterCount) {
            [formatMismatch addObject:language];
        }
    }

    return formatMismatch;
}

NSDictionary *checkForFormatMismatch(NSDictionary *master, NSDictionary *othersByLanguage) {

	/** Arrays of languages with mismatched format character counts */
	NSMutableDictionary *problems = [NSMutableDictionary new];

	for	(NSString *masterKey in master) {

        NSArray *formatMismatch = checkFormat(masterKey, master[masterKey], othersByLanguage);

		if (formatMismatch.count > 0) {
			problems[masterKey] = formatMismatch;
		}
	}

	if (problems.count > 0) {
		return [NSDictionary dictionaryWithDictionary: problems];
	} else {
		return nil;
	}
}

NSArray *checkTranslation(NSString *masterKey, NSString *masterString, NSDictionary *othersByLanguage) {

    NSMutableArray *stringMatches = [NSMutableArray new];

    for (NSString *language in othersByLanguage) {

        NSDictionary *otherStrings = othersByLanguage[language];
        NSString *otherString = otherStrings[masterKey];
        if (otherString != nil && NSOrderedSame == [otherString caseInsensitiveCompare: masterString]) {
            [stringMatches addObject:language];
        }
    }

    return stringMatches;
}


NSDictionary *checkForTranslation(NSDictionary *master, NSDictionary *othersByLanguage) {

    /** Arrays of languages with mismatched format character counts */
    NSMutableDictionary *problems = [NSMutableDictionary new];

    for (NSString *masterKey in master) {

        NSArray *stringMatches = checkTranslation(masterKey, master[masterKey], othersByLanguage);

        if (stringMatches.count > 0) {
            problems[masterKey] = stringMatches;
        }
    }

    if (problems.count > 0) {
        return [NSDictionary dictionaryWithDictionary: problems];
    } else {
        return nil;
    }
}

NSDictionary *dictionaryOfKeyLines(NSString *stringsFilePath) {

    NSMutableDictionary *keyLines = [NSMutableDictionary new];

    NSString *fileContents = [[NSString alloc] initWithContentsOfFile:stringsFilePath usedEncoding:nil error:nil];

    if (fileContents.length == 0) {
        return nil;
    }

    NSArray *lines = [fileContents componentsSeparatedByString:@"\n"];

    for (NSUInteger lineIndex = 0; lineIndex < lines.count; lineIndex++) {
        NSString *keyString = [lines[lineIndex] componentsSeparatedByString: @"="][0];
        keyString = [keyString stringByTrimmingCharactersInSet: NSCharacterSet.whitespaceCharacterSet];
        NSUInteger keyStringLen = keyString.length;
        if (2 < keyStringLen && '\"' == [keyString characterAtIndex: 0] && '\"' == [keyString characterAtIndex: keyStringLen - 1]) {

            keyString = [keyString substringWithRange: NSMakeRange(1, keyString.length - 2)];

            keyLines[keyString] = [NSNumber numberWithUnsignedLong: lineIndex + 1];
        }
    }

    return keyLines;
}

#pragma mark - Output

NSUInteger lineNumberForKeyInStringsFile(NSString *key, NSString *stringsFilePath) {

	static NSMutableDictionary *stringsFileCache = nil;

	if (stringsFileCache == nil) {
		stringsFileCache = [NSMutableDictionary new];
	}

    NSDictionary *keyLines = stringsFileCache[stringsFilePath];
    if (nil == keyLines) {
        keyLines = dictionaryOfKeyLines(stringsFilePath);
    }

    if (nil != keyLines) {
        NSNumber *lineForKey = [keyLines objectForKey: key];
        if (Nil != lineForKey) {

            return lineForKey.unsignedLongValue;
        }
    }

	return 1;
}

void logMissingKeys(NSString *masterStringsFilePath, NSDictionary *missingKeys, NSString *warningLevel) {

	for (NSString *masterKey in missingKeys) {

		NSUInteger keyLine = lineNumberForKeyInStringsFile(masterKey, masterStringsFilePath);
		NSArray *missingLanguages = missingKeys[masterKey];

		for (NSString *language in missingLanguages) {
			fprintf(stderr, "%s:%lu: %s: %s is missing in %s\n",
					masterStringsFilePath.UTF8String,
					(unsigned long)keyLine,
					warningLevel.UTF8String,
					masterKey.UTF8String,
					language.UTF8String);
		}
	}
}

void logFormatMismatch(NSString *masterStringsFilePath, NSDictionary *mismatchedFormats, NSString *warningLevel) {

    for (NSString *masterKey in mismatchedFormats) {

        NSUInteger keyLine = lineNumberForKeyInStringsFile(masterKey, masterStringsFilePath);
        NSArray *missingLanguages = mismatchedFormats[masterKey];

        for (NSString *language in missingLanguages) {
            fprintf(stderr, "%s:%lu: %s: %s does not match format specifiers in %s\n",
                    masterStringsFilePath.UTF8String,
                    (unsigned long)keyLine,
                    warningLevel.UTF8String,
                    masterKey.UTF8String,
                    language.UTF8String);
        }
    }
}

void logPossibleMissingTranslation(NSString *masterStringsFilePath, NSDictionary *mismatchedFormats, NSString *warningLevel) {

    for (NSString *masterKey in mismatchedFormats) {

        NSUInteger keyLine = lineNumberForKeyInStringsFile(masterKey, masterStringsFilePath);
        NSArray *missingLanguages = mismatchedFormats[masterKey];

        for (NSString *language in missingLanguages) {
            fprintf(stderr, "%s:%lu: %s: %s possible missing translation in %s\n",
                    masterStringsFilePath.UTF8String,
                    (unsigned long)keyLine,
                    warningLevel.UTF8String,
                    masterKey.UTF8String,
                    language.UTF8String);
        }
    }
}

#pragma mark - Main

BOOL warningLevelIsValid(NSString *warningLevel) {
	return [warningLevel isEqualToString:@"error"] ||
	[warningLevel isEqualToString:@"warning"] ||
	[warningLevel isEqualToString:@"note"];
}

int main(int argc, const char * argv[])
{

    @autoreleasepool {

        NSString *inputFilePath = [[NSUserDefaults standardUserDefaults] valueForKey:@"master"];
		NSString *warningLevel = [[NSUserDefaults standardUserDefaults] valueForKey:@"warning-level"];
		if (warningLevel.length == 0) {
			warningLevel = @"error";
		}
        NSString *newWarningLevel = @"warning";

        setbuf(stdout, NULL);

        if (inputFilePath.length == 0 || !warningLevelIsValid(warningLevel)) {
            printUsage();
            exit(EXIT_FAILURE);
        }

        if (![[NSFileManager defaultManager] fileExistsAtPath:inputFilePath]) {
            printf("ERROR: Input file %s doesn't exist.\n", [inputFilePath UTF8String]);
            exit(EXIT_FAILURE);
        }

		NSDictionary *masterStrings = contentsOfStringsFile(inputFilePath);
		NSDictionary *otherStrings = otherStringsFiles(inputFilePath);

		NSDictionary *missingKeys = checkForMissingKeys(masterStrings, otherStrings);
		logMissingKeys(inputFilePath, missingKeys, warningLevel);

        NSDictionary *formatMismatches = checkForFormatMismatch(masterStrings, otherStrings);
        logFormatMismatch(inputFilePath, formatMismatches, newWarningLevel);

        NSDictionary *stringMatches = checkForTranslation(masterStrings, otherStrings);
        logPossibleMissingTranslation(inputFilePath, stringMatches, newWarningLevel);

        exit(EXIT_SUCCESS);
    }
    return 0;
}
