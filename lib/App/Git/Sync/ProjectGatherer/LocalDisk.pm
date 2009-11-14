package App::Git::Sync::ProjectGatherer::LocalDisk;
use Moose;

with 'App::Git::Sync::ProjectGatherer';

sub gather {}

__PACKAGE__->meta->make_immutable;
