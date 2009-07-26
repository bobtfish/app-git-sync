use strict;
use warnings;
use inc::Module::Install 0.91;

name 'App-Git-Sync';
all_from 'lib/App/Git/Sync.pm';

license 'perl';

install_script 'script/git-sync';

requires 'Net::GitHub' => '0.18';
requires 'Moose';
requires 'MooseX::Getopt';
requires 'MooseX::Types::Path::Class';
requires 'Config::INI::Reader';
test_requires 'Test::More';

if ($Module::Install::AUTHOR) {
    system("pod2text lib/App/Git/Sync.pm > README")
        and die;
}

WriteAll;

