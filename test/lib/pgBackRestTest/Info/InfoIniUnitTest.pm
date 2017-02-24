####################################################################################################################################
# InfoIniUnitTest.pm - Unit tests for Ini module
####################################################################################################################################
package pgBackRestTest::Info::InfoIniUnitTest;
use parent 'pgBackRestTest::Common::RunTest';

####################################################################################################################################
# Perl includes
####################################################################################################################################
use strict;
use warnings FATAL => qw(all);
use Carp qw(confess);
use English '-no_match_vars';

# use File::Basename qw(dirname);
# use Storable qw(dclone);
#
# use pgBackRest::BackupInfo;
use pgBackRest::Common::Exception;
# use pgBackRest::Common::Lock;
use pgBackRest::Common::Ini;
use pgBackRest::Common::Log;
# use pgBackRest::Config::Config;
# use pgBackRest::DbVersion;
# use pgBackRest::File;
use pgBackRest::FileCommon;
# use pgBackRest::Info;
# use pgBackRest::Protocol::Common;
# use pgBackRest::Protocol::Protocol;
use pgBackRest::Version;
#
# use pgBackRestTest::Common::Env::EnvHostTest;
# use pgBackRestTest::Common::ExecuteTest;
# use pgBackRestTest::Common::Host::HostBackupTest;
use pgBackRestTest::Common::RunTest;
# use pgBackRestTest::Expire::ExpireEnvTest;

####################################################################################################################################
# iniHeader
####################################################################################################################################
sub iniHeader
{
    my $self = shift;
    my $oIni = shift;
    my $iSequence = shift;
    my $iFormat = shift;
    my $iVersion = shift;
    my $strChecksum = shift;

    return
        "[backrest]" .
        "\nbackrest-checksum=\"" .
            (defined($strChecksum) ? $strChecksum : $oIni->get(INI_SECTION_BACKREST, INI_KEY_CHECKSUM)) . "\"" .
        "\nbackrest-format=" . (defined($iFormat) ? $iFormat : $oIni->get(INI_SECTION_BACKREST, INI_KEY_FORMAT)) .
        "\nbackrest-sequence=" . (defined($iSequence) ? $iSequence : $oIni->get(INI_SECTION_BACKREST, INI_KEY_SEQUENCE)) .
        "\nbackrest-version=\"" . (defined($iVersion) ? $iVersion : $oIni->get(INI_SECTION_BACKREST, INI_KEY_VERSION)) . "\"" .
        "\n";
}

####################################################################################################################################
# run
####################################################################################################################################
sub run
{
    my $self = shift;

    # Test ini file
    my $strTestFile = $self->testPath() . '/test.ini';

    # Test keys, values
    my $strSection = 'test-section';
    my $strKey = 'test-key';
    my $strSubKey = 'test-subkey';
    my $strValue = 'test-value';

    ################################################################################################################################
    if ($self->begin("Ini->new()"))
    {
        #---------------------------------------------------------------------------------------------------------------------------
        my $oIni = new pgBackRest::Common::Ini(
            $strTestFile, {bLoad => false, hInit => {&INI_KEY_FORMAT => 4, &INI_KEY_VERSION => '1.01'}});
        $oIni->saveCopy();

        $self->testResult(
            sub {fileStringRead($strTestFile . INI_COPY_EXT)},
            $self->iniHeader(undef, 1, 4, '1.01', '488e5ca1a018cd7cd6d4e15150548f39f493dacd'),
            'empty with synthetic format and version');

        #---------------------------------------------------------------------------------------------------------------------------
        $oIni = new pgBackRest::Common::Ini($strTestFile, {bLoad => false});
        $oIni->saveCopy();

        $self->testResult(
            sub {fileStringRead($strTestFile . INI_COPY_EXT)},
            $self->iniHeader(undef, 1, BACKREST_FORMAT, BACKREST_VERSION, $oIni->hash()),
            'empty with default format and version');

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(
            sub {fileList($self->testPath())},
            'test.ini.copy',
            'only copy is saved');

        $oIni->save();

        $self->testResult(
            sub {fileList($self->testPath())},
            '(test.ini, test.ini.copy)',
            'both versions are saved');

        $self->testException(
            sub {$oIni->saveCopy()}, ERROR_ASSERT,
            "cannot save copy only when '${strTestFile}' exists");

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {new pgBackRest::Common::Ini($strTestFile)}, '[object]', 'normal load');

        #---------------------------------------------------------------------------------------------------------------------------
        my $hIni = iniLoad($strTestFile);
        $hIni->{&INI_SECTION_BACKREST}{&INI_KEY_CHECKSUM} = BOGUS;
        iniSave($strTestFile, $hIni);

        $self->testException(
            sub {new pgBackRest::Common::Ini($strTestFile)}, ERROR_CHECKSUM,
            "invalid checksum in '${strTestFile}', expected '" .
                $oIni->get(INI_SECTION_BACKREST, INI_KEY_CHECKSUM) . "' but found 'bogus'");

        $hIni->{&INI_SECTION_BACKREST}{&INI_KEY_CHECKSUM} = $oIni->hash();
        iniSave($strTestFile, $hIni);

        #---------------------------------------------------------------------------------------------------------------------------
        $oIni->numericSet(INI_SECTION_BACKREST, INI_KEY_FORMAT, undef, BACKREST_FORMAT - 1);
        $oIni->save();

        $self->testException(
            sub {new pgBackRest::Common::Ini($strTestFile)}, ERROR_FORMAT,
            "invalid format in '${strTestFile}', expected " . BACKREST_FORMAT . ' but found ' . (BACKREST_FORMAT - 1));

        $oIni->numericSet(INI_SECTION_BACKREST, INI_KEY_FORMAT, undef, BACKREST_FORMAT);
        $oIni->save();

        #---------------------------------------------------------------------------------------------------------------------------
        $oIni->set(INI_SECTION_BACKREST, INI_KEY_VERSION, undef, '1.01');
        $oIni->save();

        $self->testResult(
            sub {fileStringRead($strTestFile . INI_COPY_EXT)},
            $self->iniHeader($oIni, undef, undef, '1.01'),
            'verify old version was written');

        $oIni = new pgBackRest::Common::Ini($strTestFile);

        $self->testResult(sub {$oIni->get(INI_SECTION_BACKREST, INI_KEY_VERSION)}, BACKREST_VERSION, 'version is updated on load');
        $oIni->save();

        $self->testResult(
            sub {fileStringRead($strTestFile . INI_COPY_EXT)},
            $self->iniHeader($oIni, undef, undef, BACKREST_VERSION),
            'verify version is updated on load');

        $self->testResult(sub {$oIni->save()}, "0", 'save again with no changes');
    }

    ################################################################################################################################
    if ($self->begin("Ini->set()"))
    {
        my $oIni = new pgBackRest::Common::Ini($strTestFile, {bLoad => false});

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testException(sub {$oIni->set()}, ERROR_ASSERT, 'strSection, strKey, and strValue are required');
        $self->testException(sub {$oIni->set($strSection)}, ERROR_ASSERT, 'strSection, strKey, and strValue are required');
        $self->testException(sub {$oIni->set(undef, $strKey)}, ERROR_ASSERT, 'strSection, strKey, and strValue are required');
        $self->testException(sub {$oIni->set($strSection, $strKey)}, ERROR_ASSERT, 'strSection, strKey, and strValue are required');

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oIni->set($strSection, $strKey, undef, $strValue)}, "", 'set key value');
        $self->testResult(sub {$oIni->set($strSection, $strKey, undef, $strValue)}, "", 'set same key value');
        $self->testResult(sub {$oIni->set($strSection, $strKey, undef, "${strValue}2")}, "", 'set different key value');

        $self->testResult(sub {$oIni->get($strSection, $strKey)}, "${strValue}2", 'get last key value');

        $self->testResult(sub {$oIni->set($strSection, "${strKey}2", $strSubKey, $strValue)}, "", 'set subkey value');
    }

    ################################################################################################################################
    if ($self->begin("Ini->get()"))
    {
        my $oIni = new pgBackRest::Common::Ini($strTestFile, {bLoad => false});

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testException(sub {$oIni->get()}, ERROR_ASSERT, 'strSection is required');

        $self->testException(sub {$oIni->get($strSection)}, ERROR_ASSERT, "strSection '${strSection}' is required but not defined");

        $self->testException(
            sub {$oIni->get($strSection, $strKey, undef)}, ERROR_ASSERT,
            "strSection '${strSection}', strKey '${strKey}' is required but not defined");

        $self->testException(
            sub {$oIni->get($strSection, undef, $strSubKey)}, ERROR_ASSERT,
            "strKey is required when strSubKey '${strSubKey}' is requested");

        $self->testException(
            sub {$oIni->get($strSection, $strKey, $strSubKey, true)}, ERROR_ASSERT,
            "strSection '${strSection}', strKey '${strKey}', strSubKey '${strSubKey}' is required but not defined");

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oIni->get($strSection, undef, undef, false)}, '[undef]', 'section value is not required');

        $self->testResult(sub {$oIni->get($strSection, undef, undef, false, $strValue)}, $strValue, 'section value is defaulted');

        #---------------------------------------------------------------------------------------------------------------------------
        $oIni->set($strSection, $strKey, $strSubKey, $strValue);

        $self->testResult(sub {$oIni->get($strSection, "${strKey}2", "${strSubKey}2", false)}, undef, 'missing key value');

        $self->testResult(sub {$oIni->get($strSection, $strKey, "${strSubKey}2", false)}, undef, 'missing subkey value');

        $self->testResult(sub {$oIni->get($strSection, $strKey, $strSubKey)}, $strValue, 'get subkey value');

        $self->testResult(sub {$oIni->get($strSection, $strKey)}, "{${strSubKey} => ${strValue}}", 'get key value');

        $self->testResult(sub {$oIni->get($strSection)}, "{${strKey} => {${strSubKey} => ${strValue}}}", 'get section value');
    }
}

1;
