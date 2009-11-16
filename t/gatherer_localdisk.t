use strict;
use warnings;
use File::Temp qw/tempdir/;
use Scalar::Util qw/blessed/;

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
    $i = App::Git::Sync::ProjectGatherer::LocalDisk->new( gitdir => $d );
};
ok $i;
my $l = $i->gather;
ok $l;
is ref($l), 'ARRAY';
ok scalar @$l;
is scalar( grep { blessed $_ } @$l), scalar(@$l);
my $proj = (grep { $_->name eq 'TestProject'} @$l)[0];
my $proj2 = (grep { $_->name eq 'TestProject2'} @$l)[0];
ok $proj;
ok $proj2;

is_deeply $proj->remotes, { foo => 'git://foo.bar/TestProject.git', origin => 'git://foo.bar.otherplace/TestProject.git' };
is_deeply $proj2->remotes, { foo => 'git://foo.bar/TestProject2.git', origin => 'git://foo.bar.otherplace/TestProject2.git' };

done_testing;
