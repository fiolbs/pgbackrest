####################################################################################################################################
# STANZA MODULE
#
# Contains functions for adding, upgrading and removing a stanza.
####################################################################################################################################
package pgBackRest::Stanza;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

use Exporter qw(import);
    our @EXPORT = qw();

use pgBackRest::Common::Exception;
use pgBackRest::Common::Log;
use pgBackRest::Config::Config;
use pgBackRest::Archive::ArchiveInfo;
use pgBackRest::BackupInfo;
use pgBackRest::Db;
use pgBackRest::DbVersion;
use pgBackRest::File;
use pgBackRest::FileCommon;
use pgBackRest::Protocol::Common;
use pgBackRest::Protocol::Protocol;

####################################################################################################################################
# Global variables
####################################################################################################################################
my $strStanzaCreateErrorMsg = "not empty\n" .
    "HINT: Use --force to force the stanza data to be created.";

####################################################################################################################################
# CONSTRUCTOR
####################################################################################################################################
sub new
{
    my $class = shift;          # Class name

    # Create the class hash
    my $self = {};
    bless $self, $class;

    # Assign function parameters, defaults, and log debug info
    my $strOperation = logDebugParam(__PACKAGE__ . '->new');

    # Initialize the database object
    $self->{oDb} = dbMasterGet();

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'self', value => $self}
    );
}

####################################################################################################################################
# DESTROY
####################################################################################################################################
sub DESTROY
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my ($strOperation) = logDebugParam(__PACKAGE__ . '->DESTROY');

    undef($self->{oDb});

    # Return from function and log return values if any
    return logDebugReturn($strOperation);
}

####################################################################################################################################
# Process Stanza Commands
####################################################################################################################################
sub process
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my ($strOperation) = logDebugParam(__PACKAGE__ . '->process');

    # Error if any other command other than stanza-create is found
    if (!commandTest(CMD_STANZA_CREATE))
    {
        confess &log(ASSERT, "Stanza->process() called with invalid command: " . commandGet());
    }

    # Process stanza create
    my $iResult = $self->stanzaCreate();

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'iResult', value => $iResult, trace => true}
    );
}

####################################################################################################################################
# stanzaCreate
#
# Creates the required data for the stanza.
####################################################################################################################################
sub stanzaCreate
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my ($strOperation) = logDebugParam(__PACKAGE__ . '->stanzaCreate');

    # Initialize default file object with protocol set to NONE meaning strictly local
    my $oFile = new pgBackRest::File
    (
        optionGet(OPTION_STANZA),
        optionGet(OPTION_REPO_PATH),
        protocolGet(NONE)
    );

    $self->dbInfoGet();

    # Get the parent paths (create if not exist)
    my $strParentPathArchive = $self->parentPathGet($oFile, PATH_BACKUP_ARCHIVE);
    my $strParentPathBackup = $self->parentPathGet($oFile, PATH_BACKUP_CLUSTER);

    # Get a listing of files in the directory, ignoring if any are missing
    my @stryFileListArchive = fileList($strParentPathArchive, undef, 'forward', true);
    my @stryFileListBackup = fileList($strParentPathBackup, undef, 'forward', true);

    # If force not used and at least one directory is not empty, then check to see if the info files exist
    if (!optionGet(OPTION_FORCE) && (@stryFileListArchive || @stryFileListBackup))
    {
        my $strBackupInfoFile = &FILE_BACKUP_INFO;
        my $strArchiveInfoFile = &ARCHIVE_INFO_FILE;

        # If either info file is not in the file list, then something exists in the directories so need to use force option
        if (@stryFileListBackup && !grep(/^$strBackupInfoFile/i, @stryFileListBackup)
            || @stryFileListArchive && !grep(/^$strArchiveInfoFile/i, @stryFileListArchive))
        {
            confess &log(ERROR,
                (@stryFileListBackup ? 'backup directory ' : '') .
                ((@stryFileListBackup && @stryFileListArchive) ? 'and/or ' : '') .
                (@stryFileListArchive ? 'archive directory ' : '') .
                $strStanzaCreateErrorMsg, ERROR_PATH_NOT_EMPTY);
        }
    }

    # Create the archive.info file and local variables
    my ($iResult, $strResultMessage) =
        $self->infoFileCreate((new pgBackRest::Archive::ArchiveInfo($strParentPathArchive, false)), $oFile,
            PATH_BACKUP_ARCHIVE, $strParentPathArchive, \@stryFileListArchive);

    if ($iResult == 0)
    {
        # Create the backup.info file
        ($iResult, $strResultMessage) =
            $self->infoFileCreate((new pgBackRest::BackupInfo($strParentPathBackup, false, false)), $oFile,
                PATH_BACKUP_CLUSTER, $strParentPathBackup, \@stryFileListBackup);
    }

    if ($iResult != 0)
    {
        &log(WARN, "unable to create stanza '" . optionGet(OPTION_STANZA) . "'");
        confess &log(ERROR, $strResultMessage, $iResult);
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'iResult', value => $iResult, trace => true}
    );
}

####################################################################################################################################
# parentPathGet
#
# Creates the parent path if it doesn't exist and returns the path.
####################################################################################################################################
sub parentPathGet
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oFile,
        $strPathType,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->parentPathGet', \@_,
            {name => 'oFile', trace => true},
            {name => 'strPathType', trace => true},
        );

    my $strParentPath = $oFile->pathGet($strPathType);

    # If the info path does not exist, create it
    if (!fileExists($strParentPath))
    {
        # Create the cluster repo path
        $oFile->pathCreate($strPathType, undef, undef, true, true);
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strParentPath', value => $strParentPath},
    );
}

####################################################################################################################################
# infoFileCreate
#
# Creates the info file based on the data passed to the function
####################################################################################################################################
sub infoFileCreate
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oInfo,
        $oFile,
        $strPathType,
        $strParentPath,
        $stryFileList,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->infoFileCreate', \@_,
            {name => 'oInfo', trace => true},
            {name => 'oFile', trace => true},
            {name => 'strPathType'},
            {name => 'strParentPath'},
            {name => 'stryFileList'},
        );

    my $iResult = 0;
    my $strResultMessage = undef;
    my $strWarningMsgArchive = undef;
    my $bSave = true;

    # Turn off console logging to control when to display the error
    logLevelSet(undef, OFF);

    eval
    {
        # ??? File init will need to be addressed with stanza-upgrade since there could then be more than one DB and db-id
        # so the DB section, esp for backup.info, cannot be initialized before we attempt to reconstruct the file from the
        # directories since the history id would be wrong. Also need to handle if the reconstruction fails - if any file in
        # the backup directory or archive directory are missing or mal-formed, then currently an error will be thrown, which
        # may not be desireable.

        # If the info file does not exist, initialize it internally but do not save until complete reconstruction
        if (!$oInfo->exists())
        {
            ($strPathType eq PATH_BACKUP_CLUSTER)
                ? $oInfo->create($self->{oDb}{strDbVersion}, $self->{oDb}{ullDbSysId}, $self->{oDb}{iControlVersion},
                    $self->{oDb}{iCatalogVersion}, false)
                : $oInfo->create($self->{oDb}{strDbVersion}, $self->{oDb}{ullDbSysId}, false);
        }

        # Reconstruct the file from the data in the directory if there is any
        if ($strPathType eq PATH_BACKUP_CLUSTER)
        {
            $oInfo->reconstruct(false, false);
        }
        # If this is the archive.info reconstruction then catch any warnings
        else
        {
            $strWarningMsgArchive = $oInfo->reconstruct($oFile, $self->{oDb}{strDbVersion}, $self->{oDb}{ullDbSysId});
        }

        # If the file exists on disk, then check if the reconstructed data is the same as what is on disk
        if ($oInfo->exists())
        {
            my $oInfoOnDisk =
                ($strPathType eq PATH_BACKUP_CLUSTER ? new pgBackRest::BackupInfo($strParentPath)
                : new pgBackRest::Archive::ArchiveInfo($strParentPath));

            # If force was not used and the hashes are different then error
            if ($oInfoOnDisk->hash() ne $oInfo->hash())
            {
                if (!optionGet(OPTION_FORCE))
                {
                    $iResult = ERROR_FILE_INVALID;
                    $strResultMessage =
                        ($strPathType eq PATH_BACKUP_CLUSTER ? 'backup file ' : 'archive file ') .
                        ' invalid; to correct, use --force';
                }
            }
            # If the hashes are the same, then don't save the file since it already exists and is valid
            else
            {
                $bSave = false;
            }
        }

        # If force was not used and the info file does not exist and the directory is not empty, then error
        # This should also be performed by the calling routine before this function is called, so this is just a safety check
        if ($iResult == 0 && !optionGet(OPTION_FORCE) && !$oInfo->exists() && @$stryFileList)
        {
            $iResult = ERROR_PATH_NOT_EMPTY;
            $strResultMessage =
                ($strPathType eq PATH_BACKUP_CLUSTER ? 'backup directory ' : 'archive directory ') . $strStanzaCreateErrorMsg;
        }

        if ($iResult == 0)
        {
            # ??? With stanza-upgrade we will want ability to force the DB section to match but for now, if it doesn't match,
            # then something is wrong.
            ($strPathType eq PATH_BACKUP_CLUSTER)
                ? $oInfo->check($self->{oDb}{strDbVersion}, $self->{oDb}{iControlVersion}, $self->{oDb}{iCatalogVersion},
                    $self->{oDb}{ullDbSysId}, false)
                : $oInfo->check($self->{oDb}{strDbVersion}, $self->{oDb}{ullDbSysId}, false);

            # Save the reconstructed file
            if ($bSave)
            {
                $oInfo->save();
            }

            # Sync path if requested
            if (optionGet(OPTION_REPO_SYNC))
            {
                $oFile->pathSync(
                    PATH_BACKUP_ABSOLUTE,
                    defined($oInfo->{strArchiveClusterPath}) ? $oInfo->{strArchiveClusterPath} : $oInfo->{strBackupClusterPath});
            }
        }

        return true;
    }
    or do
    {
        # Capture error information
        $iResult = exceptionCode($EVAL_ERROR);
        $strResultMessage = exceptionMessage($EVAL_ERROR->message());
    };

    # Reset the console logging
    logLevelSet(undef, optionGet(OPTION_LOG_LEVEL_CONSOLE));

    # If a warning was issued, raise it
    if (defined($strWarningMsgArchive))
    {
        &log(WARN, $strWarningMsgArchive);
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'iResult', value => $iResult},
        {name => 'strResultMessage', value => $strResultMessage},
    );
}

####################################################################################################################################
# dbInfoGet
#
# Gets the database information and store it in $self
####################################################################################################################################
sub dbInfoGet
{
    my $self = shift;

    # Assign function parameters, defaults, and log debug info
    my ($strOperation) = logDebugParam(__PACKAGE__ . '->dbInfoGet');

    # Validate the database configuration. Do not require the database to be online before creating a stanza because the
    # archive_command will attempt to push an achive before the archive.info file exists which will result in an error in the
    # postgres logs.
    if (optionGet(OPTION_ONLINE))
    {
        # If the db-path in pgbackrest.conf does not match the pg_control then this will error alert the user to fix pgbackrest.conf
        $self->{oDb}->configValidate();
    }

    ($self->{oDb}{strDbVersion}, $self->{oDb}{iControlVersion}, $self->{oDb}{iCatalogVersion}, $self->{oDb}{ullDbSysId})
        = $self->{oDb}->info();

    # Return from function and log return values if any
    return logDebugReturn($strOperation);
}

1;
