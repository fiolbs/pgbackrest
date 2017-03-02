####################################################################################################################################
# COMMON INI MODULE
####################################################################################################################################
package pgBackRest::Common::Ini;

use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);

use Exporter qw(import);
    our @EXPORT = qw();
use Fcntl qw(:mode O_WRONLY O_CREAT O_TRUNC);
use File::Basename qw(dirname basename);
use IO::Handle;
use JSON::PP;
use Storable qw(dclone);

use pgBackRest::Common::Exception;
use pgBackRest::Common::Log;
use pgBackRest::Common::String;
use pgBackRest::FileCommon;
use pgBackRest::Version;

####################################################################################################################################
# Boolean constants
####################################################################################################################################
use constant INI_TRUE                                               => JSON::PP::true;
    push @EXPORT, qw(INI_TRUE);
use constant INI_FALSE                                              => JSON::PP::false;
    push @EXPORT, qw(INI_FALSE);

####################################################################################################################################
# Ini control constants
####################################################################################################################################
use constant INI_SECTION_BACKREST                                   => 'backrest';
    push @EXPORT, qw(INI_SECTION_BACKREST);

use constant INI_KEY_CHECKSUM                                       => 'backrest-checksum';
    push @EXPORT, qw(INI_KEY_CHECKSUM);
use constant INI_KEY_FORMAT                                         => 'backrest-format';
    push @EXPORT, qw(INI_KEY_FORMAT);
use constant INI_KEY_SEQUENCE                                       => 'backrest-sequence';
    push @EXPORT, qw(INI_KEY_SEQUENCE);
use constant INI_KEY_VERSION                                        => 'backrest-version';
    push @EXPORT, qw(INI_KEY_VERSION);

####################################################################################################################################
# Ini file copy extension
####################################################################################################################################
use constant INI_COPY_EXT                                           => '.copy';
    push @EXPORT, qw(INI_COPY_EXT);

####################################################################################################################################
# Ini sort orders
####################################################################################################################################
use constant INI_SORT_FORWARD                                       => 'forward';
    push @EXPORT, qw(INI_SORT_FORWARD);
use constant INI_SORT_REVERSE                                       => 'reverse';
    push @EXPORT, qw(INI_SORT_REVERSE);
use constant INI_SORT_NONE                                          => 'none';
    push @EXPORT, qw(INI_SORT_NONE);

####################################################################################################################################
# new()
####################################################################################################################################
sub new
{
    my $class = shift;                  # Class name

    # Create the class hash
    my $self = {};
    bless $self, $class;

    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $strFileName,
        $bLoad,
        $strContent,
        $iInitFormat,
        $strInitVersion,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '->new', \@_,
            {name => 'strFileName', trace => true},
            {name => 'bLoad', optional => true, default => true, trace => true},
            {name => 'strContent', optional => true, trace => true},
            {name => 'iInitFormat', optional => true, default => BACKREST_FORMAT, trace => true},
            {name => 'strInitVersion', optional => true, default => BACKREST_VERSION, trace => true},
        );

    # Set variables
    my $oContent = {};
    $self->{oContent} = $oContent;
    $self->{strFileName} = $strFileName;

    # Set changed to false
    $self->{bModified} = false;

    # Set exists to false
    $self->{bExists} = false;

    if ($bLoad || defined($strContent))
    {
        if ($bLoad)
        {
            $self->load();
        }
        else
        {
            $self->{oContent} = iniParse($strContent);
        }

        # Make sure the ini is valid by testing checksum
        my $strChecksum = $self->get(INI_SECTION_BACKREST, INI_KEY_CHECKSUM);
        my $strTestChecksum = $self->hash();

        if ($strChecksum ne $strTestChecksum)
        {
            confess &log(ERROR,
                "invalid checksum in '${strFileName}', expected '${strTestChecksum}' but found '${strChecksum}'", ERROR_CHECKSUM);
        }

        # Make sure that the format is current, otherwise error
        my $iFormat = $self->get(INI_SECTION_BACKREST, INI_KEY_FORMAT, undef, false, 0);

        if ($iFormat != $iInitFormat)
        {
            confess &log(ERROR,
                "invalid format in '${strFileName}', expected " . BACKREST_FORMAT . " but found ${iFormat}", ERROR_FORMAT);
        }

        # Check if the version has changed
        if (!$self->test(INI_SECTION_BACKREST, INI_KEY_VERSION, undef, $strInitVersion))
        {
            $self->set(INI_SECTION_BACKREST, INI_KEY_VERSION, undef, $strInitVersion);
        }
    }
    else
    {
        $self->{oContent}{&INI_SECTION_BACKREST}{&INI_KEY_SEQUENCE} = 0 + 0;
        $self->numericSet(INI_SECTION_BACKREST, INI_KEY_FORMAT, undef, $iInitFormat);
        $self->set(INI_SECTION_BACKREST, INI_KEY_VERSION, undef, $strInitVersion);
    }

    return $self;
}

####################################################################################################################################
# load() - load the ini.
####################################################################################################################################
sub load
{
    my $self = shift;

    my $strContent = fileStringRead($self->{strFileName}, {bIgnoreMissing => true});
    my $strContentCopy = fileStringRead($self->{strFileName} . INI_COPY_EXT, {bIgnoreMissing => true});

    if (defined($strContent) && defined($strContentCopy))
    {
        # !!! FIX THIS
        $self->{oContent} = iniParse($strContent);
    }
    # If only the main file exists then use it
    elsif (defined($strContent) && !defined($strContentCopy))
    {
        $self->{oContent} = iniParse($strContent);
    }
    # If only the copy exists then use it
    elsif (!defined($strContent) && defined($strContentCopy))
    {
        $self->{oContent} = iniParse($strContentCopy);
    }
    # If neither exists then error
    else
    {
        confess &log(ERROR, "unable to open $self->{strFileName} or $self->{strFileName}" . INI_COPY_EXT, ERROR_FILE_OPEN);
    }

    $self->{bExists} = true;
}

####################################################################################################################################
# iniParse() - parse from standard INI format to a hash.
####################################################################################################################################
push @EXPORT, qw(iniParse);

sub iniParse
{
    my $strContent = shift;
    my $bRelaxed = shift;

    # Ini content
    my $oContent = {};
    my $strSection;

    # Create the JSON object
    my $oJSON = JSON::PP->new()->allow_nonref();

    # Read the INI file
    foreach my $strLine (split("\n", $strContent))
    {
        $strLine = trim($strLine);

        # Skip lines that are blank or comments
        if ($strLine ne '' && $strLine !~ '^[ ]*#.*')
        {
            # Get the section
            if (index($strLine, '[') == 0)
            {
                $strSection = substr($strLine, 1, length($strLine) - 2);
            }
            else
            {
                # Get key and value
                my $iIndex = index($strLine, '=');

                if ($iIndex == -1)
                {
                    confess &log(ERROR, "unable to find '=' in '${strLine}'", ERROR_CONFIG);
                }

                my $strKey = substr($strLine, 0, $iIndex);
                my $strValue = substr($strLine, $iIndex + 1);

                # If relaxed then read the value directly
                if ($bRelaxed)
                {
                    if (defined($$oContent{$strSection}{$strKey}))
                    {
                        if (ref($$oContent{$strSection}{$strKey}) ne 'ARRAY')
                        {
                            $$oContent{$strSection}{$strKey} = [$$oContent{$strSection}{$strKey}];
                        }

                        push(@{$$oContent{$strSection}{$strKey}}, $strValue);
                    }
                    else
                    {
                        $$oContent{$strSection}{$strKey} = $strValue;
                    }
                }
                # Else read the value as stricter JSON
                else
                {
                    ${$oContent}{$strSection}{$strKey} = $oJSON->decode($strValue);
                }
            }
        }
    }

    # close($hFile);
    return($oContent);
}

####################################################################################################################################
# save() - save the file.
####################################################################################################################################
sub save
{
    my $self = shift;

    $self->hash();

    if ($self->{bModified})
    {
        fileStringWrite($self->{strFileName}, iniRender($self->{oContent}));
        fileStringWrite($self->{strFileName} . INI_COPY_EXT, iniRender($self->{oContent}));
        $self->{bModified} = false;

        # Indicate the file now exists
        $self->{bExists} = true;
    }
}

####################################################################################################################################
# saveCopy - save only a copy of the file.
####################################################################################################################################
sub saveCopy
{
    my $self = shift;

    if (fileExists($self->{strFileName}))
    {
        confess &log(ASSERT, "cannot save copy only when '$self->{strFileName}' exists");
    }

    $self->hash();
    fileStringWrite("$self->{strFileName}" . INI_COPY_EXT, iniRender($self->{oContent}));
}

####################################################################################################################################
# iniRender() - render hash to standard INI format.
####################################################################################################################################
push @EXPORT, qw(iniRender);

sub iniRender
{
    # Assign function parameters, defaults, and log debug info
    my
    (
        $strOperation,
        $oContent,
        $bRelaxed,
    ) =
        logDebugParam
        (
            __PACKAGE__ . '::iniRender', \@_,
            {name => 'oContent', trace => true},
            {name => 'bTemp', default => false, trace => true},
        );

    # Open the ini file for writing
    my $strContent = '';
    my $bFirst = true;

    # Create the JSON object canonical so that fields are alpha ordered to pass unit tests
    my $oJSON = JSON::PP->new()->canonical()->allow_nonref();

    # Write the INI file
    foreach my $strSection (sort(keys(%$oContent)))
    {
        # Add a linefeed between sections
        if (!$bFirst)
        {
            $strContent .= "\n";
        }

        # Write the section
        $strContent .= "[${strSection}]\n";

        # Iterate through all keys in the section
        foreach my $strKey (sort(keys(%{$oContent->{$strSection}})))
        {
            # If the value is a hash then convert it to JSON, otherwise store as is
            my $strValue = ${$oContent}{$strSection}{$strKey};

            # If relaxed then store as old-style config
            if ($bRelaxed)
            {
                # If the value is an array then save each element to a separate key/value pair
                if (ref($strValue) eq 'ARRAY')
                {
                    foreach my $strArrayValue (@{$strValue})
                    {
                        $strContent .= "${strKey}=${strArrayValue}\n";
                    }
                }
                # Else write a standard key/value pair
                else
                {
                    $strContent .= "${strKey}=${strValue}\n";
                }
            }
            # Else write as stricter JSON
            else
            {
                $strContent .= "${strKey}=" . $oJSON->encode($strValue) . "\n";
            }
        }

        $bFirst = false;
    }

    # Return from function and log return values if any
    return logDebugReturn
    (
        $strOperation,
        {name => 'strContent', value => $strContent, trace => true}
    );
}

####################################################################################################################################
# hash() - generate hash for the manifest.
####################################################################################################################################
sub hash
{
    my $self = shift;

    # Remove the old checksum and save the sequence
    my $iSequence = $self->{oContent}{&INI_SECTION_BACKREST}{&INI_KEY_SEQUENCE};
    delete($self->{oContent}{&INI_SECTION_BACKREST}{&INI_KEY_CHECKSUM});
    delete($self->{oContent}{&INI_SECTION_BACKREST}{&INI_KEY_SEQUENCE});

    my $oSHA = Digest::SHA->new('sha1');
    my $oJSON = JSON::PP->new()->canonical()->allow_nonref();
    $oSHA->add($oJSON->encode($self->{oContent}));

    # Set the new checksum
    $self->{oContent}{&INI_SECTION_BACKREST}{&INI_KEY_CHECKSUM} = $oSHA->hexdigest();
    $self->{oContent}{&INI_SECTION_BACKREST}{&INI_KEY_SEQUENCE} = $iSequence + 0;

    return $self->{oContent}{&INI_SECTION_BACKREST}{&INI_KEY_CHECKSUM};
}

####################################################################################################################################
# get() - get a value.
####################################################################################################################################
sub get
{
    my $self = shift;
    my $strSection = shift;
    my $strKey = shift;
    my $strSubKey = shift;
    my $bRequired = shift;
    my $oDefault = shift;

    # Parameter constraints
    if (!defined($strSection))
    {
        confess &log(ASSERT, 'strSection is required');
    }

    if (defined($strSubKey) && !defined($strKey))
    {
        confess &log(ASSERT, "strKey is required when strSubKey '${strSubKey}' is requested");
    }

    # Get the result
    my $oResult = $self->{oContent}->{$strSection};

    if (defined($strKey) && defined($oResult))
    {
        $oResult = $oResult->{$strKey};

        if (defined($strSubKey) && defined($oResult))
        {
            $oResult = $oResult->{$strSubKey};
        }
    }

    # When result is not defined
    if (!defined($oResult))
    {
        # Error if a result is required
        if (!defined($bRequired) || $bRequired)
        {
            confess &log(ASSERT, "strSection '$strSection'" . (defined($strKey) ? ", strKey '$strKey'" : '') .
                                  (defined($strSubKey) ? ", strSubKey '$strSubKey'" : '') . ' is required but not defined');
        }

        # Return default if specified
        if (defined($oDefault))
        {
            return $oDefault;
        }
    }

    return $oResult
}

####################################################################################################################################
# boolGet() - get a boolean value.
####################################################################################################################################
sub boolGet {
    return shift->get(shift, shift, shift, shift, defined($_[0]) ? (shift() ? INI_TRUE : INI_FALSE) : undef) ? true : false}

####################################################################################################################################
# numericGet() - get a numeric value.
####################################################################################################################################
sub numericGet {return shift->get(shift, shift, shift, shift, defined($_[0]) ? shift() + 0 : undef) + 0}

####################################################################################################################################
# set - set a value.
####################################################################################################################################
sub set
{
    my $self = shift;
    my $strSection = shift;
    my $strKey = shift;
    my $strSubKey = shift;
    my $oValue = shift;

    # Parameter constraints
    if (!(defined($strSection) && defined($strKey)))
    {
        confess &log(ASSERT, 'strSection and strKey are required');
    }

    my $oCurrentValue;

    if (defined($strSubKey))
    {
        $oCurrentValue = \$self->{oContent}{$strSection}{$strKey}{$strSubKey};
    }
    else
    {
        $oCurrentValue = \$self->{oContent}{$strSection}{$strKey};
    }

    if (!defined($$oCurrentValue) ||
        defined($oCurrentValue) != defined($oValue) ||
        ${dclone($oCurrentValue)} ne ${dclone(\$oValue)})
    {
        $$oCurrentValue = $oValue;

        if (!$self->{bModified})
        {
            $self->{bModified} = true;
            $self->{oContent}{&INI_SECTION_BACKREST}{&INI_KEY_SEQUENCE}++;
        }

        return true;
    }

    return false;
}

####################################################################################################################################
# boolSet - set a boolean value.
####################################################################################################################################
sub boolSet {shift->set(shift, shift, shift, shift() ? INI_TRUE : INI_FALSE)}

####################################################################################################################################
# numericSet - set a numeric value.
####################################################################################################################################
sub numericSet {shift->set(shift, shift, shift, defined($_[0]) ? shift() + 0 : undef)}

####################################################################################################################################
# remove - remove a value.
####################################################################################################################################
sub remove
{
    my $self = shift;
    my $strSection = shift;
    my $strKey = shift;
    my $strSubKey = shift;

    # Test if the value exists
    if ($self->test($strSection, $strKey, $strSubKey))
    {
        # Remove a subkey
        if (defined($strSubKey))
        {
            delete($self->{oContent}{$strSection}{$strKey}{$strSubKey});
        }

        # Remove a key
        if (defined($strKey))
        {
            if (!defined($strSubKey))
            {
                delete($self->{oContent}{$strSection}{$strKey});
            }

            # Remove the section if it is now empty
            if (keys(%{$self->{oContent}{$strSection}}) == 0)
            {
                delete($self->{oContent}{$strSection});
            }
        }

        # Remove a section
        if (!defined($strKey))
        {
            delete($self->{oContent}{$strSection});
        }

        # Record changes
        if (!$self->{bModified})
        {
            $self->{bModified} = true;
            $self->{oContent}{&INI_SECTION_BACKREST}{&INI_KEY_SEQUENCE}++;
        }

        return true;
    }

    return false;
}

####################################################################################################################################
# keys - get the list of keys in a section.
####################################################################################################################################
sub keys
{
    my $self = shift;
    my $strSection = shift;
    my $strSortOrder = shift;

    if ($self->test($strSection))
    {
        if (!defined($strSortOrder) || $strSortOrder eq INI_SORT_FORWARD)
        {
            return (sort(keys(%{$self->get($strSection)})));
        }
        elsif ($strSortOrder eq INI_SORT_REVERSE)
        {
            return (sort {$b cmp $a} (keys(%{$self->get($strSection)})));
        }
        elsif ($strSortOrder eq INI_SORT_NONE)
        {
            return (keys(%{$self->get($strSection)}));
        }
        else
        {
            confess &log(ASSERT, "invalid strSortOrder '${strSortOrder}'");
        }
    }

    my @stryEmptyArray;
    return @stryEmptyArray;
}

####################################################################################################################################
# test - test a value.
#
# Test a value to see if it equals the supplied test value.  If no test value is given, tests that the section, key, or subkey
# is defined.
####################################################################################################################################
sub test
{
    my $self = shift;
    my $strSection = shift;
    my $strValue = shift;
    my $strSubValue = shift;
    my $strTest = shift;

    # Get the value
    my $strResult = $self->get($strSection, $strValue, $strSubValue, false);

    # Is there a result
    if (defined($strResult))
    {
        # Is there a value to test against?
        if (defined($strTest))
        {
            return $strResult eq $strTest ? true : false;
        }

        return true;
    }

    return false;
}

####################################################################################################################################
# boolTest - test a boolean value, see test().
####################################################################################################################################
sub boolTest
{
    return shift->test(shift, shift, shift, defined($_[0]) ? (shift() ? INI_TRUE : INI_FALSE) : undef);
}

####################################################################################################################################
# Properties.
####################################################################################################################################
sub modified {shift->{bModified}}                                   # Has the data been modified since last load/save?
sub exists {shift->{bExists}}                                       # Is the data persisted to file?

1;
