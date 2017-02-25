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

use pgBackRest::Common::Exception;
use pgBackRest::Common::Ini;
use pgBackRest::Common::Log;
use pgBackRest::FileCommon;
use pgBackRest::Version;

use pgBackRestTest::Common::RunTest;

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

        $self->testResult($oIni->exists(), false, 'file does not exist');

        $oIni->saveCopy();

        $self->testResult($oIni->exists(), false, 'file does not exist after saveCopy()');

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
        $self->testException(sub {$oIni->set()}, ERROR_ASSERT, 'strSection and strKey are required');
        $self->testException(sub {$oIni->set($strSection)}, ERROR_ASSERT, 'strSection and strKey are required');
        $self->testException(sub {$oIni->set(undef, $strKey)}, ERROR_ASSERT, 'strSection and strKey are required');

        #---------------------------------------------------------------------------------------------------------------------------
        $oIni->{bModified} = false;
        $self->testResult(sub {$oIni->set($strSection, $strKey, undef, $strValue)}, true, 'set key value');
        $self->testResult($oIni->modified(), true, '    check changed flag = true');

        #---------------------------------------------------------------------------------------------------------------------------
        $oIni->{bModified} = false;
        $self->testResult(sub {$oIni->set($strSection, $strKey, undef, $strValue)}, false, 'set same key value');
        $self->testResult($oIni->modified(), false, '    check changed flag remains false');

        #---------------------------------------------------------------------------------------------------------------------------
        $oIni->{bModified} = false;
        $self->testResult(sub {$oIni->set($strSection, $strKey, undef, "${strValue}2")}, true, 'set different key value');
        $self->testResult($oIni->modified(), true, '    check changed flag = true');

        $self->testResult(sub {$oIni->get($strSection, $strKey)}, "${strValue}2", 'get last key value');

        #---------------------------------------------------------------------------------------------------------------------------
        $oIni->{bModified} = false;
        $self->testResult(sub {$oIni->set($strSection, $strKey, undef, undef)}, true, 'set undef key value');
        $self->testResult($oIni->modified(), true, '    check changed flag = true');

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oIni->set($strSection, "${strKey}2", $strSubKey, $strValue)}, true, 'set subkey value');
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

    ################################################################################################################################
    if ($self->begin("Ini->remove()"))
    {
        my $oIni = new pgBackRest::Common::Ini($strTestFile, {bLoad => false});

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testException(sub {$oIni->remove()}, ERROR_ASSERT, 'strSection is required');

        $self->testException(
            sub {$oIni->remove($strSection, undef, $strSubKey)}, ERROR_ASSERT,
            "strKey is required when strSubKey '${strSubKey}' is requested");

        #---------------------------------------------------------------------------------------------------------------------------
        $oIni->{bModified} = false;
        $self->testResult(sub {$oIni->remove($strSection)}, false, 'undefined section is not removed');
        $self->testResult($oIni->modified(), '0', '    check changed flag remains false');

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oIni->set($strSection, $strKey, undef, $strValue)}, true, 'set key');

        $oIni->{bModified} = false;
        $self->testResult(sub {$oIni->remove($strSection, $strKey)}, true, '    remove key');
        $self->testResult($oIni->modified(), '1', '    check changed flag = true');
        $self->testResult(sub {$oIni->test($strSection, $strKey)}, false, '    test key');
        $self->testResult(sub {$oIni->test($strSection)}, false, '    test section');

        $self->testResult(sub {$oIni->set($strSection, $strKey, undef, $strValue)}, true, 'set key 1');
        $self->testResult(sub {$oIni->set($strSection, "${strKey}2", undef, $strValue)}, true, '    set key 2');
        $self->testResult(sub {$oIni->remove($strSection, $strKey)}, true, '    remove key 1');
        $self->testResult(sub {$oIni->test($strSection, $strKey)}, false, '    test key');
        $self->testResult(sub {$oIni->test($strSection)}, true, '    test section');

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oIni->set($strSection, $strKey, undef, $strValue)}, true, 'set key');

        $self->testResult(sub {$oIni->remove($strSection)}, true, '    remove section');
        $self->testResult(sub {$oIni->test($strSection)}, false, '    test section');

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oIni->set($strSection, $strKey, $strSubKey, $strValue)}, true, 'set subkey');

        $self->testResult(sub {$oIni->remove($strSection, $strKey, $strSubKey)}, true, '    remove subkey');
        $self->testResult(sub {$oIni->test($strSection, $strKey, $strSubKey)}, false, '    test subkey');
        $self->testResult(sub {$oIni->test($strSection, $strKey)}, true, '    test key');
        $self->testResult(sub {$oIni->test($strSection)}, true, '    test section');

        $self->testResult(sub {$oIni->set($strSection, $strKey, $strSubKey, $strValue)}, true, 'set subkey 1');
        $self->testResult(sub {$oIni->set($strSection, $strKey, "${strSubKey}2", $strValue)}, true, 'set subkey 2');

        $self->testResult(sub {$oIni->remove($strSection, $strKey, $strSubKey)}, true, '    remove subkey');
        $self->testResult(sub {$oIni->test($strSection, $strKey, $strSubKey)}, false, '    test subkey');
        $self->testResult(sub {$oIni->test($strSection, $strKey)}, true, '    test key');
        $self->testResult(sub {$oIni->test($strSection)}, true, '    test section');
    }

    ################################################################################################################################
    if ($self->begin("Ini->test()"))
    {
        my $oIni = new pgBackRest::Common::Ini($strTestFile, {bLoad => false});

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oIni->test($strSection, $strKey)}, false, 'test undefined key');

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oIni->set($strSection, $strKey, undef, $strValue)}, true, 'define key');

        $self->testResult(sub {$oIni->test($strSection, $strKey)}, true, 'test key exists');

        $self->testResult(sub {$oIni->test($strSection, $strKey, undef, $strValue)}, true, 'test key value');

        $self->testResult(sub {$oIni->test($strSection, $strKey, undef, BOGUS)}, false, 'test key invalid value');
    }

    ################################################################################################################################
    if ($self->begin("Ini->boolSet() & Ini->boolGet() & Ini->boolTest()"))
    {
        my $oIni = new pgBackRest::Common::Ini($strTestFile, {bLoad => false});

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oIni->boolTest($strSection, $strKey)}, false, 'test bool on undefined key');

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oIni->boolGet($strSection, $strKey, undef, false, false)}, false, 'get bool default false value');
        $self->testResult(sub {$oIni->boolGet($strSection, $strKey, undef, false, true)}, true, 'get bool default true value');

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oIni->boolSet($strSection, $strKey, undef, undef)}, true, 'set bool false (undef) value');
        $self->testResult(sub {$oIni->boolGet($strSection, $strKey)}, false, '    check bool false value');

        $self->testResult(sub {$oIni->boolTest($strSection, $strKey, undef, false)}, true, 'test bool on false key');

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oIni->boolSet($strSection, $strKey, undef, false)}, false, 'set bool false value');
        $self->testResult(sub {$oIni->boolGet($strSection, $strKey)}, false, '    check value');

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oIni->boolSet($strSection, $strKey, undef, true)}, true, 'set bool false value');
        $self->testResult(sub {$oIni->boolGet($strSection, $strKey)}, true, '    check value');

        $self->testResult(sub {$oIni->boolTest($strSection, $strKey, undef, true)}, true, 'test bool on true key');
    }

    ################################################################################################################################
    if ($self->begin("Ini->numericSet() & Ini->numericGet() & Ini->numericTest()"))
    {
        my $oIni = new pgBackRest::Common::Ini($strTestFile, {bLoad => false});

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oIni->numericSet($strSection, $strKey)}, true, 'set numeric undef value');
        $self->testResult(sub {$oIni->test($strSection, $strKey)}, false, 'test numeric undef value');

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oIni->numericGet($strSection, $strKey, undef, false, 1000)}, 1000, 'get numeric default value');

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oIni->numericSet($strSection, $strKey, undef, 0)}, true, 'set numeric 0 value');
        $self->testResult(sub {$oIni->numericGet($strSection, $strKey)}, 0, '    check value');

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oIni->numericSet($strSection, $strKey, undef, 0)}, false, 'set numeric 0 value again');
        $self->testResult(sub {$oIni->numericGet($strSection, $strKey)}, 0, '    check value');

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oIni->numericSet($strSection, $strKey, undef, -100)}, true, 'set numeric -100 value');
        $self->testResult(sub {$oIni->numericGet($strSection, $strKey)}, -100, '    check value');
    }

    ################################################################################################################################
    if ($self->begin("Ini->keys()"))
    {
        my $oIni = new pgBackRest::Common::Ini($strTestFile, {bLoad => false});

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oIni->keys($strSection)}, '[undef]', 'section undefined');

        #---------------------------------------------------------------------------------------------------------------------------
        $oIni->set($strSection, 'a', undef, $strValue);
        $oIni->set($strSection, 'c', undef, $strValue);
        $oIni->set($strSection, 'b', undef, $strValue);

        #---------------------------------------------------------------------------------------------------------------------------
        $self->testResult(sub {$oIni->keys($strSection)}, '(a, b, c)', 'sort forward (default)');

        $self->testResult(sub {$oIni->keys($strSection, INI_SORT_FORWARD)}, '(a, b, c)', 'sort forward');

        $self->testResult(sub {$oIni->keys($strSection, INI_SORT_REVERSE)}, '(c, b, a)', 'sort reverse');

        $self->testResult(sub {sort($oIni->keys($strSection, INI_SORT_NONE))}, '(a, b, c)', 'sort none');

        $self->testException(sub {sort($oIni->keys($strSection, BOGUS))}, ERROR_ASSERT, "invalid strSortOrder '" . BOGUS . "'");
    }
}

1;
