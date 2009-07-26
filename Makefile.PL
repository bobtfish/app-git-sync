use strict;
use warnings;
use inc::Module::Install 0.91;

name 'App-Git-Sync';
all_from 'lib/App/Git/Sync.pm';

license 'perl';

requires 'Net::GitHub';
test_requires 'Test::More';

WriteAll;
