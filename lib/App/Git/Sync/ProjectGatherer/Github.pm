package App::Git::Sync::ProjectGatherer::Github;
use Moose;

with 'App::Git::Sync::ProjectGatherer'; 

sub gather {}

__PACKAGE__->meta->make_immutable;
