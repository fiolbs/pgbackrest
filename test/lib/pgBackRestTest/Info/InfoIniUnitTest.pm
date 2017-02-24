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

    ################################################################################################################################
    if ($self->begin("Ini->new"))
    {
        my $strTestFile = $self->testPath() . '/test.ini';

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

        #---------------------------------------------------------------------------------------------------------------------------
    }
}

1;
