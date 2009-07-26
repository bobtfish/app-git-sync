use strict;
use warnings;
use inc::Module::Install 0.91;

name 'App-Git-Sync';
all_from 'lib/App/Git/Sync.pm';

license 'perl';

install_script 'script/git-sync';

requires 'Net::GitHub' => '0.18';
test_requires 'Test::More';

WriteAll;