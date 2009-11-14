use strict;
use warnings;
use File::Temp qw/tempdir/;

use Test::More;
use Test::Exception;

use App::Git::Sync::Repos;

my $d = tempdir(CLEANUP => 1);
chdir $d or die $!;

mkdir 'TestProject' or die $!;
chdir 'TestProject' or die $!;
system(qw/git init/) and die;

chdir $d or die $!;

{
    my $repos;
    lives_ok { $repos = App::Git::Sync::Repos->new(gitdir => $d, name => 'TestProject') };
    ok $repos;
    is_deeply $repos->remotes, {};
}

chdir 'TestProject' or die $!;
system(qw|git remote add foo git://foo.bar/TestProject.git|) and die;
chdir $d or die $!;

{
    my $repos;
    lives_ok { $repos = App::Git::Sync::Repos->new(gitdir => $d, name => 'TestProject') };
    ok $repos;
    is_deeply $repos->remotes, { foo => 'git://foo.bar/TestProject.git' };
    is_deeply [$repos->remote_uris], ['git://foo.bar/TestProject.git'];
}

chdir 'TestProject' or die $!;
system(qw|git remote add origin git://foo.bar.otherplace/TestProject.git|) and die;
chdir $d or die $!;

{
    my $repos;
    lives_ok { $repos = App::Git::Sync::Repos->new(gitdir => $d, name => 'TestProject') };
    ok $repos;
    is_deeply $repos->remotes, { foo => 'git://foo.bar/TestProject.git', origin => 'git://foo.bar.otherplace/TestProject.git', };
    is_deeply [ sort $repos->remote_uris ], [sort 'git://foo.bar/TestProject.git', 'git://foo.bar.otherplace/TestProject.git'];
}

done_testing;
