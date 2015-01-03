#!/usr/bin/perl
####################################################################################################################################
# FileTest.pl - Unit Tests for BackRest::File
####################################################################################################################################
package BackRestTest::FileTest;

####################################################################################################################################
# Perl includes
####################################################################################################################################
use strict;
use warnings;
use Carp;

use File::Basename;
use Cwd 'abs_path';
use File::stat;
use Fcntl ':mode';
use Scalar::Util 'blessed';

use lib dirname($0) . '/../lib';
use BackRest::Utility;
use BackRest::File;
use BackRest::Remote;

use BackRestTest::CommonTest;

use Exporter qw(import);
our @EXPORT = qw(BackRestTestFile_Test);

my $strTestPath;
my $strHost;
my $strUserBackRest;

####################################################################################################################################
# BackRestTestFile_Setup
####################################################################################################################################
sub BackRestTestFile_Setup
{
    my $bPrivate = shift;
    my $bDropOnly = shift;

    # Remove the backrest private directory
    if (-e "${strTestPath}/private")
    {
        system("ssh ${strUserBackRest}\@${strHost} 'rm -rf ${strTestPath}/private'");
    }

    # Remove the test directory
    system("rm -rf ${strTestPath}") == 0 or die 'unable to drop test path';

    if (!defined($bDropOnly) || !$bDropOnly)
    {
        # Create the test directory
        mkdir($strTestPath, oct('0770')) or confess 'Unable to create test directory';

        # Create the backrest private directory
        if (defined($bPrivate) && $bPrivate)
        {
            system("ssh backrest\@${strHost} 'mkdir -m 700 ${strTestPath}/private'") == 0 or die 'unable to create test/private path';
        }
    }
}

####################################################################################################################################
# BackRestTestFile_Test
####################################################################################################################################
sub BackRestTestFile_Test
{
    my $strTest = shift;

    # If no test was specified, then run them all
    if (!defined($strTest))
    {
        $strTest = 'all';
    }

    # Setup test variables
    my $iRun;
    $strTestPath = BackRestTestCommon_TestPathGet();
    my $strStanza = BackRestTestCommon_StanzaGet();
    my $strUser = BackRestTestCommon_UserGet();
    my $strGroup = BackRestTestCommon_GroupGet();
    $strHost = BackRestTestCommon_HostGet();
    $strUserBackRest = BackRestTestCommon_UserBackRestGet();

    # Print test banner
    &log(INFO, 'FILE MODULE ********************************************************************');

    #-------------------------------------------------------------------------------------------------------------------------------
    # Create remote
    #-------------------------------------------------------------------------------------------------------------------------------
    my $oRemote = new BackRest::Remote
    (
        $strHost,
        $strUser,
        BackRestTestCommon_CommandRemoteGet()
    );

    #-------------------------------------------------------------------------------------------------------------------------------
    # Test path_create()
    #-------------------------------------------------------------------------------------------------------------------------------
    if ($strTest eq 'all' || $strTest eq 'path_create')
    {
        $iRun = 0;

        &log(INFO, "Test File->path_create()\n");

        # Loop through local/remote
        for (my $bRemote = 0; $bRemote <= 1; $bRemote++)
        {
            # Create the file object
            my $oFile = new BackRest::File
            (
                $strStanza,
                $strTestPath,
                $bRemote ? 'backup' : undef,
                $bRemote ? $oRemote : undef
            );

            # Loop through error
            for (my $bError = 0; $bError <= 1; $bError++)
            {
            # Loop through permission (permission will be set on true)
            for (my $bPermission = 0; $bPermission <= 1; $bPermission++)
            {
                my $strPathType = PATH_BACKUP_CLUSTER;

                # Increment the run, log, and decide whether this unit test should be run
                if (!BackRestTestCommon_Run(++$iRun,
                                            "rmt ${bRemote}, err ${bError}, prm ${bPermission}")) {next}

                # Setup test directory
                BackRestTestFile_Setup($bError);

                mkdir("${strTestPath}/backup") or confess 'Unable to create test/backup directory';
                mkdir("${strTestPath}/backup/db") or confess 'Unable to create test/backup/db directory';

                my $strPath = 'path';
                my $strPermission;

                # If permission then set one (other than the default)
                if ($bPermission)
                {
                    $strPermission = '0700';
                }

                # If not exists then set the path to something bogus
                if ($bError)
                {
                    $strPath = "${strTestPath}/private/path";
                    $strPathType = PATH_BACKUP_ABSOLUTE;
                }

                # Execute in eval to catch errors
                my $bErrorExpected = $bError;

                eval
                {
                    $oFile->path_create($strPathType, $strPath, $strPermission);
                };

                # Check for errors
                if ($@)
                {
                    # Ignore errors if the path did not exist
                    if ($bErrorExpected)
                    {
                        next;
                    }

                    confess "error raised: " . $@ . "\n";
                }

                if ($bErrorExpected)
                {
                    confess 'error was expected';
                }

                # Make sure the path was actually created
                my $strPathCheck = $oFile->path_get($strPathType, $strPath);

                unless (-e $strPathCheck)
                {
                    confess 'path was not created';
                }

                # Check that the permissions were set correctly
                my $oStat = lstat($strPathCheck);

                if (!defined($oStat))
                {
                    confess "unable to stat ${strPathCheck}";
                }

                if ($bPermission)
                {
                    if ($strPermission ne sprintf('%04o', S_IMODE($oStat->mode)))
                    {
                        confess "permissions were not set to {$strPermission}";
                    }
                }
            }
            }
        }
    }

    #-------------------------------------------------------------------------------------------------------------------------------
    # Test move()
    #-------------------------------------------------------------------------------------------------------------------------------
    if ($strTest eq 'all' || $strTest eq 'move')
    {
        $iRun = 0;

        &log(INFO, '--------------------------------------------------------------------------------');
        &log(INFO, "Test File->move()\n");

        for (my $bRemote = 0; $bRemote <= 0; $bRemote++)
        {
            # Create the file object
            my $oFile = (new BackRest::File
            (
                $strStanza,
                $strTestPath,
                $bRemote ? 'backup' : undef,
                $bRemote ? $oRemote : undef
            ))->clone(1);

            # Loop through source exists
            for (my $bSourceExists = 0; $bSourceExists <= 1; $bSourceExists++)
            {
            # Loop through source errors
            for (my $bSourceError = 0; $bSourceError <= 1; $bSourceError++)
            {
            # Loop through destination exists
            for (my $bDestinationExists = 0; $bDestinationExists <= 1; $bDestinationExists++)
            {
            # Loop through source errors
            for (my $bDestinationError = 0; $bDestinationError <= 1; $bDestinationError++)
            {
            # Loop through create
            for (my $bCreate = 0; $bCreate <= $bDestinationExists; $bCreate++)
            {
                # Increment the run, log, and decide whether this unit test should be run
                if (!BackRestTestCommon_Run(++$iRun,
                                            "src_exists ${bSourceExists}, src_error ${bSourceError}, " .
                                            ", dst_exists ${bDestinationExists}, dst_error ${bDestinationError}, " .
                                            "dst_create ${bCreate}")) {next}

                # Setup test directory
                BackRestTestFile_Setup($bSourceError || $bDestinationError);

                my $strSourceFile = "${strTestPath}/test.txt";
                my $strDestinationFile = "${strTestPath}/test-dest.txt";

                if ($bSourceError)
                {
                    $strSourceFile = "${strTestPath}/private/test.txt";
                }
                elsif ($bSourceExists)
                {
                    system("echo 'TESTDATA' > ${strSourceFile}");
                }

                if ($bDestinationError)
                {
                    $strSourceFile = "${strTestPath}/private/test.txt";
                }
                elsif (!$bDestinationExists)
                {
                    $strDestinationFile = "${strTestPath}/sub/test-dest.txt";
                }

                # Execute in eval in case of error
                eval
                {
                    $oFile->move(PATH_BACKUP_ABSOLUTE, $strSourceFile, PATH_BACKUP_ABSOLUTE, $strDestinationFile, $bCreate);
                };

                if ($@)
                {
                    if (!$bSourceExists || (!$bDestinationExists && !$bCreate) || $bSourceError || $bDestinationError)
                    {
                        next;
                    }

                    confess 'error raised: ' . $@ . "\n";
                }

                if (!$bSourceExists || (!$bDestinationExists && !$bCreate) || $bSourceError || $bDestinationError)
                {
                    confess 'error should have been raised';
                }

                unless (-e $strDestinationFile)
                {
                    confess 'file was not moved';
                }
            }
            }
            }
            }
            }
        }
    }

    #-------------------------------------------------------------------------------------------------------------------------------
    # Test compress()
    #-------------------------------------------------------------------------------------------------------------------------------
    if ($strTest eq 'all' || $strTest eq 'compress')
    {
        $iRun = 0;

        &log(INFO, '--------------------------------------------------------------------------------');
        &log(INFO, "Test File->compress()\n");

        for (my $bRemote = 0; $bRemote <= 0; $bRemote++)
        {
            # Create the file object
            my $oFile = new BackRest::File
            (
                $strStanza,
                $strTestPath,
                $bRemote ? 'backup' : undef,
                $bRemote ? $oRemote : undef
            );

            # Loop through exists
            for (my $bExists = 0; $bExists <= 1; $bExists++)
            {
            for (my $bError = 0; $bError <= 1; $bError++)
            {
                if (!BackRestTestCommon_Run(++$iRun,
                                            "rmt ${bRemote}, exists ${bExists}, err ${bError}")) {next}

                # Setup test directory
                BackRestTestFile_Setup($bError);

                my $strFile = "${strTestPath}/test.txt";
                my $strSourceHash;

                if ($bError)
                {
                    $strFile = "${strTestPath}/private/test.txt";
                }
                elsif ($bExists)
                {
                    system("echo 'TESTDATA' > ${strFile}");
                    $strSourceHash = $oFile->hash(PATH_BACKUP_ABSOLUTE, $strFile);
                }

                # Execute in eval in case of error
                eval
                {
                    $oFile->compress(PATH_BACKUP_ABSOLUTE, $strFile);
                };

                if ($@)
                {
                    if (!$bExists || $bError)
                    {
                        next;
                    }

                    confess 'error raised: ' . $@ . "\n";
                }

                if (!$bExists || $bError)
                {
                    confess 'expected error';
                }

                my $strDestinationFile = $strFile . '.gz';

                if (-e $strFile)
                {
                    confess 'source file still exists';
                }

                unless (-e $strDestinationFile)
                {
                    confess 'file was not compressed';
                }

                system("gzip -d ${strDestinationFile}") == 0 or die "could not decompress ${strDestinationFile}";

                my $strDestinationHash = $oFile->hash(PATH_BACKUP_ABSOLUTE, $strFile);

                if ($strSourceHash ne $strDestinationHash)
                {
                    confess "source ${strSourceHash} and destination ${strDestinationHash} file hashes do not match";
                }
            }
            }
        }
    }

    #-------------------------------------------------------------------------------------------------------------------------------
    # Test manifest()
    #-------------------------------------------------------------------------------------------------------------------------------
    if ($strTest eq 'all' || $strTest eq 'manifest')
    {
        $iRun = 0;

        &log(INFO, '--------------------------------------------------------------------------------');
        &log(INFO, "Test File->manifest()\n");

        my $strManifestCompare =
            ".,d,${strUser},${strGroup},0770,,,,,\n" .
            "sub1,d,${strUser},${strGroup},0750,,,,,\n" .
            "sub1/sub2,d,${strUser},${strGroup},0750,,,,,\n" .
            "sub1/sub2/test,l,${strUser},${strGroup},,,,,../..,\n" .
            "sub1/sub2/test-hardlink.txt,f,${strUser},${strGroup},1640,1111111111,0,9,,\n" .
            "sub1/sub2/test-sub2.txt,f,${strUser},${strGroup},0666,1111111113,0,11,,\n" .
            "sub1/test,l,${strUser},${strGroup},,,,,..,\n" .
            "sub1/test-hardlink.txt,f,${strUser},${strGroup},1640,1111111111,0,9,,\n" .
            "sub1/test-sub1.txt,f,${strUser},${strGroup},0646,1111111112,0,10,,\n" .
            "test.txt,f,${strUser},${strGroup},1640,1111111111,0,9,,";

        for (my $bRemote = 0; $bRemote <= 1; $bRemote++)
        {
            # Create the file object
            my $oFile = new BackRest::File
            (
                $strStanza,
                $strTestPath,
                $bRemote ? 'backup' : undef,
                $bRemote ? $oRemote : undef
            );

            for (my $bError = 0; $bError <= 1; $bError++)
            {
            for (my $bExists = 0; $bExists <= 1; $bExists++)
            {
            for (my $bPause = false; $bPause <= $bExists && !$bError; $bPause++)
            {
                if (!BackRestTestCommon_Run(++$iRun,
                                            "rmt ${bRemote}, exists ${bExists}, pause ${bPause}, err ${bError}")) {next}

                # Setup test directory
                BackRestTestFile_Setup($bError);

                # Setup test data
                system("mkdir -m 750 ${strTestPath}/sub1") == 0 or confess 'Unable to create test directory';
                system("mkdir -m 750 ${strTestPath}/sub1/sub2") == 0 or confess 'Unable to create test directory';

                system("echo 'TESTDATA' > ${strTestPath}/test.txt");
                utime(1111111111, 1111111111, "${strTestPath}/test.txt");
                system("chmod 1640 ${strTestPath}/test.txt");

                system("echo 'TESTDATA_' > ${strTestPath}/sub1/test-sub1.txt");
                utime(1111111112, 1111111112, "${strTestPath}/sub1/test-sub1.txt");
                system("chmod 0640 ${strTestPath}/sub1/test-sub1.txt");

                system("echo 'TESTDATA__' > ${strTestPath}/sub1/sub2/test-sub2.txt");
                utime(1111111113, $bPause ? time() + 10 : 1111111113, "${strTestPath}/sub1/sub2/test-sub2.txt");
                system("chmod 0646 ${strTestPath}/sub1/test-sub1.txt");

                system("ln ${strTestPath}/test.txt ${strTestPath}/sub1/test-hardlink.txt");
                system("ln ${strTestPath}/test.txt ${strTestPath}/sub1/sub2/test-hardlink.txt");

                system("ln -s .. ${strTestPath}/sub1/test");
                system("chmod 0700 ${strTestPath}/sub1/test");
                system("ln -s ../.. ${strTestPath}/sub1/sub2/test");
                system("chmod 0750 ${strTestPath}/sub1/sub2/test");

                system("chmod 0770 ${strTestPath}");

                # Create path
                my $strPath = $strTestPath;

                if ($bError)
                {
                    $strPath = $strTestPath . '/private';
                }
                elsif (!$bExists)
                {
                    $strPath = $strTestPath . '/error';
                }

                # Execute in eval in case of error
                my %oManifestHash;
                my $bErrorExpected = !$bExists || $bError;

                eval
                {
                    $oFile->manifest(PATH_BACKUP_ABSOLUTE, $strPath, \%oManifestHash, $bPause);
                };

                # Check for an error
                if ($@)
                {
                    if ($bErrorExpected)
                    {
                        next;
                    }

                    confess 'error raised: ' . $@ . "\n";
                }

                # Check for an expected error
                if ($bErrorExpected)
                {
                    confess 'error was expected';
                }

                my $strManifest;

                # Validate the manifest
                foreach my $strName (sort(keys $oManifestHash{name}))
                {
                    if (!defined($strManifest))
                    {
                        $strManifest = '';
                    }
                    else
                    {
                        $strManifest .= "\n";
                    }

                    if (defined($oManifestHash{name}{"${strName}"}{inode}))
                    {
                        $oManifestHash{name}{"${strName}"}{inode} = 0;
                    }

                    if ($bPause && $strName eq 'sub1/sub2/test-sub2.txt')
                    {
                        if (!(defined($oManifestHash{name}{$strName}{future}) &&
                             $oManifestHash{name}{$strName}{future} eq 'y'))
                        {
                            confess "${strName} is not marked as future";
                        }

                        if ($oManifestHash{name}{$strName}{modification_time} != time() - 1)
                        {
                            confess "${strName} does not have future time reset to past";
                        }

                        delete($oManifestHash{name}{$strName}{future});
                        $oManifestHash{name}{$strName}{modification_time} = 1111111113;
                    }

                    $strManifest .=
                        "${strName}," .
                        $oManifestHash{name}{"${strName}"}{type} . ',' .
                        (defined($oManifestHash{name}{"${strName}"}{user}) ?
                            $oManifestHash{name}{"${strName}"}{user} : '') . ',' .
                        (defined($oManifestHash{name}{"${strName}"}{group}) ?
                            $oManifestHash{name}{"${strName}"}{group} : '') . ',' .
                        (defined($oManifestHash{name}{"${strName}"}{permission}) ?
                            $oManifestHash{name}{"${strName}"}{permission} : '') . ',' .
                        (defined($oManifestHash{name}{"${strName}"}{modification_time}) ?
                            $oManifestHash{name}{"${strName}"}{modification_time} : '') . ',' .
                        (defined($oManifestHash{name}{"${strName}"}{inode}) ?
                            $oManifestHash{name}{"${strName}"}{inode} : '') . ',' .
                        (defined($oManifestHash{name}{"${strName}"}{size}) ?
                            $oManifestHash{name}{"${strName}"}{size} : '') . ',' .
                        (defined($oManifestHash{name}{"${strName}"}{link_destination}) ?
                            $oManifestHash{name}{"${strName}"}{link_destination} : '') . ',' .
                        (defined($oManifestHash{name}{"${strName}"}{future}) ?
                            $oManifestHash{name}{"${strName}"}{future} : '');
                }

                if ($strManifest ne $strManifestCompare)
                {
                    confess "manifest is not equal:\n\n${strManifest}\n\ncompare:\n\n${strManifestCompare}\n\n";
                }
            }
            }
            }
        }
    }

    #-------------------------------------------------------------------------------------------------------------------------------
    # Test list()
    #-------------------------------------------------------------------------------------------------------------------------------
    if ($strTest eq 'all' || $strTest eq 'list')
    {
        $iRun = 0;

        &log(INFO, '--------------------------------------------------------------------------------');
        &log(INFO, "Test File->list()\n");

        for (my $bRemote = false; $bRemote <= true; $bRemote++)
        {
            # Create the file object
            my $oFile = new BackRest::File
            (
                $strStanza,
                $strTestPath,
                $bRemote ? 'backup' : undef,
                $bRemote ? $oRemote : undef
            );

            for (my $bSort = false; $bSort <= true; $bSort++)
            {
                my $strSort = $bSort ? undef : 'reverse';

                # Loop through expression
                for (my $iExpression = 0; $iExpression <= 2; $iExpression++)
                {
                    my $strExpression;

                    # Expression tha returns results
                    if ($iExpression == 1)
                    {
                        $strExpression = "^test2\\..*\$";
                    }
                    # Expression that does not return results
                    elsif ($iExpression == 2)
                    {
                        $strExpression = "^du\$";
                    }

                    # Loop through exists
                    for (my $bExists = false; $bExists <= true; $bExists++)
                    {
                    # Loop through ignore missing
                    for (my $bIgnoreMissing = false; $bIgnoreMissing <= $bExists; $bIgnoreMissing++)
                    {
                    # Loop through error
                    for (my $bError = false; $bError <= true; $bError++)
                    {
                        if (!BackRestTestCommon_Run(++$iRun,
                                                    "rmt ${bRemote}, err ${bError}, exists ${bExists}, ignmis ${bIgnoreMissing}, " .
                                                    'expression ' . (defined($strExpression) ? $strExpression : '[undef]') . ', ' .
                                                    'sort ' . (defined($strSort) ? $strSort : '[undef]'))) {next}

                        # Setup test directory
                        BackRestTestFile_Setup($bError);

                        my $strPath = $strTestPath;

                        if ($bError)
                        {
                            $strPath = "${strTestPath}/private";
                        }
                        elsif (!$bExists)
                        {
                            $strPath = "${strTestPath}/error";
                        }
                        else
                        {
                            system("echo 'TESTDATA' > ${strPath}/test.txt");
                            system("echo 'TESTDATA2' > ${strPath}/test2.txt");
                        }

                        my @stryFileCompare = split(/\n/, "test.txt\ntest2.txt");

                        # Execute in eval in case of error
                        my @stryFileList;
                        my $bErrorExpected = (!$bExists && !$bIgnoreMissing) || $bError;

                        eval
                        {
                            @stryFileList = $oFile->list(PATH_BACKUP_ABSOLUTE, $strPath, $strExpression, $strSort, $bIgnoreMissing);
                        };

                        if ($@)
                        {
                            if ($bErrorExpected)
                            {
                                next;
                            }

                            confess 'error raised: ' . $@ . "\n";
                        }

                        if ($bErrorExpected)
                        {
                            confess 'error was expected';
                        }

                        # Validate the list
                        if (defined($strExpression))
                        {
                            @stryFileCompare = grep(/$strExpression/i, @stryFileCompare);
                        }

                        if (defined($strSort))
                        {
                            @stryFileCompare = sort {$b cmp $a} @stryFileCompare;
                        }

                        my $strFileList = sprintf("@stryFileList");
                        my $strFileCompare = sprintf("@stryFileCompare");

                        if ($strFileList ne $strFileCompare)
                        {
                            confess "list (${strFileList})[" . @stryFileList .
                                    "] does not match compare (${strFileCompare})[" . @stryFileCompare . ']';
                        }
                    }
                    }
                    }
                }
            }
        }
    }

    #-------------------------------------------------------------------------------------------------------------------------------
    # Test remove()
    #-------------------------------------------------------------------------------------------------------------------------------
    if ($strTest eq 'all' || $strTest eq 'remove')
    {
        $iRun = 0;

        &log(INFO, '--------------------------------------------------------------------------------');
        &log(INFO, "Test File->remove()\n");

        for (my $bRemote = 0; $bRemote <= 1; $bRemote++)
        {
            my $oFile = new BackRest::File
            (
                $strStanza,
                $strTestPath,
                $bRemote ? 'backup' : undef,
                $bRemote ? $oRemote : undef
            );

            # Loop through exists
            for (my $bError = 0; $bError <= 1; $bError++)
            {
            # Loop through exists
            for (my $bExists = 0; $bExists <= 1; $bExists++)
            {
            # Loop through temp
            for (my $bTemp = 0; $bTemp <= 1; $bTemp++)
            {
                # Loop through ignore missing
                for (my $bIgnoreMissing = 0; $bIgnoreMissing <= 1; $bIgnoreMissing++)
                {
                    if (!BackRestTestCommon_Run(++$iRun,
                                                "rmt ${bRemote}, err = ${bError}, exists ${bExists}, tmp ${bTemp}, " .
                                                "ignore missing ${bIgnoreMissing}")) {next}

                    # Setup test directory
                    BackRestTestFile_Setup($bError);

                    my $strFile = "${strTestPath}/test.txt";

                    if ($bError)
                    {
                        $strFile = "${strTestPath}/private/test.txt"
                    }
                    elsif (!$bExists)
                    {
                        $strFile = "${strTestPath}/private/error.txt"
                    }
                    else
                    {
                        system("echo 'TESTDATA' > ${strFile}" . ($bTemp ? '.backrest.tmp' : ''));
                    }

                    # Execute in eval in case of error
                    my $bRemoved;

                    eval
                    {
                        $bRemoved = $oFile->remove(PATH_BACKUP_ABSOLUTE, $strFile, $bTemp, $bIgnoreMissing);
                    };

                    if ($@)
                    {
                        if ($bError || $bRemote)
                        {
                            next;
                        }

                        if (!$bExists && !$bIgnoreMissing)
                        {
                            next;
                        }

                        confess 'unexpected error raised: ' . $@;
                    }

                    if ($bError || $bRemote)
                    {
                        confess 'error should have been returned';
                    }

                    if (!$bRemoved)
                    {
                        if (!$bExists && $bIgnoreMissing)
                        {
                            next;
                        }

                        confess 'remove returned false, but something should have been removed';
                    }

                    if (-e ($strFile . ($bTemp ? '.backrest.tmp' : '')))
                    {
                        confess 'file still exists';
                    }
                }
            }
            }
            }
        }
    }

    #-------------------------------------------------------------------------------------------------------------------------------
    # Test hash()
    #-------------------------------------------------------------------------------------------------------------------------------
    if ($strTest eq 'all' || $strTest eq 'hash')
    {
        $iRun = 0;

        &log(INFO, '--------------------------------------------------------------------------------');
        &log(INFO, "test File->hash()\n");

        for (my $bRemote = false; $bRemote <= true; $bRemote++)
        {
            my $oFile = new BackRest::File
            (
                $strStanza,
                $strTestPath,
                $bRemote ? 'backup' : undef,
                $bRemote ? $oRemote : undef
            );

            # Loop through error
            for (my $bError = false; $bError <= true; $bError++)
            {
            # Loop through exists
            for (my $bExists = false; $bExists <= true; $bExists++)
            {
            # Loop through exists
            for (my $bCompressed = false; $bCompressed <= true; $bCompressed++)
            {
                if (!BackRestTestCommon_Run(++$iRun,
                                            "rmt ${bRemote}, err ${bError}, exists ${bExists}, cmp ${bCompressed}")) {next}

                # Setup test directory
                BackRestTestFile_Setup($bError);

                my $strFile = "${strTestPath}/test.txt";

                if ($bError)
                {
                    $strFile = "${strTestPath}/private/test.txt";
                }
                elsif (!$bExists)
                {
                    $strFile = "${strTestPath}/error.txt";
                }
                else
                {
                    system("echo 'TESTDATA' > ${strFile}");

                    if ($bCompressed && !$bRemote)
                    {
                        $oFile->compress(PATH_BACKUP_ABSOLUTE, $strFile);
                        $strFile = $strFile . '.gz';
                    }
                }

                # Execute in eval in case of error
                my $strHash;
                my $bErrorExpected = !$bExists || $bError || $bRemote;

                eval
                {
                    $strHash = $oFile->hash(PATH_BACKUP_ABSOLUTE, $strFile, $bCompressed)
                };

                if ($@)
                {
                    if ($bErrorExpected)
                    {
                        next;
                    }

                    confess 'unexpected error raised: ' . $@;
                }

                if ($bErrorExpected)
                {
                    confess 'error was expected';
                }

                if ($strHash ne '06364afe79d801433188262478a76d19777ef351')
                {
                    confess 'hashes do not match';
                }
            }
            }
            }
        }
    }

    #-------------------------------------------------------------------------------------------------------------------------------
    # Test exists()
    #-------------------------------------------------------------------------------------------------------------------------------
    if ($strTest eq 'all' || $strTest eq 'exists')
    {
        $iRun = 0;

        &log(INFO, '--------------------------------------------------------------------------------');
        &log(INFO, "test File->exists()\n");

        for (my $bRemote = 0; $bRemote <= 1; $bRemote++)
        {
            my $oFile = new BackRest::File
            (
                $strStanza,
                $strTestPath,
                $bRemote ? 'backup' : undef,
                $bRemote ? $oRemote : undef
            );

            # Loop through exists
            for (my $bExists = 0; $bExists <= 1; $bExists++)
            {
                # Loop through exists
                for (my $bError = 0; $bError <= $bExists; $bError++)
                {
                    if (!BackRestTestCommon_Run(++$iRun,
                                                "rmt ${bRemote}, err ${bError}, exists ${bExists}")) {next}

                    # Setup test directory
                    BackRestTestFile_Setup($bError);

                    my $strFile = "${strTestPath}/test.txt";

                    if ($bError)
                    {
                        $strFile = "${strTestPath}/private/test.txt";
                    }
                    elsif ($bExists)
                    {
                        system("echo 'TESTDATA' > ${strFile}");
                    }

                    # Execute in eval in case of error
                    eval
                    {
                        if ($oFile->exists(PATH_BACKUP_ABSOLUTE, $strFile) != $bExists)
                        {
                            confess "bExists is set to ${bExists}, but exists() returned " . !$bExists;
                        }
                    };

                    if ($@)
                    {
                        my $oMessage = $@;
                        my $iCode;
                        my $strMessage;

                        if (blessed($oMessage))
                        {
                            if ($oMessage->isa('BackRest::Exception'))
                            {
                                $iCode = $oMessage->code();
                                $strMessage = $oMessage->message();
                            }
                            else
                            {
                                confess 'unknown error object';
                            }
                        }
                        else
                        {
                            $strMessage = $oMessage;
                        }

                        if ($bError)
                        {
                            next;
                        }

                        confess 'error raised: ' . $strMessage . "\n";
                    }
                }
            }
        }
    }

    #-------------------------------------------------------------------------------------------------------------------------------
    # Test copy()
    #-------------------------------------------------------------------------------------------------------------------------------
    if ($strTest eq 'all' || $strTest eq 'copy')
    {
        $iRun = 0;

        # Loop through backup local vs remote
        for (my $bBackupRemote = 0; $bBackupRemote <= 1; $bBackupRemote++)
        {
        # Loop through db local vs remote
        for (my $bDbRemote = 0; $bDbRemote <= 1; $bDbRemote++)
        {
            # Backup and db cannot both be remote
            if ($bBackupRemote && $bDbRemote)
            {
                next;
            }

            # Determine side is remote
            my $strRemote = $bBackupRemote ? 'backup' : $bDbRemote ? 'db' : undef;

            # Create the file object
            my $oFile = new BackRest::File
            (
                $strStanza,
                $strTestPath,
                $strRemote,
                defined($strRemote) ? $oRemote : undef
            );

            # Loop through source compression
            for (my $bSourceCompressed = 0; $bSourceCompressed <= 1; $bSourceCompressed++)
            {
            # Loop through destination compression
            for (my $bDestinationCompress = 0; $bDestinationCompress <= 1; $bDestinationCompress++)
            {
            # Loop through source path types
            for (my $bSourcePathType = 0; $bSourcePathType <= 1; $bSourcePathType++)
            {
            # Loop through destination path types
            for (my $bDestinationPathType = 0; $bDestinationPathType <= 1; $bDestinationPathType++)
            {
            # Loop through source ignore/require
            for (my $bSourceIgnoreMissing = 0; $bSourceIgnoreMissing <= 1; $bSourceIgnoreMissing++)
            {
            # Loop through source missing/present
            for (my $bSourceMissing = 0; $bSourceMissing <= 1; $bSourceMissing++)
            {
            # Loop through small/large
            for (my $bLarge = false; $bLarge <= defined($strRemote) && !$bSourceMissing; $bLarge++)
            {
                my $strSourcePathType = $bSourcePathType ? PATH_DB_ABSOLUTE : PATH_BACKUP_ABSOLUTE;
                my $strSourcePath = $bSourcePathType ? 'db' : 'backup';

                my $strDestinationPathType = $bDestinationPathType ? PATH_DB_ABSOLUTE : PATH_BACKUP_ABSOLUTE;
                my $strDestinationPath = $bDestinationPathType ? 'db' : 'backup';

                if (!BackRestTestCommon_Run(++$iRun,
                                            'rmt ' .
                                                (defined($strRemote) && ($strRemote eq $strSourcePath ||
                                                 $strRemote eq $strDestinationPath) ? 1 : 0) .
                                            ", lrg ${bLarge}, " .
                                            'srcpth ' . (defined($strRemote) && $strRemote eq $strSourcePath ? 'rmt' : 'lcl') .
                                                ":${strSourcePath}, srccmp $bSourceCompressed, srcmiss ${bSourceMissing}, " .
                                                "srcignmiss ${bSourceIgnoreMissing}, " .
                                            'dstpth ' .
                                                (defined($strRemote) && $strRemote eq $strDestinationPath ? 'rmt' : 'lcl') .
                                                ":${strDestinationPath}, dstcmp $bDestinationCompress")) {next}

                # Setup test directory
                BackRestTestFile_Setup(false);
                system("mkdir ${strTestPath}/backup") == 0 or confess 'Unable to create test/backup directory';
                system("mkdir ${strTestPath}/db") == 0 or confess 'Unable to create test/db directory';

                my $strSourceFile = "${strTestPath}/${strSourcePath}/test-source";
                my $strDestinationFile = "${strTestPath}/${strDestinationPath}/test-destination";

                # Create the compressed or uncompressed test file
                my $strSourceHash;

                if (!$bSourceMissing)
                {
                    if ($bLarge)
                    {
                        $strSourceFile .= '.bin';
                        $strDestinationFile .= '.bin';

                        BackRestTestCommon_Execute('cp ' . BackRestTestCommon_DataPathGet() . "/test.archive.bin ${strSourceFile}");
                    }
                    else
                    {
                        $strSourceFile .= '.txt';
                        $strDestinationFile .= '.txt';

                        system("echo 'TESTDATA' > ${strSourceFile}");
                    }

                    $strSourceHash = $oFile->hash(PATH_ABSOLUTE, $strSourceFile);

                    if ($bSourceCompressed)
                    {
                        system("gzip ${strSourceFile}");
                        $strSourceFile .= '.gz';
                    }
                }

                if ($bDestinationCompress)
                {
                    $strDestinationFile .= '.gz';
                }

                # Run file copy in an eval block because some errors are expected
                my $bReturn;

                eval
                {
                    $bReturn = $oFile->copy($strSourcePathType, $strSourceFile,
                                            $strDestinationPathType, $strDestinationFile,
                                            $bSourceCompressed, $bDestinationCompress,
                                            $bSourceIgnoreMissing, undef,
                                            '0700');
                };

                # Check for errors after copy
                if ($@)
                {
                    my $oMessage = $@;

                    if (blessed($oMessage))
                    {
                        if ($oMessage->isa('BackRest::Exception'))
                        {
                            if ($bSourceMissing && !$bSourceIgnoreMissing)
                            {
                                next;
                            }

                            confess $oMessage->message();
                        }
                        else
                        {
                            confess 'unknown error object: ' . $oMessage;
                        }
                    }

                    confess $oMessage;
                }

                if ($bSourceMissing)
                {
                    if ($bSourceIgnoreMissing)
                    {
                         if ($bReturn)
                         {
                             confess 'copy() returned ' . $bReturn .  ' when ignore missing set';
                         }

                         next;
                    }

                    confess 'expected source file missing error';
                }

                unless (-e $strDestinationFile)
                {
                    confess "could not find destination file ${strDestinationFile}";
                }

                my $strDestinationTest = $strDestinationFile;

                if ($bDestinationCompress)
                {
                    $strDestinationTest = substr($strDestinationFile, 0, length($strDestinationFile) - 3) . '.test';

                    system("gzip -dc ${strDestinationFile} > ${strDestinationTest}") == 0
                        or die "could not decompress ${strDestinationFile}";
                }

                my $strDestinationHash = $oFile->hash(PATH_ABSOLUTE, $strDestinationTest);

                if ($strSourceHash ne $strDestinationHash)
                {
                    confess "source ${strSourceHash} and destination ${strDestinationHash} file hashes do not match";
                }
            }
            }
            }
            }
            }
            }
            }
        }
        }
    }

    if (BackRestTestCommon_Cleanup())
    {
        BackRestTestFile_Setup(undef, true);
    }
}

1;
