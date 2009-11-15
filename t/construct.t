use strict;
use warnings;
use Test::More;
use Test::Exception;

use App::Git::Sync;

my $sync;
lives_ok { $sync = App::Git::Sync->new(github_user => 'bobtfish', github_token => 'foo') };
ok $sync;

done_testing;
