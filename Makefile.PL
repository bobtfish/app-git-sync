use strict;
use warnings;
use inc::Module::Install 0.91;

name 'App-Git-Sync';
all_from 'lib/App/Git/Sync.pm';

license 'perl';

install_script 'script/git-sync';

requires 'Net::GitHub' => '0.18';
requires 'Moose' => '0.88';
requires 'MooseX::Getopt';
requires 'Moose::Autobox';
requires 'MooseX::Types';
requires 'MooseX::Types::Path::Class';
requires 'Config::INI::Reader';
requires 'List::MoreUtils';
requires 'namespace::autoclean';
requires 'aliased';

test_requires 'Test::More' -> '0.88';
test_requires 'Test::Exception';

if ($Module::Install::AUTHOR) {
    system("pod2text lib/App/Git/Sync.pm > README")
        and die;
}

WriteAll;

