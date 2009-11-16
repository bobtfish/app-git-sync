use strict;
use warnings;
use File::Temp qw/tempdir/;

use Test::More;
use Test::Exception;

use App::Git::Sync::ProjectGatherer::LocalDisk;

my $d = tempdir(CLEANUP => 1);
chdir $d or die $!;

mkdir 'TestProject' or die $!;
chdir 'TestProject' or die $!;
system(qw/git init/) and die;
system(qw|git remote add foo git://foo.bar/TestProject.git|) and die;
system(qw|git remote add origin git://foo.bar.otherplace/TestProject.git|) and die;
chdir $d or die $!;
mkdir 'TestProject2' or die $!;
chdir 'TestProject2' or die $!;
system(qw/git init/) and die;
system(qw|git remote add foo git://foo.bar/TestProject2.git|) and die;
system(qw|git remote add origin git://foo.bar.otherplace/TestProject2.git|) and die;
chdir $d or die $!;

my $i;
lives_ok {
    $i = App::Git::Sync::ProjectGatherer::LocalDisk->new;
};
ok $i;

done_testing;
