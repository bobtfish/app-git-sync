package App::Git::Sync::Types;
use strict;
use MooseX::Types -declare => [qw/
    ProjectGatherer
/];

role_type 'App::Git::Sync::ProjectGatherer';
subtype ProjectGatherer, as 'App::Git::Sync::ProjectGatherer', where { 1 };

1;
